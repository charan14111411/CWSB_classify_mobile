"""Proof for the ON-DEVICE version: model inside the phone app versus a direct run of v1.

For every photo in plan.json:
  DIRECT  - the photo file is scored on the computer with the model repo's own
            code (src/make_report_pdf.py: load_model, eval_tf), PyTorch, no app.
  PHONE   - the app in the Android emulator, model running inside the app
            (no server). The exact score is the one the app wrote to the device
            log (device_results.json); the pictures are crops of its screen.
Writes on_device_sheet_*.png and on_device_table.csv next to this file.
"""
import csv
import json
import sys
from pathlib import Path

import cv2
import numpy as np
import torch
import torch.nn.functional as F
from PIL import Image, ImageDraw, ImageFont, ImageOps

REPO = Path("D:/Desktop/coffee_Cswb_Model")
sys.path.insert(0, str(REPO / "src"))
import make_report_pdf as M  # the original v1 code  # noqa: E402

HERE = Path(__file__).resolve().parent
SHOTS = HERE / "screenshots_on_device"
T_LOW, T_HIGH = M.T_LOW, M.T_HIGH
model = M.load_model()


def direct(pil):
    """Score + Grad-CAM straight from the PyTorch model, for the class the result shows."""
    store = {}

    def grab(module, inp, out):
        out.retain_grad()
        store["a"] = out

    h = model.stages[-1].register_forward_hook(grab)
    logits = model(M.eval_tf(pil).unsqueeze(0))
    h.remove()
    prob = torch.softmax(logits, 1)[0, 1].item()
    model.zero_grad()
    logits[0, 1 if prob >= T_LOW else 0].backward()
    a, g = store["a"], store["a"].grad
    cam = F.relu((g.mean(dim=(2, 3), keepdim=True) * a).sum(1, keepdim=True))
    cam = F.interpolate(cam, size=(384, 384), mode="bicubic", align_corners=False)[0, 0].detach().clamp(min=0).numpy()
    rng = cam.max() - cam.min()
    return prob, (cam - cam.min()) / rng if rng > 1e-9 else np.zeros_like(cam)


def overlay(photo, cam):
    heat = cv2.cvtColor(cv2.applyColorMap((cam * 255).astype(np.uint8), cv2.COLORMAP_JET), cv2.COLOR_BGR2RGB)
    a = (0.15 + 0.5 * cam)[..., None]
    return (photo * (1 - a) + heat * a).astype(np.uint8)


def label_of(s):
    return "Unhealthy" if s >= T_HIGH else "Healthy" if s < T_LOW else "Unsure"


def heat_corr(a, b):
    """Agreement of the colour (heat) part: red minus blue, pixel by pixel."""
    def f(im):
        x = np.asarray(im.resize((96, 96)), dtype=np.float32)
        return (x[..., 0] - x[..., 2]).ravel()
    return float(np.corrcoef(f(a), f(b))[0, 1])


try:
    FB, FN = ImageFont.truetype("arialbd.ttf", 17), ImageFont.truetype("arial.ttf", 15)
except OSError:
    FB = FN = ImageFont.load_default()

plan = json.load(open(HERE / "plan.json"))
device = {r["n"]: r for r in json.load(open(HERE / "device_results.json"))}
W, RH, table, strips = 1500, 430, [], []
for p in plan:
    pil = ImageOps.exif_transpose(Image.open(p["path"])).convert("RGB")
    score, cam = direct(pil)
    photo = np.array(M.disp_tf(pil))
    d_img = Image.fromarray(overlay(photo, cam))
    dv = device.get(p["n"], {})
    shot = Image.open(SHOTS / f"{p['n']:02d}_b_result.png").convert("RGB")
    # The heatmap's height on the screen depends on the result card above it; find it.
    hc, dy = max((heat_corr(shot.crop((76, 1246 + k, 1004, 2174 + k)).resize((384, 384)), d_img), k) for k in range(0, 226, 2))
    a_heat = shot.crop((76, 1246 + dy, 1004, 2174 + dy)).resize((384, 384))
    a_card = shot.crop((44, 396, 1036, 1010 + dy))
    d_lab = label_of(score)
    p_score, p_lab = dv.get("score"), dv.get("label", "ERROR")
    diff = abs(p_score - score) if p_score is not None else None
    ok = p_lab == d_lab and diff is not None and diff < 0.001 and hc > 0.98
    table.append({"no": p["n"], "file": p["file"], "true_label": p["true_label"],
                  "direct_v1_score": round(score, 5), "phone_score": None if p_score is None else round(p_score, 5),
                  "score_difference": None if diff is None else f"{diff:.6f}",
                  "direct_v1_result": d_lab, "phone_result": p_lab,
                  "heatmap_agreement": round(hc, 4), "phone_seconds": dv.get("seconds"),
                  "match": "YES" if ok else "NO"})
    row = Image.new("RGB", (W, RH), "white")
    d = ImageDraw.Draw(row)
    d.text((10, 6), f"{p['n']}.  {p['file']}     true label: {p['true_label']}", fill="black", font=FB)
    d.text((10, 30), "Photo (as the model sees it)", fill=(90, 90, 90), font=FN)
    d.text((330, 30), f"DIRECT v1:  score {score:.5f}  ->  {d_lab}", fill=(0, 70, 160), font=FN)
    ps = "error" if p_score is None else f"{p_score:.5f}"
    d.text((650, 30), f"PHONE (model inside the app):  score {ps}  ->  {p_lab}", fill=(0, 110, 60), font=FN)
    d.text((1180, 30), "PHONE heatmap (emulator screen)", fill=(0, 110, 60), font=FN)
    row.paste(Image.fromarray(photo).resize((310, 310)), (10, 54))
    row.paste(d_img.resize((310, 310)), (330, 54))
    card = a_card.resize((500, int(a_card.height * 500 / a_card.width)))
    if card.height > 300:
        card = card.crop((0, 0, 500, 300))
    row.paste(card, (650, 54))
    dtxt = "n/a" if diff is None else f"{diff:.6f}"
    d.text((650, 362), f"Score difference: {dtxt}     Heatmap agreement: {hc:.4f}  (1 = identical)", fill="black", font=FN)
    d.text((650, 388), "MATCH" if ok else "DOES NOT MATCH", fill=(0, 130, 60) if ok else (200, 0, 0), font=FB)
    row.paste(a_heat.resize((310, 310)), (1180, 54))
    d.line([0, RH - 1, W, RH - 1], fill=(200, 200, 200))
    strips.append(row)
    print(table[-1], flush=True)

for s in range(0, len(strips), 4):
    part = strips[s:s + 4]
    sheet = Image.new("RGB", (W, RH * len(part)), "white")
    for i, r in enumerate(part):
        sheet.paste(r, (0, i * RH))
    sheet.save(HERE / f"on_device_sheet_{s // 4 + 1}.png")
with open(HERE / "on_device_table.csv", "w", newline="") as f:
    w = csv.DictWriter(f, fieldnames=list(table[0].keys()))
    w.writeheader()
    w.writerows(table)
print("matches:", sum(t["match"] == "YES" for t in table), "of", len(table))
