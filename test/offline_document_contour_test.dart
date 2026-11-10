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
