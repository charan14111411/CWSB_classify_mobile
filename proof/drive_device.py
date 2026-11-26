"""Upload the proof photos one by one in the emulator app, with the model running INSIDE the phone.

For each photo: push it to the emulator gallery, open the app, Upload image, pick it, Proceed,
read the exact score the app wrote to the device log, and save a screenshot of the result.
"""
import json
import os
import re
import subprocess
import time
from pathlib import Path

ADB = os.path.expandvars(r"%LOCALAPPDATA%\Android\Sdk\platform-tools\adb.exe")
HERE = Path(__file__).resolve().parent
OUT = HERE / "screenshots_on_device"
OUT.mkdir(exist_ok=True)
PKG = "com.vayublue.cwsb_mobile"


def adb(*a, out=None):
    r = subprocess.run([ADB, *a], capture_output=True, timeout=180)
    if out:
        Path(out).write_bytes(r.stdout)
    return r.stdout.decode(errors="replace")


plan = json.load(open(HERE / "plan.json"))
results = []
for p in plan:
    dev = f"/sdcard/Pictures/cwsb_test/dev_{p['n']:02d}_{int(time.time())}.jpg"
    adb("push", p["path"], dev)
    adb("shell", f"touch {dev}; am broadcast -a android.intent.action.MEDIA_SCANNER_SCAN_FILE -d file://{dev}")
    time.sleep(4)
    adb("shell", "am", "force-stop", PKG)
    adb("logcat", "-c")
    adb("shell", "monkey", "-p", PKG, "-c", "android.intent.category.LAUNCHER", "1")
    time.sleep(9)
    adb("shell", "input", "tap", "300", "1540")   # Upload image
    time.sleep(5)
    adb("shell", "input", "tap", "176", "1580")   # newest photo (top-left)
    time.sleep(5)
    adb("exec-out", "screencap", "-p", out=OUT / f"{p['n']:02d}_a_selected.png")
    adb("shell", "input", "tap", "780", "1462")   # Proceed
    found = None
    for _ in range(90):
        time.sleep(2)
        m = re.findall(r"CWSB_(RESULT|ERROR) (.*)", adb("logcat", "-d", "-s", "flutter:*"))
        if m:
            found = m[-1]
            break
    time.sleep(3)
    adb("exec-out", "screencap", "-p", out=OUT / f"{p['n']:02d}_b_result.png")
    rec = {"n": p["n"], "file": p["file"]}
    if found and found[0] == "RESULT":
        rec.update(json.loads(found[1].strip()))
    else:
        rec["error"] = found[1].strip() if found else "no result within 3 minutes"
    results.append(rec)
    json.dump(results, open(HERE / "device_results.json", "w"), indent=1)
    print(rec, flush=True)
print("ALL DONE", flush=True)
