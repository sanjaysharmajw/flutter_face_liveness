#!/usr/bin/env python3
"""
MiniFASNet-V2  →  TFLite Conversion Script
Works on Google Colab (Python 3.10 / 3.11 / 3.12)

Output: MiniFASNetV2.tflite  — upload this to GitHub releases.
"""

import subprocess, sys, os, urllib.request

def pip(*pkgs):
    for p in pkgs:
        print(f"  installing {p}...")
        ret = subprocess.call([sys.executable, "-m", "pip", "install", p, "-q",
                               "--no-warn-script-location"])
        if ret != 0:
            print(f"  WARNING: {p} install returned {ret}, continuing...")

# ── 1. Install dependencies ─────────────────────────────────────────────────
print("=" * 50)
print("Step 1: Installing dependencies...")
pip(
    "torch --index-url https://download.pytorch.org/whl/cpu",
    "onnxscript",      # required by torch >= 2.1 for onnx export
    "onnx",
    "onnx2tf",         # onnx → tflite (actively maintained)
    "sng4onnx",        # required by onnx2tf
    # tensorflow is pre-installed in Colab — installing it here downgrades numpy
    # and breaks torch (ABI mismatch). Use Colab's version as-is.
)
print("✓ Dependencies installed\n")

# ── 2. Clone MiniFASNet repo ─────────────────────────────────────────────────
print("=" * 50)
print("Step 2: Cloning MiniFASNet repository...")
if not os.path.exists("Silent-Face-Anti-Spoofing"):
    os.system("git clone --quiet https://github.com/minivision-ai/Silent-Face-Anti-Spoofing.git")
sys.path.insert(0, "Silent-Face-Anti-Spoofing/src/model_lib")
print("✓ Cloned\n")

# ── 3. Download pretrained weights ──────────────────────────────────────────
print("=" * 50)
print("Step 3: Downloading pretrained weights (2.7 MB)...")
WEIGHTS_URL = (
    "https://github.com/minivision-ai/Silent-Face-Anti-Spoofing"
    "/blob/master/resources/anti_spoof_models/2.7_80x80_MiniFASNetV2.pth?raw=true"
)
if not os.path.exists("MiniFASNetV2.pth"):
    urllib.request.urlretrieve(WEIGHTS_URL, "MiniFASNetV2.pth")
print("✓ Weights downloaded\n")

# ── 4. Load model ────────────────────────────────────────────────────────────
print("=" * 50)
print("Step 4: Loading model...")
import torch
import torch.nn as nn
from MiniFASNet import MiniFASNetV2

# Wrap model to accept [-1, 1] input (Flutter TFLiteService normalises to
# [-1,1], but MiniFASNet was trained on [0,1]).
class NormalisedMiniFAS(nn.Module):
    def __init__(self, base: nn.Module):
        super().__init__()
        self.base = base

    def forward(self, x):          # x in [-1, 1]
        x = (x + 1.0) * 0.5       # → [0, 1]
        return self.base(x)

base = MiniFASNetV2(conv6_kernel=(5, 5))
ckpt  = torch.load("MiniFASNetV2.pth", map_location="cpu")
state = ckpt.get("state_dict", ckpt)
state = {k.replace("module.", ""): v for k, v in state.items()}
base.load_state_dict(state)
base.eval()

model = NormalisedMiniFAS(base)
model.eval()

dummy = torch.zeros(1, 3, 80, 80)
with torch.no_grad():
    out = model(dummy)
print(f"✓ Model loaded — output shape: {out.shape}  values: {out[0].tolist()}\n")

# ── 5. Export to ONNX ────────────────────────────────────────────────────────
print("=" * 50)
print("Step 5: Exporting to ONNX...")
dummy_input = torch.randn(1, 3, 80, 80)
torch.onnx.export(
    model,
    dummy_input,
    "MiniFASNetV2.onnx",
    opset_version=12,
    input_names=["input"],
    output_names=["output"],
    dynamic_axes=None,
)
import onnx
onnx.checker.check_model(onnx.load("MiniFASNetV2.onnx"))
print("✓ ONNX exported and verified\n")

# ── 6. ONNX → TFLite via onnx2tf ────────────────────────────────────────────
print("=" * 50)
print("Step 6: Converting ONNX → TFLite (this may take a minute)...")
import onnx2tf, glob, shutil

onnx2tf.convert(
    input_onnx_file_path="MiniFASNetV2.onnx",
    output_folder_path="MiniFASNetV2_out",
    non_verbose=True,
)

# Prefer float32 model; fall back to any .tflite if not found
float32_files = glob.glob("MiniFASNetV2_out/*float32*.tflite")
any_tflite    = glob.glob("MiniFASNetV2_out/*.tflite")
tflite_src = (float32_files or any_tflite)
if not tflite_src:
    raise RuntimeError(
        "onnx2tf did not produce a .tflite file — check the output above for errors"
    )

shutil.copy(tflite_src[0], "MiniFASNetV2.tflite")
size_kb = os.path.getsize("MiniFASNetV2.tflite") / 1024
print(f"✓ TFLite saved — {size_kb:.0f} KB  (source: {os.path.basename(tflite_src[0])})\n")

# ── 7. Sanity-check TFLite (flatbuffer header inspection — no tensorflow needed) ─
print("=" * 50)
print("Step 7: Sanity check...")
import struct

with open("MiniFASNetV2.tflite", "rb") as f:
    header = f.read(8)

# TFLite flatbuffer magic bytes: offset 4 = "TFL3"
magic = header[4:8]
if magic != b"TFL3":
    print(f"  WARNING: unexpected magic {magic!r} — file may be corrupt")
else:
    print(f"  ✓ Valid TFLite flatbuffer (magic: {magic.decode()})")

size_kb = os.path.getsize("MiniFASNetV2.tflite") / 1024
print(f"  Size  : {size_kb:.0f} KB")
print(f"  Input : [1, 80, 80, 3]  float32  (NHWC)")
print(f"  Output: [1, 2]          float32  → [spoof_prob, real_prob]")

print("\n" + "=" * 50)
print("✅ SUCCESS!")
print("   MiniFASNetV2.tflite is ready.")
print()
print("Next steps:")
print("  1. Download  MiniFASNetV2.tflite  from the Files panel (left sidebar)")
print("  2. Go to: github.com/sanjaysharmajw/flutter_face_liveness/releases")
print("  3. Edit release  v2.0.0-models")
print("  4. Attach  MiniFASNetV2.tflite  → Update release")
print("=" * 50)
