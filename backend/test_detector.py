import cv2
import numpy as np
from document_detector import DocumentBoundaryDetector, contrast

def test_rejects_invalid_and_blank():
    detector = DocumentBoundaryDetector()
    assert detector.detect(b"invalid")["success"] is False
    white = np.full((500, 700, 3), 255, np.uint8)
    ok, encoded = cv2.imencode(".jpg", white)
    assert ok and detector.detect(encoded.tobytes())["success"] is False

def test_detects_synthetic_card_on_lined_paper():
    image = np.full((840, 620, 3), 238, np.uint8)
    for y in range(20, 840, 28):
        cv2.line(image, (0, y), (619, y), (200, 165, 140), 1)
    polygon = np.array([[82, 240], [548, 230], [554, 511], [76, 521]])
    cv2.fillConvexPoly(image, polygon, (120, 185, 221))
    ok, encoded = cv2.imencode(".jpg", image)
    assert ok
    result = DocumentBoundaryDetector().detect(encoded.tobytes(), True)
    assert result["success"], result
    corners = result["corners"]
    assert corners["top_left"][0] < .28
    assert corners["top_right"][0] > .70
    assert .60 < corners["bottom_left"][1] < .80

def test_rejects_nonexistent_boundary_contrast():
    image = np.full((400, 500, 3), 255, np.uint8)
    quad = np.array([[70,70],[400,70],[400,310],[70,310]],np.float32)
    assert contrast(image, quad) < .01
