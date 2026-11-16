import 'dart:io';
import 'dart:typed_data';

import 'package:doclens/doclens.dart';
import 'package:docscanner/src/services/background_contrast_contour.dart';
import 'package:docscanner/src/services/document_edges.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

const _w = 360;
const _h = 640;

img.Image _fabric() {
  final image = img.Image(width: _w, height: _h);
  img.fill(image, color: img.ColorRgb8(35, 30, 70));
  for (var y = 0; y < _h; y += 8) {
    for (var x = ((y ~/ 8) % 2) * 5; x < _w; x += 10) {
      img.fillRect(image, x1: x, y1: y, x2: x + 3, y2: y + 1,
          color: img.ColorRgb8(170, 190, 60));
    }
  }
  return image;
}

img.Image _pinkCheck() {
  final image = img.Image(width: _w, height: _h);
  img.fill(image, color: img.ColorRgb8(215, 120, 140));
  final stripe = img.ColorRgb8(235, 215, 220);
  for (var x = 0; x < _w; x += 64) {
    img.fillRect(image, x1: x, y1: 0, x2: x + 19, y2: _h - 1, color: stripe);
  }
  for (var y = 0; y < _h; y += 64) {
    img.fillRect(image, x1: 0, y1: y, x2: _w - 1, y2: y + 19, color: stripe);
  }
  return image;
}

/// Deterministic beige speckle, like a textured table top.
img.Image _speckle() {
  final image = img.Image(width: _w, height: _h);
  var seed = 12345;
  for (var y = 0; y < _h; y++) {
    for (var x = 0; x < _w; x++) {
      seed = (seed * 1103515245 + 12345) & 0x7fffffff;
      final v = (seed >> 16) % 41 - 20;
      image.setPixelRgb(x, y, (150 + v).clamp(0, 255),
          (140 + v).clamp(0, 255), (85 + v).clamp(0, 255));
    }
  }
  return image;
}

List<img.Point> _poly(List<List<int>> points) =>
    [for (final p in points) img.Point(p[0], p[1])];

Uint8List _png(img.Image image) =>
    Uint8List.fromList(img.encodePng(image));

void _expectCorners(ImageDetection? detection, List<List<int>> truth,
    {double tolerance = .02}) {
  expect(detection, isNotNull);
  final quad = detection!.quad!;
  final found = quad.points;
  for (var i = 0; i < 4; i++) {
    expect(found[i].dx, closeTo(truth[i][0] / _w, tolerance),
        reason: 'corner $i x');
    expect(found[i].dy, closeTo(truth[i][1] / _h, tolerance),
        reason: 'corner $i y');
  }
}

class _NoNativeDetector extends DoclensPlatform {
  @override
  Future<ImageDetection?> detectInImage({
    required String imagePath,
    ScannerConfig config = const ScannerConfig(),
  }) async => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const whiteCard = [[100, 220], [280, 236], [272, 340], [92, 328]];

  img.Image whiteCardOnFabric() {
    final image = _fabric();
    img.fillPolygon(image, vertices: _poly(whiteCard),
        color: img.ColorRgb8(240, 240, 236));
    for (var i = 0; i < 4; i++) {
      img.drawLine(image, x1: 120, y1: 250 + i * 18, x2: 250, y2: 258 + i * 18,
          color: img.ColorRgb8(40, 40, 40), thickness: 2);
    }
    return image;
  }

  test('small white card on patterned cloth gets its four outside corners',
      () {
    _expectCorners(
        BackgroundContrastContour.detectBytes(_png(whiteCardOnFabric())),
        whiteCard);
  });

  test('blue card pressed against the left photo edge is still found', () {
    const card = [[0, 220], [320, 205], [338, 400], [0, 412]];
    final image = _pinkCheck();
    img.fillPolygon(image, vertices: _poly(card),
        color: img.ColorRgb8(90, 120, 150));
    img.fillRect(image, x1: 30, y1: 260, x2: 70, y2: 290,
        color: img.ColorRgb8(200, 170, 60));
    _expectCorners(BackgroundContrastContour.detectBytes(_png(image)), card,
        tolerance: .025);
  });

  test('white-bordered photo keeps its border and drops its cast shadow', () {
    const photo = [[70, 180], [230, 184], [228, 390], [66, 386]];
    final image = _speckle();
    img.fillPolygon(image,
        vertices: _poly([for (final p in photo) [p[0] + 8, p[1] + 9]]),
        color: img.ColorRgb8(70, 66, 40));
    img.fillPolygon(image, vertices: _poly(photo),
        color: img.ColorRgb8(244, 244, 240));
    img.fillRect(image, x1: 78, y1: 190, x2: 220, y2: 376,
        color: img.ColorRgb8(222, 226, 230));
    img.fillRect(image, x1: 78, y1: 300, x2: 220, y2: 376,
        color: img.ColorRgb8(20, 20, 25));
    img.fillCircle(image, x: 150, y: 242, radius: 35,
        color: img.ColorRgb8(150, 100, 80));
    _expectCorners(BackgroundContrastContour.detectBytes(_png(image)), photo);
  });

  test('printed blocks on a page filling the photo are never cropped', () {
    final image = img.Image(width: _w, height: _h);
    img.fill(image, color: img.ColorRgb8(245, 245, 242));
    for (var i = 0; i < 18; i++) {
      img.drawLine(image, x1: 20, y1: 40 + i * 32, x2: 340, y2: 40 + i * 32,
          color: img.ColorRgb8(80, 80, 80), thickness: 2);
    }
    img.fillRect(image, x1: 60, y1: 200, x2: 300, y2: 330,
        color: img.ColorRgb8(40, 90, 180));
    img.drawRect(image, x1: 40, y1: 400, x2: 320, y2: 560,
        color: img.ColorRgb8(0, 0, 0), thickness: 3);
    expect(BackgroundContrastContour.detectBytes(_png(image)), isNull);
  });

  test('cloth with no document on it gives no outline', () {
    expect(BackgroundContrastContour.detectBytes(_png(_fabric())), isNull);
  });

  test('gallery import crops a small card when the other detectors decline',
      () async {
    final folder = await Directory.systemTemp.createTemp('ds_background_');
    final previous = DoclensPlatform.instance;
    try {
      final source = File('${folder.path}/card.png');
      await source.writeAsBytes(_png(whiteCardOnFabric()));
      DoclensPlatform.instance = _NoNativeDetector();
      final detection =
          await DocumentEdges.detectSafeStillOutline(source.path);
      _expectCorners(detection, whiteCard, tolerance: .03);
      expect(detection!.imageSize, const Size(_w * 1.0, _h * 1.0));
    } finally {
      DoclensPlatform.instance = previous;
      await folder.delete(recursive: true);
    }
  });
}
