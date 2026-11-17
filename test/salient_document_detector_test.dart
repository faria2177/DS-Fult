import 'dart:typed_data';

import 'package:doclens/doclens.dart';
import 'package:docscanner/src/services/background_contrast_contour.dart';
import 'package:docscanner/src/services/document_edges.dart';
import 'package:docscanner/src/services/salient_document_detector.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

const _side = 320;

/// A model answer: [polygon] is foreground with certainty [inside].
SalientMask _mask(List<List<int>> polygon, {int inside = 255,
    img.Color? surround, int imageWidth = 900, int imageHeight = 1600}) {
  final canvas = img.Image(width: _side, height: _side);
  img.fill(canvas, color: img.ColorRgb8(0, 0, 0));
  img.fillPolygon(canvas,
      vertices: [for (final p in polygon) img.Point(p[0], p[1])],
      color: img.ColorRgb8(inside, inside, inside));
  final probability = Uint8List(_side * _side);
  final rgb = Uint8List(_side * _side * 3);
  final background = surround ?? img.ColorRgb8(40, 35, 80);
  for (var y = 0; y < _side; y++) {
    for (var x = 0; x < _side; x++) {
      final i = y * _side + x;
      probability[i] = canvas.getPixel(x, y).r.toInt();
      final object = probability[i] > 127;
      rgb[i * 3] = object ? 240 : background.r.toInt();
      rgb[i * 3 + 1] = object ? 240 : background.g.toInt();
      rgb[i * 3 + 2] = object ? 236 : background.b.toInt();
    }
  }
  return SalientMask(width: _side, height: _side, probability: probability,
      rgb: rgb, imageWidth: imageWidth, imageHeight: imageHeight);
}

Quad? _quad(SalientMask mask) => BackgroundContrastContour.quadFromSalientMask(
    probability: mask.probability, rgb: mask.rgb,
    width: mask.width, height: mask.height,
    imageWidth: mask.imageWidth.toDouble(),
    imageHeight: mask.imageHeight.toDouble());

void main() {
  const card = [[90, 120], [250, 128], [246, 190], [86, 182]];

  test('a confident four-sided object becomes four corners', () {
    final quad = _quad(_mask(card));
    expect(quad, isNotNull);
    final points = quad!.points;
    for (var i = 0; i < 4; i++) {
      expect(points[i].dx, closeTo(card[i][0] / _side, .012));
      expect(points[i].dy, closeTo(card[i][1] / _side, .012));
    }
  });

  test('an object touching one photo edge is still accepted', () {
    expect(_quad(_mask([[0, 110], [220, 100], [228, 210], [0, 216]])),
        isNotNull);
  });

  test('a hesitant model answer is discarded', () {
    expect(_quad(_mask(card, inside: 170)), isNull);
  });

  test('a non-rectangular object is discarded', () {
    expect(_quad(_mask([[160, 60], [260, 250], [60, 250]])), isNull);
    expect(_quad(_mask([[60, 60], [260, 60], [260, 120], [130, 120],
        [130, 260], [60, 260]])), isNull);
  });

  test('an object cut by two photo edges is left to the page detectors', () {
    expect(_quad(_mask([[0, 0], [200, 0], [200, 220], [0, 220]])), isNull);
  });

  test('a block printed on white paper is not cropped out of its page', () {
    expect(_quad(_mask(card, surround: img.ColorRgb8(246, 246, 243))),
        isNull);
  });

  test('gallery detection prefers the confident model outline', () async {
    SalientDocumentDetector.maskProviderForTesting = (_) async => _mask(card);
    addTearDown(() => SalientDocumentDetector.maskProviderForTesting = null);
    final detection =
        await DocumentEdges.detectSafeStillOutline('/nonexistent/card.jpg');
    expect(detection, isNotNull);
    expect(detection!.imageSize.width, 900);
    expect(detection.quad!.topLeft.dx, closeTo(card[0][0] / _side, .012));
  });

  test('camera captures never use the gallery segmentation model', () async {
    var asked = 0;
    SalientDocumentDetector.maskProviderForTesting = (_) async {
      asked++;
      return _mask(card);
    };
    addTearDown(() => SalientDocumentDetector.maskProviderForTesting = null);
    await DocumentEdges.detectSafeStillOutline('/nonexistent/camera.jpg',
        galleryDetectors: false);
    expect(asked, 0);
  });
}
