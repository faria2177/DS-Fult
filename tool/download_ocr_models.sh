#!/usr/bin/env bash
set -euo pipefail

# Bundle official open-source Tesseract Bengali model *inside* the APK.
# The app does not fetch document content or OCR models after installation.
mkdir -p assets/tessdata
target='assets/tessdata/ben.traineddata'
if [ ! -s "$target" ]; then
  curl --fail --location --retry 3 --connect-timeout 15 \
    'https://raw.githubusercontent.com/tesseract-ocr/tessdata_fast/main/ben.traineddata' \
    --output "$target"
fi
test -s "$target"
echo 'Bengali offline OCR traineddata is available.'
