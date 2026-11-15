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

  test('shutter green corners survive lost still border and full-frame sentinel', () {
    // Real screenshots: live camera framed the LEFT grey notebook page,
    // CameraX saved the whole two-page landscape still, and the editor used
    // the full-frame sentinel. The camera-only reviewQuad must win instead.
    final capture = ScanResult.fromMap({
      'rawImagePath': 'capture_landscape.jpg',
      'croppedImagePath': null,
      'quad': quadInPixels(0, 0, 1, 1).toMap(),
      'reviewQuad': quadInPixels(.21, .08, .77, .93).toMap(),
      'rawImageSize': [1200, 900],
      'liveOutlineAtShutter': true,
      'liveOutlineMatched': false,
    });
    final hint = DocumentEdges.captureQuadHint(capture);
    expect(hint, isNotNull);
    expect(hint!.corners[0], const Offset(.21, .08));
    expect(hint.corners[2], const Offset(.77, .93));
    expect(capture.reviewQuad, isNotNull);
    expect(capture.copyWith(liveOutlineMatched: true).reviewQuad,
        capture.reviewQuad);
  });

  test('unverified gallery input cannot inherit camera-only review geometry', () {
    final gallery = ScanResult.fromMap({
      'rawImagePath': 'imported.jpg',
      'croppedImagePath': null,
      'quad': quadInPixels(0, 0, 1, 1).toMap(),
      'reviewQuad': quadInPixels(.21, .08, .77, .93).toMap(),
      'rawImageSize': [1200, 900],
      'liveOutlineAtShutter': false,
    });
    expect(DocumentEdges.captureQuadHint(gallery), isNull);
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

  test('native camera flags distinguish verified green crop from review', () {
    final result = ScanResult.fromMap({
      'rawImagePath': 'raw.jpg',
      'croppedImagePath': 'green_crop.jpg',
      'quad': quadInPixels(.10, .11, .90, .89).toMap(),
      'rawImageSize': [1200, 900],
      'liveOutlineAtShutter': true,
      'liveOutlineMatched': true,
    });
    expect(result.liveOutlineAtShutter, isTrue);
    expect(result.liveOutlineMatched, isTrue);
    expect(result.croppedImagePath, 'green_crop.jpg');
    final pending = result.copyWith(liveOutlineMatched: false);
    expect(pending.liveOutlineAtShutter, isTrue);
    expect(pending.liveOutlineMatched, isFalse);
  });

  test('legacy captures and gallery results have no green-quad lock', () {
    final result = ScanResult.fromMap({
      'rawImagePath': 'gallery.jpg',
      'croppedImagePath': null,
      'quad': quadInPixels(.10, .11, .90, .89).toMap(),
      'rawImageSize': [1200, 900],
    });
    expect(result.liveOutlineAtShutter, isFalse);
    expect(result.liveOutlineMatched, isFalse);
  });

  test('small visible green card seeds manual editor, not gallery auto crop', () {
    // Video 382753: a 10%-area vertical card is real despite the normal
    // A4 reliability gate rejecting its small coverage.
    const size = Size(900, 1200);
    const live = Quad(
      topLeft: Offset(288, 384),
      topRight: Offset(549, 384),
      bottomRight: Offset(549, 804),
      bottomLeft: Offset(288, 804),
    );
    final greenCamera = ScanResult(
      croppedImagePath: null,
      rawImagePath: 'still.jpg',
      rawImageSize: size,
      detectedQuad: live,
      liveOutlineAtShutter: true,
      liveOutlineMatched: false,
    );
    final hint = DocumentEdges.captureQuadHint(greenCamera);
    expect(hint, isNotNull);
    expect(hint!.corners.first.dx, closeTo(.32, .0001));
    // No green camera metadata => imported images must retain their strict
    // normal outline checks and never inherit this relaxed manual hint.
    expect(DocumentEdges.captureQuadHint(
      greenCamera.copyWith(liveOutlineAtShutter: false)), isNull);
  });

  test('preview screen is optional but still available for other users', () {
    const scanner = DoclensScreen(skipCaptureReview: true);
    const reusable = DoclensScreen();
    expect(scanner.skipCaptureReview, isTrue);
    expect(reusable.skipCaptureReview, isFalse);
  });
}
