import 'dart:typed_data';

import 'package:doclens/doclens.dart';
import 'package:docscanner/src/services/document_edges.dart';
import 'package:docscanner/src/services/quad_edge_evidence.dart';
import 'package:docscanner/src/services/salient_document_detector.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

const _w = 480, _h = 640;

Uint8List _rgb(img.Image image) =>
    Uint8List.fromList(image.getBytes(order: img.ChannelOrder.rgb));

Quad _quad(List<List<double>> p) => Quad(
    topLeft: Offset(p[0][0] / _w, p[0][1] / _h),
    topRight: Offset(p[1][0] / _w, p[1][1] / _h),
    bottomRight: Offset(p[2][0] / _w, p[2][1] / _h),
    bottomLeft: Offset(p[3][0] / _w, p[3][1] / _h));

img.Image _pageOnDesk() {
  final image = img.Image(width: _w, height: _h);
  img.fill(image, color: img.ColorRgb8(60, 62, 70));
  img.fillRect(image, x1: 100, y1: 120, x2: 380, y2: 520,
      color: img.ColorRgb8(236, 236, 230));
  // Printed table rules inside the page must never attract a side.
  for (var y = 180; y < 500; y += 40) {
    img.drawLine(image, x1: 120, y1: y, x2: 360, y2: y,
        color: img.ColorRgb8(70, 70, 70), thickness: 2);
  }
  return image;
}

void main() {
  test('a slightly loose outline snaps onto the page edges', () {
    final evidence = QuadEdgeEvidence.check(
        _quad([[88, 110], [392, 112], [390, 530], [86, 532]]),
        _rgb(_pageOnDesk()), _w, _h)!;
    expect(evidence.confirmed, isTrue);
    final p = evidence.quad.points;
    expect(p[0].dx * _w, closeTo(100, 4));
    expect(p[0].dy * _h, closeTo(120, 4));
    expect(p[2].dx * _w, closeTo(381, 4));
    expect(p[2].dy * _h, closeTo(521, 4));
  });

  test('an exact outline stays put and is confirmed', () {
    final evidence = QuadEdgeEvidence.check(
        _quad([[100, 120], [381, 120], [381, 521], [100, 521]]),
        _rgb(_pageOnDesk()), _w, _h)!;
    expect(evidence.confirmed, isTrue);
    expect(evidence.quad.topLeft.dx * _w, closeTo(100, 2));
  });

  test('a side running across white paper is not confirmed', () {
    // The model merged the page with another sheet lying beside it, so its
    // left side crosses plain paper with no edge anywhere nearby.
    final image = _pageOnDesk();
    img.fillRect(image, x1: 0, y1: 150, x2: 99, y2: 500,
        color: img.ColorRgb8(236, 236, 230));
    final evidence = QuadEdgeEvidence.check(
        _quad([[40, 120], [381, 120], [381, 521], [40, 521]]),
        _rgb(image), _w, _h)!;
    expect(evidence.confirmed, isFalse);
  });

  group('gallery detection', () {
    SalientMask mask({Uint8List? edges}) {
      final probability = Uint8List(320 * 320);
      final rgb = Uint8List(320 * 320 * 3);
      for (var y = 0; y < 320; y++) {
        for (var x = 0; x < 320; x++) {
          final i = y * 320 + x;
          final inside = x >= 64 && x <= 255 && y >= 58 && y <= 262;
          probability[i] = inside ? 255 : 0;
          rgb[i * 3] = inside ? 236 : 60;
          rgb[i * 3 + 1] = inside ? 236 : 62;
          rgb[i * 3 + 2] = inside ? 230 : 70;
        }
      }
      return SalientMask(width: 320, height: 320, probability: probability,
          rgb: rgb, imageWidth: 1200, imageHeight: 1600,
          edgeRgb: edges, edgeWidth: edges == null ? 0 : _w,
          edgeHeight: edges == null ? 0 : _h);
    }

    tearDown(() => SalientDocumentDetector.maskProviderForTesting = null);

    test('an edge-confirmed model outline is used, snapped to the edges',
        () async {
      SalientDocumentDetector.maskProviderForTesting =
          (_) async => mask(edges: _rgb(_pageOnDesk()));
      final result = await SalientDocumentDetector.detectFile('/x.jpg');
      expect(result!.edgesConfirmed, isTrue);
      expect(result.detection.quad!.topLeft.dx * _w, closeTo(100, 4));
    });

    test('without edge evidence the model is only a last resort', () async {
      SalientDocumentDetector.maskProviderForTesting = (_) async => mask();
      final result = await SalientDocumentDetector.detectFile('/x.jpg');
      expect(result!.edgesConfirmed, isFalse);
      // No other detector can read this path, so the model outline is used.
      final detection =
          await DocumentEdges.detectSafeStillOutline('/nonexistent/x.jpg');
      expect(detection, isNotNull);
    });
  });
}
