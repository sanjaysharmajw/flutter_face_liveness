#!/usr/bin/env bash
# Downloads the MobileFaceNet TFLite weights into assets/models/.
# Run this ONCE after adding flutter_face_liveness to your project.
#
# Usage (from package root):
#   bash scripts/download_face_model.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ASSET_DIR="$SCRIPT_DIR/../assets/models"
MODEL_FILE="$ASSET_DIR/mobile_face_net.tflite"

mkdir -p "$ASSET_DIR"

if [ -f "$MODEL_FILE" ] && [ "$(wc -c < "$MODEL_FILE")" -gt 100000 ]; then
  echo "Model already present at: $MODEL_FILE"
  exit 0
fi

echo "Downloading MobileFaceNet TFLite (~1.9 MB)..."

# Try known mirrors in order
URLS=(
  "https://github.com/emrekilincarslan/MobileFaceNet/raw/main/MobileFaceNet.tflite"
  "https://github.com/cydas/mobilefacenet-flutter/raw/main/assets/MobileFaceNet.tflite"
)

for URL in "${URLS[@]}"; do
  echo "Trying: $URL"
  if curl -fsSL --retry 2 -L -o "$MODEL_FILE" "$URL" 2>/dev/null; then
    SIZE=$(wc -c < "$MODEL_FILE")
    if [ "$SIZE" -gt 100000 ]; then
      echo "Downloaded successfully: $MODEL_FILE  (${SIZE} bytes)"
      exit 0
    fi
  fi
done

echo ""
echo "Auto-download failed. Please download manually:"
echo ""
echo "  1. Go to: https://github.com/sirius-ai/MobileFaceNet_TF"
echo "     OR: https://github.com/cydas/mobilefacenet-flutter/tree/main/assets"
echo ""
echo "  2. Download the .tflite file"
echo "     Expected input : [1, 112, 112, 3] float32 (values in [-1, 1])"
echo "     Expected output: [1, 128]         float32 (face embedding)"
echo ""
echo "  3. Save it as:  assets/models/mobile_face_net.tflite"
echo ""
exit 1
