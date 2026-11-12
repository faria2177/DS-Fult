import 'package:doclens/doclens.dart';
import 'package:docscanner/src/services/document_edges.dart';
import 'package:docscanner/src/services/online_auto_crop_service.dart';
import 'package:docscanner/src/services/offline_document_contour.dart';
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
  Quad? lastWarpedQuad;
  ImageEnhancement? lastWarpEnhancement;

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
    lastWarpedQuad = quad;
    lastWarpEnhancement = enhancement;
    return '$rawImagePath.cropped';
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('Online First uses a validated server quad before native detection',
      () async {
    final previous = DoclensPlatform.instance;
    final fake = _StillFakePlatform(page: _detection(
        _rect(.12, .12, .88, .88)));
    DoclensPlatform.instance = fake;
    DocumentEdges.onlineDetectorForTesting = (path, preferCard) async =>
      OnlineCropCandidate(_detection(_rect(.08, .08, .92, .92)),
          .96, 'document');
    try {
      final found = await DocumentEdges.detectSafeStillOutline(
          'nonexistent-online-source.jpg');
      expect(found?.quad?.area, closeTo(.7056, .001));
      expect(fake.preferCardCalls, isEmpty);
    } finally {
      DocumentEdges.onlineDetectorForTesting = null;
      DoclensPlatform.instance = previous;
    }
  });

  test('Unreliable online corners fall back to the existing local detector',
      () async {
    final previous = DoclensPlatform.instance;
    final native = _detection(_rect(.08, .08, .92, .92));
    final fake = _StillFakePlatform(page: native);
    DoclensPlatform.instance = fake;
    DocumentEdges.onlineDetectorForTesting = (path, preferCard) async =>
      OnlineCropCandidate(_detection(_rect(.28, .38, .70, .60)),
          .99, 'document');
    try {
      final found = await DocumentEdges.detectSafeStillOutline(
          'nonexistent-local-fallback.jpg');
      expect(found?.quad?.area, closeTo(.7056, .001));
      expect(fake.preferCardCalls, isNotEmpty);
    } finally {
      DocumentEdges.onlineDetectorForTesting = null;
      DoclensPlatform.instance = previous;
    }
  });

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

  test('Auto Crop only warps pixels and never pre-enhances ID text or faces',
      () async {
    final previous = DoclensPlatform.instance;
    final fake = _StillFakePlatform(page: _detection(
      _rect(.08, .08, .92, .92)));
    DoclensPlatform.instance = fake;
    try {
      final result = await DocumentEdges.autoCropFiles(['original.jpg']);
      expect(result.croppedCount, 1);
      expect(fake.lastWarpEnhancement, ImageEnhancement.none);
    } finally {
      DoclensPlatform.instance = previous;
    }
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

  test('NID text band touching left/right edges cannot silently crop face', () {
    // 381861.mp4: this appears sizeable enough to beat the old area guard,
    // and near the horizontal image borders, but it is not the outer NID.
    final label = _detection(_rect(.04, .25, .96, .75),
      size: const Size(900, 1200));
    expect(DocumentEdges.isReliableGalleryCrop(label), isFalse);
  });

  test('An edge-touching NID text fragment keeps the original if no card is found',
      () async {
    final previous = DoclensPlatform.instance;
    final fake = _StillFakePlatform(page: _detection(
      _rect(.04, .25, .96, .75), size: const Size(900, 1200)));
    DoclensPlatform.instance = fake;
    try {
      final result = await DocumentEdges.autoCropFiles(['full-nid.jpg']);
      expect(fake.preferCardCalls, [false, true]);
      expect(fake.warpCalls, 0);
      expect(result.paths, ['full-nid.jpg']);
      expect(result.needsReview, 1);
      expect(result.failedIndexes, [0]);
    } finally {
      DoclensPlatform.instance = previous;
    }
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

  test('Almost edge-to-edge cards are not rejected by the old 1.2% margin', () {
    // Normalized card corners can be close to the camera frame without
    // touching or leaving it. The strict 1.2% margin discarded those scans.
    final edgeCard = _detection(_rect(.007, .12, .94, .90),
      size: const Size(1200, 900));
    expect(DocumentEdges.isCredibleStandaloneCard(edgeCard), isTrue);
  });

  test('Lined notebook background can yield to enclosed portrait ID card', () async {
    // Video 381861.mp4: the gold ID occupies only part of the ruled sheet.
    final background = _detection(_rect(.03, .03, .97, .97),
      size: const Size(416, 741));
    final goldCard = _detection(_rect(.18, .12, .94, .84),
      size: const Size(416, 741));
    expect(DocumentEdges.isReliableGalleryCrop(background), isTrue);
    expect(DocumentEdges.isCredibleCardInsideBackground(background, goldCard),
      isTrue);

    final previous = DoclensPlatform.instance;
    final fake = _StillFakePlatform(page: background, card: goldCard);
    DoclensPlatform.instance = fake;
    try {
      final result = await DocumentEdges.autoCropFiles(['gold-id.jpg']);
      expect(fake.preferCardCalls, [false, true]);
      expect(result.croppedCount, 1);
      expect(fake.lastWarpedQuad?.points, goldCard.quadIn.points);
    } finally {
      DoclensPlatform.instance = previous;
    }
  });

  test('Video 381877: a 20%-frame gold card replaces a near-frame notebook',
      () async {
    const size = Size(320, 420);
    final notebook = _detection(_rect(.02, .02, .98, .98), size: size);
    final card = _detection(_rect(.295, .26, .705, .75), size: size);
    expect(card.quad!.area, lessThan(.21));
    expect(DocumentEdges.isCredibleStandaloneCard(card), isTrue);
    expect(DocumentEdges.isCredibleCardInsideBackground(notebook, card), isTrue);

    final previous = DoclensPlatform.instance;
    final fake = _StillFakePlatform(page: notebook, card: card);
    DoclensPlatform.instance = fake;
    try {
      final batch = await DocumentEdges.autoCropFiles(['notebook-id.jpg']);
      expect(fake.preferCardCalls, [false, true]);
      expect(fake.lastWarpedQuad!.points, card.quadIn.points);
      expect(batch.croppedCount, 1);
    } finally {
      DoclensPlatform.instance = previous;
    }
  });

  test('A good framed page skips a misleading inner coloured label', () async {
    final page = _detection(_rect(.10, .10, .90, .90));
    final label = _detection(_rect(.295, .26, .705, .75));
    final previous = DoclensPlatform.instance;
    final fake = _StillFakePlatform(page: page, card: label);
    DoclensPlatform.instance = fake;
    try {
      final batch = await DocumentEdges.autoCropFiles(['a4-report.jpg']);
      expect(fake.preferCardCalls, [false]);
      expect(fake.lastWarpedQuad!.points, page.quadIn.points);
      expect(batch.croppedCount, 1);
    } finally {
      DoclensPlatform.instance = previous;
    }
  });

  test('Coloured airport-pass card replaces a fairly inset notebook outline', () {
    // The ruled background is not touching three frame edges, so the earlier
    // near-frame guard alone could never choose the real outer ID corners.
    const size = Size(864, 1536);
    final notebook = _detection(_rect(.07, .07, .96, .93), size: size);
    final card = _detection(_rect(.185, .125, .945, .825), size: size);
    final segmented = OfflineContourResult(card, .61,
        colorOnNeutralBackground: true);
    expect(DocumentEdges.isCredibleCardInsideBackground(notebook, card),
        isFalse);
    expect(DocumentEdges.isCredibleColoredCardOverPage(notebook, segmented),
        isTrue);
    expect(DocumentEdges.isCredibleColoredCardOverPage(notebook,
        OfflineContourResult(card, .61)), isFalse);
    expect(DocumentEdges.isCredibleColoredCardOverPage(notebook,
        OfflineContourResult(card, .32,
            colorOnNeutralBackground: true)), isFalse);
  });

  test('Normal A4 printed boxes cannot replace the outer page', () {
    const size = Size(864, 1536);
    final page = _detection(_rect(.07, .07, .96, .93), size: size);
    final label = _detection(_rect(.24, .30, .77, .66), size: size);
    expect(DocumentEdges.isCredibleColoredCardOverPage(page,
        OfflineContourResult(label, .95,
            colorOnNeutralBackground: true)), isFalse);
  });

  test('Ordinary A4 page is not replaced by an inner card-looking label', () async {
    final regularA4 = _detection(_rect(.09, .09, .91, .91));
    final printedTitle = _detection(_rect(.18, .32, .82, .66));
    expect(DocumentEdges.isCredibleCardInsideBackground(
      regularA4, printedTitle), isFalse);
    final previous = DoclensPlatform.instance;
    final fake = _StillFakePlatform(page: regularA4, card: printedTitle);
    DoclensPlatform.instance = fake;
    try {
      final result = await DocumentEdges.autoCropFiles(['a4.jpg']);
      expect(fake.preferCardCalls, [false]);
      expect(result.croppedCount, 1);
      expect(fake.lastWarpedQuad?.points, regularA4.quadIn.points);
    } finally {
      DoclensPlatform.instance = previous;
    }
  });

  test('A separately visible ID replaces a larger dark document holder', () {
    const size = Size(1200, 900);
    final holder = _detection(_rect(.08, .12, .92, .88), size: size);
    final card = _detection(_rect(.22, .25, .78, .75), size: size);
    expect(DocumentEdges.isCredibleCardInsideBackground(holder, card), isFalse);
    expect(DocumentEdges.isCredibleCardInsideHolder(holder, card,
        borderEvidence: .86), isTrue);
    expect(DocumentEdges.isCredibleCardInsideHolder(holder, card,
        borderEvidence: .27), isFalse);
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
      expect(result.failedIndexes, [0]);
      expect(fake.warpCalls, 0);
      expect(fake.preferCardCalls, [false, true, false, true]);
    } finally {
      DoclensPlatform.instance = previous;
    }
  });

  test('Verified white NID wins against reflective sleeve or no native quad', () {
    const size = Size(1200, 1600);
    final whiteCard = _detection(_rect(.08, .28, .92, .68), size: size);
    final holder = _detection(_rect(.02, .20, .98, .77), size: size);
    final proven = OfflineContourResult(whiteCard, .84,
        whiteOnDarkBackground: true);
    expect(DocumentEdges.isCredibleStandaloneCard(whiteCard), isTrue);
    expect(DocumentEdges.isVerifiedWhiteCardOnDark(null, proven), isTrue);
    expect(DocumentEdges.isVerifiedWhiteCardOnDark(holder, proven), isTrue);
    expect(DocumentEdges.isVerifiedWhiteCardOnDark(holder,
      OfflineContourResult(whiteCard, .25,
          whiteOnDarkBackground: true)), isFalse);
    expect(DocumentEdges.isVerifiedWhiteCardOnDark(holder,
      OfflineContourResult(whiteCard, .9)), isFalse);
  });



  test('Full-width white card on dark table can retain lateral source edges', () {
    const size = Size(550, 690);
    final edgeToEdge = _detection(_rect(0, .16, .995, .73),
        size: size);
    final result = OfflineContourResult(edgeToEdge, .51,
        whiteOnDarkBackground: true);
    final mistakenNative = _detection(_rect(.12, .26, .86, .61),
        size: size);
    expect(DocumentEdges.isCredibleStandaloneCard(edgeToEdge), isFalse);
    expect(DocumentEdges.isVerifiedWhiteCardOnDark(null, result), isTrue);
    expect(DocumentEdges.isVerifiedWhiteCardOnDark(
        mistakenNative, result), isTrue);
    expect(DocumentEdges.isVerifiedWhiteCardOnDark(null,
      OfflineContourResult(edgeToEdge, .18,
          whiteOnDarkBackground: true)), isFalse);
    expect(DocumentEdges.isVerifiedWhiteCardOnDark(null,
      OfflineContourResult(edgeToEdge, .99)), isFalse);
  });


}
