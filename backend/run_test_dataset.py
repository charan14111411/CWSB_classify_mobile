"""Send every photo in test_dataset/ to the running app and write test_dataset/results.csv.

Start the app first (run_app.bat), then:  python run_test_dataset.py
"""
import collections
import csv
import json
import sys
import urllib.request
from pathlib import Path

HERE = Path(__file__).resolve().parent
URL = (sys.argv[1] if len(sys.argv) > 1 else "http://localhost:8765") + "/api/predict"
EXTS = {".jpg", ".jpeg", ".png", ".webp", ".bmp"}
rows, tally = [], collections.Counter()
for folder, truth in (("healthy_closeups", "Healthy"), ("unhealthy_infested_closeups", "Unhealthy")):
    for p in sorted((HERE.parent / "test_dataset" / folder).iterdir()):
        if p.suffix.lower() not in EXTS:
            continue
        req = urllib.request.Request(URL, data=p.read_bytes(), method="POST", headers={"Content-Type": "image/jpeg"})
        with urllib.request.urlopen(req, timeout=600) as r:
            j = json.load(r)
        rows.append({"folder": folder, "file": p.name, "true_label": truth, "app_result": j["label"],
                     "score": j["score"], "quality_note": j["quality_note"] or ""})
        tally[(truth, j["label"])] += 1
        print(f"{p.name:44s} true {truth:9s} -> {j['label']:9s} {j['score']:.3f}", flush=True)
out = HERE.parent / "test_dataset" / "results.csv"
with open(out, "w", newline="") as f:
    w = csv.DictWriter(f, fieldnames=list(rows[0].keys()))
    w.writeheader()
    w.writerows(rows)
print()
for (truth, got), n in sorted(tally.items()):
    print(f"true {truth:9s} app says {got:9s}: {n}")
print("->", out)
