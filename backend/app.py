"""CWSB mobile screening app.

Loads the v1 model (ConvNeXt-Tiny), takes one photo (uploaded or captured),
and returns Healthy / Unhealthy / Unsure with a heatmap of the image area
that drove the decision.

Run:   python app.py            (this computer only)
       python app.py --lan      (also reachable from a phone on the same Wi-Fi)
"""
import argparse
import base64
import io
import json
import socket
import threading
from pathlib import Path

import cv2
import numpy as np
import timm
import torch
import torch.nn.functional as F
import uvicorn
from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from fastapi.staticfiles import StaticFiles
from PIL import Image, ImageOps
from starlette.concurrency import run_in_threadpool
from torchvision import transforms

HERE = Path(__file__).resolve().parent
CFG = json.loads((HERE / "model" / "config.json").read_text())
T_LOW, T_HIGH, IMG = CFG["T_low"], CFG["T_high"], CFG["img"]
MAX_BYTES = 30 * 1024 * 1024

# Same preprocessing as training and as src/make_report_pdf.py in the model repo.
MEAN, STD = (0.485, 0.456, 0.406), (0.229, 0.224, 0.225)
eval_tf = transforms.Compose([
    transforms.Resize(IMG + 32), transforms.CenterCrop(IMG),
    transforms.ToTensor(), transforms.Normalize(MEAN, STD)])
disp_tf = transforms.Compose([transforms.Resize(IMG + 32), transforms.CenterCrop(IMG)])

# Photo quality limits, same numbers as the training pipeline.
BLUR_MIN, CLIPPED_MAX, DARK_MAX = 60.0, 0.20, 0.40


def load_model():
    ck = torch.load(HERE / "model" / "cwsb_v1.pt", map_location="cpu", weights_only=False)
    m = timm.create_model(ck["backbone"], pretrained=False, num_classes=2)
    m.load_state_dict(ck["state_dict"])
    return m.eval()


MODEL = load_model()
LOCK = threading.Lock()   # one photo at a time: Grad-CAM uses hooks on the shared model


def quality_note(pil):
    g = cv2.cvtColor(np.asarray(pil), cv2.COLOR_RGB2GRAY)
    s = 1024 / max(g.shape[1], 1)
    if s < 1:
        g = cv2.resize(g, (1024, max(int(g.shape[0] * s), 1)))
    if float(cv2.Laplacian(g, cv2.CV_64F).var()) < BLUR_MIN:
        return "The photo looks blurry. Hold steady and retake for a more reliable result."
    if float((g > 250).mean()) > CLIPPED_MAX:
        return "Too much glare. Shade the plant and retake for a more reliable result."
    if float((g < 15).mean()) > DARK_MAX:
        return "The photo is too dark. Retake in better light for a more reliable result."
    return None


def score_and_cam(pil):
    """One forward and one backward pass. Returns (probability of Unhealthy,
    heatmap 0-1 for the class the model chose)."""
    store = {}

    def grab(module, inp, out):
        out.retain_grad()
        store["a"] = out

    handle = MODEL.stages[-1].register_forward_hook(grab)
    try:
        logits = MODEL(eval_tf(pil).unsqueeze(0))
        prob = torch.softmax(logits, 1)[0, 1].item()
        chosen = 1 if prob >= T_LOW else 0
        MODEL.zero_grad()
        logits[0, chosen].backward()
    finally:
        handle.remove()
    a, g = store["a"], store["a"].grad
    cam = F.relu((g.mean(dim=(2, 3), keepdim=True) * a).sum(1, keepdim=True))
    cam = F.interpolate(cam, size=(IMG, IMG), mode="bicubic", align_corners=False)[0, 0]
    cam = cam.detach().clamp(min=0).numpy()
    rng = cam.max() - cam.min()
    return prob, ((cam - cam.min()) / rng if rng > 1e-9 else np.zeros_like(cam))


def to_data_url(rgb):
    ok, buf = cv2.imencode(".jpg", cv2.cvtColor(rgb, cv2.COLOR_RGB2BGR), [cv2.IMWRITE_JPEG_QUALITY, 88])
    return "data:image/jpeg;base64," + base64.b64encode(buf.tobytes()).decode()


def analyse(data):
    pil = ImageOps.exif_transpose(Image.open(io.BytesIO(data))).convert("RGB")
    note = quality_note(pil)
    with LOCK:
        prob, cam = score_and_cam(pil)
    photo = np.array(disp_tf(pil))
    heat = cv2.cvtColor(cv2.applyColorMap((cam * 255).astype(np.uint8), cv2.COLORMAP_JET), cv2.COLOR_BGR2RGB)
    alpha = (0.15 + 0.5 * cam)[..., None]                 # stronger colour where the model looked
    overlay = (photo * (1 - alpha) + heat * alpha).astype(np.uint8)
    if prob >= T_HIGH:
        label, detail = "Unhealthy", "Signs of white stem borer are likely."
    elif prob < T_LOW:
        label, detail = "Healthy", "No visible signs of white stem borer."
    else:
        label, detail = "Unsure", "The model cannot decide from this photo. Retake it, or check the plant by hand."
    return {"label": label, "detail": detail, "score": round(prob, 4),
            "t_low": T_LOW, "t_high": T_HIGH, "quality_note": note,
            "photo": to_data_url(photo), "heatmap": to_data_url(overlay),
            "size": f"{pil.width}x{pil.height}"}


app = FastAPI(title="CWSB mobile", docs_url=None, redoc_url=None)
# The Flutter app calls this server from a phone or from another browser origin.
app.add_middleware(CORSMiddleware, allow_origins=["*"], allow_methods=["GET", "POST"], allow_headers=["*"])
WEB = HERE.parent / "flutter_app" / "build" / "web"   # Flutter web build, served at / when present


@app.get("/api/info")
def info():
    return {"model": "cwsb_v1", "backbone": CFG["backbone"], "t_low": T_LOW, "t_high": T_HIGH}


@app.post("/api/predict")
async def predict(request: Request):
    data = await request.body()
    if not data:
        return JSONResponse({"error": "No image was received."}, status_code=400)
    if len(data) > MAX_BYTES:
        return JSONResponse({"error": "The image is larger than 30 MB."}, status_code=413)
    try:
        return await run_in_threadpool(analyse, data)
    except Exception as e:  # unreadable or unsupported image
        return JSONResponse({"error": f"This file could not be read as an image ({type(e).__name__})."}, status_code=400)


if WEB.is_dir():
    app.mount("/", StaticFiles(directory=WEB, html=True), name="web")


def lan_ip():
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        s.connect(("10.255.255.255", 1))
        return s.getsockname()[0]
    except OSError:
        return "this-computer-ip"
    finally:
        s.close()


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--lan", action="store_true", help="allow phones on the same Wi-Fi to open the app")
    ap.add_argument("--port", type=int, default=8765)
    args = ap.parse_args()
    print(f"\n  CWSB mobile is running.\n  On this computer:  http://localhost:{args.port}")
    if args.lan:
        print(f"  Address to type in the phone app (same Wi-Fi):  http://{lan_ip()}:{args.port}")
    print("  Press Ctrl+C to stop.\n")
    uvicorn.run(app, host="0.0.0.0" if args.lan else "127.0.0.1", port=args.port, log_level="warning")
