"""Compare the mobile app with a direct run of the v1 model, photo by photo.

For every photo in plan.json:
  DIRECT  - the photo file is scored here with the model repo's own code
            (src/make_report_pdf.py: load_model, eval_tf), no app and no server.
  APP     - the screenshot taken from the app in the Android emulator.
Writes proof_sheet_*.png and proof_table.csv next to this file.
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
T_LOW, T_HIGH = M.T_LOW, M.T_HIGH
model = M.load_model()


def direct(pil):
    """Score + Grad-CAM straight from the model, for the class the result shows."""
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


BANNER = {"Healthy": (31, 138, 76), "Unhealthy": (198, 53, 43), "Unsure": (208, 138, 0)}


def app_label(shot):
    """Read the result from the banner colour in the app screenshot."""
    px = np.asarray(shot.crop((60, 410, 120, 440)), dtype=np.float32).reshape(-1, 3).mean(0)
    return min(BANNER, key=lambda k: float(np.abs(px - np.array(BANNER[k])).sum()))


def corr(a, b):
    a = np.asarray(a.convert("L").resize((96, 96)), dtype=np.float32).ravel()
    b = np.asarray(b.convert("L").resize((96, 96)), dtype=np.float32).ravel()
    return float(np.corrcoef(a, b)[0, 1])


def heat_corr(a, b):
    """Agreement of the colour (heat) part only: compare hue-like signal red minus blue."""
    f = lambda im: (np.asarray(im.resize((96, 96)), dtype=np.float32)[..., 0] - np.asarray(im.resize((96, 96)), dtype=np.float32)[..., 2]).ravel()
    return float(np.corrcoef(f(a), f(b))[0, 1])


try:
    FB, FN = ImageFont.truetype("arialbd.ttf", 17), ImageFont.truetype("arial.ttf", 15)
except OSError:
    FB = FN = ImageFont.load_default()

plan = json.load(open(HERE / "plan.json"))
W, RH, table, strips = 1500, 400, [], []
for p in plan:
    pil = ImageOps.exif_transpose(Image.open(p["path"])).convert("RGB")
    score, cam = direct(pil)
    ref_score, _ = M.score_and_cam(model, pil)          # the repo's own function, as a cross-check
    photo = np.array(M.disp_tf(pil))
    d_img = Image.fromarray(overlay(photo, cam))
    shot = Image.open(HERE / "screenshots" / f"{p['n']:02d}_b_result.png").convert("RGB")
    # The heatmap sits lower on the screen when the banner text takes two lines,
    # so find its vertical position by the best agreement.
    hc, dy = max((heat_corr(shot.crop((76, 1246 + k, 1004, 2174 + k)).resize((384, 384)), d_img), k) for k in range(0, 140, 2))
    a_heat = shot.crop((76, 1246 + dy, 1004, 2174 + dy)).resize((384, 384))
    a_card = shot.crop((44, 396, 1036, 1010 + dy))
    a_lab, d_lab = app_label(shot), label_of(score)
    ok = a_lab == d_lab and hc > 0.9
    table.append({"no": p["n"], "file": p["file"], "true_label": p["true_label"],
                  "direct_v1_score": round(score, 4), "repo_function_score": round(ref_score, 4),
                  "direct_v1_result": d_lab, "app_result": a_lab,
                  "app_gauge_should_show": round(score * 100), "heatmap_agreement": round(hc, 3),
                  "match": "YES" if ok else "NO"})
    row = Image.new("RGB", (W, RH), "white")
    d = ImageDraw.Draw(row)
    d.text((10, 6), f"{p['n']}.  {p['file']}     true label: {p['true_label']}", fill="black", font=FB)
    d.text((10, 30), "Photo (as the model sees it)", fill=(90, 90, 90), font=FN)
    d.text((330, 30), f"DIRECT v1:  score {score:.4f}  ->  {d_lab}", fill=(0, 70, 160), font=FN)
    d.text((650, 30), f"APP (emulator):  {a_lab}", fill=(0, 110, 60), font=FN)
    d.text((1180, 30), "APP heatmap (emulator screen)", fill=(0, 110, 60), font=FN)
    row.paste(Image.fromarray(photo).resize((310, 310)), (10, 54))
    row.paste(d_img.resize((310, 310)), (330, 54))
    card = a_card.resize((520, int(a_card.height * 520 / a_card.width)))
    row.paste(card, (650, 54))
    d.text((650, 62 + card.height), f"Heatmap agreement with direct run: {hc:.3f}   (1.000 = identical)",
           fill="black", font=FN)
    d.text((650, 86 + card.height), "MATCH" if ok else "DOES NOT MATCH", fill=(0, 130, 60) if ok else (200, 0, 0), font=FB)
    row.paste(a_heat.resize((310, 310)), (1180, 54))
    d.line([0, RH - 1, W, RH - 1], fill=(200, 200, 200))
    strips.append(row)
    print(table[-1], flush=True)

for s in range(0, len(strips), 4):
    part = strips[s:s + 4]
    sheet = Image.new("RGB", (W, RH * len(part)), "white")
    for i, r in enumerate(part):
        sheet.paste(r, (0, i * RH))
    sheet.save(HERE / f"proof_sheet_{s // 4 + 1}.png")
with open(HERE / "proof_table.csv", "w", newline="") as f:
    w = csv.DictWriter(f, fieldnames=list(table[0].keys()))
    w.writeheader()
    w.writerows(table)
print("matches:", sum(t["match"] == "YES" for t in table), "of", len(table))
