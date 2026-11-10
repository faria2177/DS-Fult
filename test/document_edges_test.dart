import 'package:doclens/doclens.dart';
import 'package:docscanner/src/services/document_edges.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

ImageDetection _detection(Quad quad, {Size size = const Size(900, 1200)}) =>
    ImageDetection(quad: quad, imageSize: size);

Quad _rect(double left, double top, double right, double bottom) => Quad(
  topLeft: Offset(left, top),
  topRight: Offset(right, top),
  bottomRight: Offset(right, bottom),
  bottomLeft: Offset(left, bottom),
);

void main() {
  test('Scanner tracks a stable four-corner outline with manual capture', () {
    final config = DocumentEdges.scannerConfig;
    expect(config.enableAutoCapture, isFalse);
    expect(config.enableAutoCaptureConfirmation, isFalse);
    expect(config.detectionPolarity, DetectionPolarity.auto);
    expect(config.detectionThresholdOffset, 12);
    expect(config.enableQuadSmoothing, isTrue);
    expect(config.quadSmoothingWindow, 7);
    expect(config.enableSharpnessGate, isTrue);
    expect(config.enablePerspectiveWarp, isTrue);
    expect(config.autoCaptureStabilityDuration.inMilliseconds, 1100);
    expect(config.autoCaptureConfirmationDelay.inMilliseconds, 400);
  });

  test('Gallery import accepts a credible outer A4 page', () {
    expect(DocumentEdges.isReliableGalleryCrop(
      _detection(_rect(.08, .08, .92, .92))), isTrue);
  });

  test('Gallery import keeps full ID image when text block is selected', () {
    // Reproduces 381847(1).mp4: the chosen NID contains a portrait, header,
    // name and number, but ordinary Scan detects only the centre name block.
    final innerNameBlock = _detection(
      _rect(.12, .33, .88, .63), size: const Size(1200, 900));
    expect(DocumentEdges.isReliableGalleryCrop(innerNameBlock), isFalse);
    // An intentionally selected ID-card workflow uses separate bounds.
    expect(DocumentEdges.isReliableGalleryCrop(innerNameBlock,
      preferIdCardBounds: true), isTrue);
  });

  test('Gallery import rejects centred inner A4 table and narrow strip', () {
    expect(DocumentEdges.isReliableGalleryCrop(
      _detection(_rect(.16, .19, .84, .81))), isFalse);
    expect(DocumentEdges.isReliableGalleryCrop(
      _detection(_rect(.07, .38, .93, .62))), isFalse);
  });

  test('Gallery import allows a well-framed landscape document', () {
    expect(DocumentEdges.isReliableGalleryCrop(
      _detection(_rect(.04, .09, .96, .91),
        size: const Size(1200, 900))), isTrue);
  });

  test('Card-aware recovery accepts the complete card around an inner name', () {
    final inner = _detection(_rect(.28, .42, .76, .65),
      size: const Size(1200, 900));
    final card = _detection(_rect(.09, .16, .91, .85),
      size: const Size(1200, 900));
    expect(DocumentEdges.isReliableGalleryCrop(inner), isFalse);
    expect(DocumentEdges.isCredibleOuterCardAlternative(inner, card), isTrue);
  });

  test('Card recovery rejects unrelated and merely larger text blocks', () {
    final inner = _detection(_rect(.20, .45, .70, .64),
      size: const Size(1200, 900));
    expect(DocumentEdges.isCredibleOuterCardAlternative(inner,
      _detection(_rect(.47, .12, .95, .52),
        size: const Size(1200, 900))), isFalse);
    expect(DocumentEdges.isCredibleOuterCardAlternative(inner,
      _detection(_rect(.18, .40, .75, .68),
        size: const Size(1200, 900))), isFalse);
  });
}
