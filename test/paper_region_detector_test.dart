import 'dart:typed_data';
import 'dart:ui';

import 'package:docscanner/src/services/document_edges.dart';
import 'package:docscanner/src/services/paper_region_detector.dart';
import 'package:doclens/doclens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

/// A sheet that runs off the right and bottom edges, on dark blue cloth,
/// with printed table lines.
Uint8List sheetOffTwoEdges() {
  final image = img.Image(width: 640, height: 360);
  img.fill(image, color: img.ColorRgb8(60, 70, 110));
  // Sheet polygon: TL (45,22), top edge to (640,8), right/bottom off frame,
  // left edge down to (35,360).
  for (var y = 0; y < 360; y++) {
    final left = 45 - (10 * y / 360);
    for (var x = 0; x < 640; x++) {
      final topEdge = 22 - 14 * (x - 45) / 595;
      if (x >= left && y >= topEdge) {
        image.setPixelRgb(x, y, 236, 236, 232);
      }
    }
  }
  for (var r = 0; r < 8; r++) {
    final y = 80 + r * 28;
    for (var x = 90; x < 560; x++) {
      image.setPixelRgb(x, y, 30, 30, 30);
    }
  }
  return Uint8List.fromList(img.encodePng(image));
}

void main() {
  test('finds a sheet that runs off two frame edges', () {
    final region = PaperRegionDetector.detectBytes(sheetOffTwoEdges())!;
    expect(region.paperFraction, greaterThan(.8));
    final q = region.detection!.quad!;
    expect(q.topLeft.dx, closeTo(45 / 640, .03));
    expect(q.topLeft.dy, closeTo(22 / 360, .04));
    expect(q.topRight.dx, greaterThan(.97));
    expect(q.bottomRight.dx, greaterThan(.97));
    expect(q.bottomRight.dy, greaterThan(.97));
    expect(q.bottomLeft.dy, greaterThan(.97));
    expect(q.bottomLeft.dx, closeTo(35 / 640, .03));
  });

  test('a photo that is all paper gives no crop but counts as paper', () {
    final image = img.Image(width: 300, height: 400);
    img.fill(image, color: img.ColorRgb8(240, 240, 236));
    for (var y = 40; y < 360; y += 20) {
      for (var x = 30; x < 270; x++) {
        image.setPixelRgb(x, y, 20, 20, 20);
      }
    }
    final region = PaperRegionDetector.detectBytes(
        Uint8List.fromList(img.encodePng(image)));
    expect(region?.detection, isNull);
  });

  Quad rect(double l, double t, double r, double b) => Quad(
    topLeft: Offset(l, t), topRight: Offset(r, t),
    bottomRight: Offset(r, b), bottomLeft: Offset(l, b));
  ImageDetection det(Quad q) =>
      ImageDetection(quad: q, imageSize: const Size(1000, 1000));

  test('paper replaces an inner table box but not a card on paper', () {
    final sheet = det(rect(.05, .05, 1, 1));
    expect(DocumentEdges.paperRegionBeats(sheet, det(rect(.1, .1, .8, .7))),
        isTrue);
    // ID card lying on the sheet: keep the card.
    expect(DocumentEdges.paperRegionBeats(sheet, det(rect(.3, .3, .7, .55))),
        isFalse);
    // Same outline: nothing to change.
    expect(DocumentEdges.paperRegionBeats(sheet, det(rect(.05, .05, .99, .99))),
        isFalse);
  });
}
