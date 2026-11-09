#!/usr/bin/env bash
set -euo pipefail

# Bundle official open-source Bengali and English OCR models *inside* the APK.
# The app does not fetch document content or OCR models after installation.
mkdir -p assets/tessdata
for language in ben eng; do
  target="assets/tessdata/${language}.traineddata"
  if [ ! -s "$target" ]; then
    curl --fail --location --retry 3 --connect-timeout 15 \
      "https://raw.githubusercontent.com/tesseract-ocr/tessdata_fast/main/${language}.traineddata" \
      --output "$target"
  fi
  test -s "$target"
done
echo 'Bengali and English offline OCR traineddata are available.'
