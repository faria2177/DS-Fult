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

class _StillFakePlatform extends DoclensPlatform {
  _StillFakePlatform({this.page, this.card});

  final ImageDetection? page;
  final ImageDetection? card;
  final List<bool> preferCardCalls = [];
  int warpCalls = 0;

  @override
  Future<ImageDetection?> detectInImage({
    required String imagePath,
    ScannerConfig config = const ScannerConfig(),
  }) async {
    preferCardCalls.add(config.preferIdCardBounds);
    return config.preferIdCardBounds ? card : page;
  }

  @override
  Future<String> warpImage({
    required String rawImagePath,
    required Quad quad,
    int jpegQuality = 100,
    ImageEnhancement enhancement = ImageEnhancement.none,
    AutoOrientation autoOrientation = AutoOrientation.none,
  }) async {
    warpCalls++;
    return '$rawImagePath.cropped';
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

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

  test('Gallery can recover a complete card when normal detection is null', () {
    // 381853.mp4: the original is still available after import, but a second
    // card-aware pass must not depend on the first detector finding a quad.
    final outerCard = _detection(_rect(.12, .20, .88, .82),
      size: const Size(1200, 900));
    expect(DocumentEdges.isCredibleStandaloneCard(outerCard), isTrue);
  });

  test('Independent recovery rejects inner labels and background rectangles', () {
    final innerName = _detection(_rect(.23, .43, .77, .59),
      size: const Size(1200, 900));
    final narrowSide = _detection(_rect(.18, .30, .82, .70),
      size: const Size(1200, 900));
    final nearlyFullFrame = _detection(_rect(.01, .02, .99, .98),
      size: const Size(1200, 900));
    final offCenter = _detection(_rect(.02, .02, .70, .48),
      size: const Size(1200, 900));
    expect(DocumentEdges.isCredibleStandaloneCard(innerName), isFalse);
    expect(DocumentEdges.isCredibleStandaloneCard(narrowSide), isFalse);
    expect(DocumentEdges.isCredibleStandaloneCard(nearlyFullFrame), isFalse);
    expect(DocumentEdges.isCredibleStandaloneCard(offCenter), isFalse);
  });

  test('Null page detector still tries card fallback before gallery warp', () async {
    final previous = DoclensPlatform.instance;
    final fake = _StillFakePlatform(card: _detection(
      _rect(.12, .20, .88, .82), size: const Size(1200, 900)));
    DoclensPlatform.instance = fake;
    try {
      final result = await DocumentEdges.autoCropFiles(['id-front.jpg']);
      expect(fake.preferCardCalls, [false, true]);
      expect(result.paths, ['id-front.jpg.cropped']);
      expect(result.croppedCount, 1);
      expect(fake.warpCalls, 1);
    } finally {
      DoclensPlatform.instance = previous;
    }
  });

  test('Manual and gallery lookup both reject inner box without outer card', () async {
    final previous = DoclensPlatform.instance;
    final fake = _StillFakePlatform(
      page: _detection(_rect(.28, .43, .75, .61),
        size: const Size(1200, 900)),
      card: _detection(_rect(.22, .38, .78, .68),
        size: const Size(1200, 900)),
    );
    DoclensPlatform.instance = fake;
    try {
      expect(await DocumentEdges.detectSafeStillOutline('card.jpg'), isNull);
      final result = await DocumentEdges.autoCropFiles(['card.jpg']);
      expect(result.paths, ['card.jpg']);
      expect(result.croppedCount, 0);
      expect(fake.warpCalls, 0);
      expect(fake.preferCardCalls, [false, true, false, true]);
    } finally {
      DoclensPlatform.instance = previous;
    }
  });
}
