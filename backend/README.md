# DocScanner private online document-boundary service

Flutter tries the configured HTTPS endpoint first **only after explicit consent**.
The device sends a resized, EXIF-upright JPEG (maximum 1.6 MB). It receives
normalized top-left, top-right, bottom-right and bottom-left coordinates.
A second geometry check and final high-resolution perspective crop run on-device.

## Deployment

1. Inside the backend folder, build: docker build -t docscanner-boundary .
2. Create a random 32-byte token with: openssl rand -hex 32
3. Run the container with environment variable DOCSCAN_DETECTOR_KEY set to that
   secret, bound to 127.0.0.1:8000. Put a trusted HTTPS reverse proxy in front.
4. On Android visit Scan > More Settings > Online First Auto Crop, enter
   https://your-domain/v1/detect, the matching access token and opt in.
5. The default app configuration does not upload any images, and missing or
   unavailable HTTPS servers trigger the existing offline detectors.

## AI model / expected accuracy

An optional trained document-specific ONNX segmentation model can be mounted
read-only and configured with DOCSCAN_ONNX_MODEL=/model/document.onnx.
Its input must be float32 RGB [1,3,512,512] in range 0..1. It must output a
foreground mask [1,1,H,W], [1,2,H,W] or [H,W]. Other models need adapters.

**No trained weights are bundled.** Without them, the backend uses cautious
OpenCV image processing, identifies engine as "opencv" and returns no result
if confidence is inadequate. This is NOT trained AI and cannot guarantee
CamScanner-equivalent accuracy. The app always falls back offline on failure.
Evaluate with consented images of ID cards, lined notebooks and A4 pages.

## Privacy and security

- The server processes images in memory, does not persist them, and disables
  Uvicorn access logs. Ensure proxies and hosting also avoid image/body logs.
- Configure HTTPS, rate limits, request-size limits and token rotation at proxy.
- Secrets must not be committed to GitHub or bundled in Android build files.
- Revoking the in-app consent immediately prevents future uploads.
- OCR and enhancement remain entirely separate from this detector.

## Tests

Install pytest alongside backend requirements, then run:
python -m pytest test_detector.py
