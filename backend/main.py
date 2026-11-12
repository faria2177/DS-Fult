"""Private HTTPS-reverse-proxy document-boundary API; never stores images."""
import hmac
import os
from fastapi import FastAPI, Header, HTTPException, Request
from document_detector import create_detector

app = FastAPI(title="DocScanner Boundary API",
              docs_url=None, redoc_url=None, openapi_url=None)
detector = create_detector()

@app.post("/v1/detect")
async def detect(request: Request,
                 x_detector_key: str | None = Header(default=None),
                 x_prefer_card: str | None = Header(default=None)):
    secret = os.environ.get("DOCSCAN_DETECTOR_KEY", "")
    if len(secret) < 24:
        raise HTTPException(status_code=503, detail="Server token not configured")
    if not x_detector_key or not hmac.compare_digest(secret, x_detector_key):
        raise HTTPException(status_code=401, detail="Unauthorized")
    if request.headers.get("content-type", "").split(";")[0] != "image/jpeg":
        raise HTTPException(status_code=415, detail="JPEG required")
    content = bytearray()
    async for chunk in request.stream():
        content.extend(chunk)
        if len(content) > 1600000:
            raise HTTPException(status_code=413, detail="Image too large")
    if not content:
        raise HTTPException(status_code=400, detail="Empty JPEG")
    return detector.detect(bytes(content), x_prefer_card == "true")
