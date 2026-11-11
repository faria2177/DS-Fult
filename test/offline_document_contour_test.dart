import 'dart:typed_data';

import 'package:docscanner/src/services/offline_document_contour.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

Uint8List _png(img.Image source) => Uint8List.fromList(img.encodePng(source));

void _rect(img.Image source, int left, int top, int right, int bottom,
    img.ColorRgb8 colour) {
  img.fillRect(source, x1: left, y1: top,
      x2: right - 1, y2: bottom - 1, color: colour);
}

void main() {
  test('Offline detector isolates a gold card from ruled notebook lines', () {
    final photo = img.Image(width: 320, height: 420);
    img.fill(photo, color: img.ColorRgb8(224, 224, 219));
    for (var y = 24; y < 420; y += 37) {
      _rect(photo, 0, y, 320, y + 2, img.ColorRgb8(103, 111, 146));
    }
    _rect(photo, 75, 77, 258, 358, img.ColorRgb8(194, 168, 114));
    _rect(photo, 134, 159, 205, 244, img.ColorRgb8(36, 61, 65));
    final result = OfflineDocumentContour.detectBytes(_png(photo));
    expect(result?.quad, isNotNull);
    final q = result!.quad!;
    expect(q.topLeft.dx, closeTo(75 / 320, .05));
    expect(q.topLeft.dy, closeTo(77 / 420, .05));
    expect(q.bottomRight.dx, closeTo(257 / 320, .05));
    expect(q.bottomRight.dy, closeTo(357 / 420, .05));
  });

  test('Offline detector isolates white ID plastic on black tabletop', () {
    final photo = img.Image(width: 420, height: 320);
    img.fill(photo, color: img.ColorRgb8(35, 36, 39));
    _rect(photo, 64, 76, 360, 244, img.ColorRgb8(232, 232, 229));
    for (var y = 103; y < 224; y += 21) {
      _rect(photo, 122, y, 330, y + 3, img.ColorRgb8(48, 48, 48));
    }
    final result = OfflineDocumentContour.detectBytes(_png(photo));
    expect(result?.quad, isNotNull);
    final q = result!.quad!;
    expect(q.topLeft.dx, closeTo(64 / 420, .04));
    expect(q.bottomRight.dy, closeTo(243 / 320, .04));
    final detail = OfflineDocumentContour.detectDetailedBytes(_png(photo));
    expect(detail!.borderEvidence, greaterThan(.67));
  });

  test('Same-brightness coloured card is distinguished from the desk', () {
    final photo = img.Image(width: 420, height: 320);
    img.fill(photo, color: img.ColorRgb8(110, 130, 140));
    // The card and desk have similar luminance. Neither the bright/dark
    // thresholds nor the gold-card saturation rule can reliably separate it.
    _rect(photo, 70, 76, 360, 250, img.ColorRgb8(155, 115, 112));
    final result = OfflineDocumentContour.detectDetailedBytes(_png(photo));
    expect(result?.detection.quad, isNotNull);
    final q = result!.detection.quad!;
    expect(q.topLeft.dx, closeTo(70 / 420, .05));
    expect(q.bottomRight.dx, closeTo(359 / 420, .05));
    expect(result.borderEvidence, greaterThan(.6));
  });

  test('White ID remains detectable on a saturated blue background', () {
    final photo = img.Image(width: 420, height: 320);
    img.fill(photo, color: img.ColorRgb8(54, 102, 180));
    _rect(photo, 60, 72, 360, 246, img.ColorRgb8(229, 226, 217));
    _rect(photo, 132, 117, 196, 195, img.ColorRgb8(72, 86, 105));
    final result = OfflineDocumentContour.detectBytes(_png(photo));
    expect(result?.quad, isNotNull);
    expect(result!.quad!.topLeft.dy, closeTo(72 / 320, .05));
    expect(result.quad!.bottomRight.dx, closeTo(359 / 420, .05));
  });

  test('Offline detector does not mistake a small printed label for a card', () {
    final photo = img.Image(width: 320, height: 420);
    img.fill(photo, color: img.ColorRgb8(235, 235, 233));
    _rect(photo, 125, 181, 208, 231, img.ColorRgb8(200, 159, 89));
    expect(OfflineDocumentContour.detectBytes(_png(photo)), isNull);
  });

  test('Uniform image is left unchanged', () {
    final photo = img.Image(width: 320, height: 420);
    img.fill(photo, color: img.ColorRgb8(229, 228, 226));
    expect(OfflineDocumentContour.detectBytes(_png(photo)), isNull);
  });
}
