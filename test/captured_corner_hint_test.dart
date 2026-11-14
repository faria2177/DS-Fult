import 'package:doclens/doclens.dart';
import 'package:docscanner/src/services/document_edges.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

ScanResult captured(Quad quad, {Size size = const Size(1200, 900)}) {
  return ScanResult(
    croppedImagePath: null,
    rawImagePath: 'upright_camera.jpg',
    detectedQuad: quad,
    rawImageSize: size,
  );
}

Quad quadInPixels(double left, double top, double right, double bottom) {
  return Quad(
    topLeft: Offset(left * 1200, top * 900),
    topRight: Offset(right * 1200, top * 900),
    bottomRight: Offset(right * 1200, bottom * 900),
    bottomLeft: Offset(left * 1200, bottom * 900),
  );
}

void main() {
  test('camera quad maps into the precise upright still pixel space', () {
    final hint = DocumentEdges.captureQuadHint(
      captured(quadInPixels(.10, .11, .90, .89)),
    );
    expect(hint, isNotNull);
    expect(hint!.isValid, isTrue);
    expect(hint.corners[0].dx, closeTo(.10, .0001));
    expect(hint.corners[2].dy, closeTo(.89, .0001));
  });

  test('full frame native sentinel must not become an invisible crop', () {
    final capture = captured(quadInPixels(0, 0, 1, 1));
    expect(DocumentEdges.captureQuadHint(capture), isNull);
    expect(DocumentEdges.captureQuadHint(capture,
        preferIdCardBounds: true), isNull);
  });

  test('central printed name box cannot replace live whole page', () {
    final capture = captured(quadInPixels(.30, .40, .70, .59));
    expect(DocumentEdges.captureQuadHint(capture), isNull);
  });

  test('small tilted card may seed manual handles but not auto crop', () {
    final capture = captured(quadInPixels(.23, .31, .77, .64));
    expect(DocumentEdges.captureQuadHint(
        capture, preferIdCardBounds: true), isNotNull);
  });

  test('invalid raw dimensions and corners produce no fake outline', () {
    final badSize = captured(quadInPixels(.1, .1, .9, .9),
        size: Size.zero);
    expect(DocumentEdges.captureQuadHint(badSize), isNull);
    final outside = captured(quadInPixels(-.1, .1, .9, .9));
    expect(DocumentEdges.captureQuadHint(outside), isNull);
  });

  test('preview screen is optional but still available for other users', () {
    const scanner = DoclensScreen(skipCaptureReview: true);
    const reusable = DoclensScreen();
    expect(scanner.skipCaptureReview, isTrue);
    expect(reusable.skipCaptureReview, isFalse);
  });
}
