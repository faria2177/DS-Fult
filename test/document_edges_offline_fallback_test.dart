import 'dart:io';
import 'dart:typed_data';

import 'package:doclens/doclens.dart';
import 'package:docscanner/src/services/document_edges.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

class _UnavailableNativeDetector extends DoclensPlatform {
  @override
  Future<ImageDetection?> detectInImage({
    required String imagePath,
    ScannerConfig config = const ScannerConfig(),
  }) async => throw UnsupportedError('no native contour detector');

  @override
  Future<String> warpImage({
    required String rawImagePath,
    required Quad quad,
    int jpegQuality = 100,
    ImageEnhancement enhancement = ImageEnhancement.none,
    AutoOrientation autoOrientation = AutoOrientation.none,
  }) async => throw UnsupportedError('no native perspective transform');

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _HolderNativeDetector extends DoclensPlatform {
  _HolderNativeDetector(this.holder);

  final ImageDetection holder;

  @override
  Future<ImageDetection?> detectInImage({
    required String imagePath,
    ScannerConfig config = const ScannerConfig(),
  }) async => config.preferIdCardBounds ? null : holder;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Strong inner card boundary beats a broad dark holder contour',
      () async {
    final folder = await Directory.systemTemp.createTemp('docscanner_holder_');
    final originalNative = DoclensPlatform.instance;
    try {
      final raw = img.Image(width: 420, height: 320);
      img.fill(raw, color: img.ColorRgb8(25, 28, 30));
      img.fillRect(raw, x1: 45, y1: 35, x2: 375, y2: 285,
          color: img.ColorRgb8(65, 68, 70));
      img.fillRect(raw, x1: 85, y1: 80, x2: 335, y2: 241,
          color: img.ColorRgb8(230, 229, 224));
      img.fillRect(raw, x1: 134, y1: 113, x2: 190, y2: 180,
          color: img.ColorRgb8(78, 91, 109));
      final source = File('${folder.path}/holder.png');
      await source.writeAsBytes(Uint8List.fromList(img.encodePng(raw)));
      final holder = ImageDetection(imageSize: const Size(420, 320),
        quad: const Quad(
          topLeft: Offset(45 / 420, 35 / 320),
          topRight: Offset(375 / 420, 35 / 320),
          bottomRight: Offset(375 / 420, 285 / 320),
          bottomLeft: Offset(45 / 420, 285 / 320),
        ));
      DoclensPlatform.instance = _HolderNativeDetector(holder);

      final detection = await DocumentEdges.detectSafeStillOutline(source.path);
      expect(detection?.quad, isNotNull);
      expect(detection!.quad!.topLeft.dx, closeTo(85 / 420, .04));
      expect(detection.quad!.bottomRight.dy, closeTo(240 / 320, .04));
    } finally {
      DoclensPlatform.instance = originalNative;
      await folder.delete(recursive: true);
    }
  });

  test('Gold card beats native notebook bounds even without near-frame sides',
      () async {
    final folder = await Directory.systemTemp.createTemp('docscanner_ruled_');
    final originalNative = DoclensPlatform.instance;
    try {
      final raw = img.Image(width: 320, height: 420);
      img.fill(raw, color: img.ColorRgb8(224, 225, 225));
      for (var y = 22; y < 420; y += 30) {
        img.fillRect(raw, x1: 0, y1: y, x2: 319, y2: y + 1,
            color: img.ColorRgb8(91, 110, 156));
      }
      img.fillRect(raw, x1: 57, y1: 55, x2: 264, y2: 374,
          color: img.ColorRgb8(192, 172, 120));
      img.fillRect(raw, x1: 111, y1: 125, x2: 208, y2: 218,
          color: img.ColorRgb8(28, 104, 114));
      img.fillRect(raw, x1: 137, y1: 148, x2: 184, y2: 203,
          color: img.ColorRgb8(178, 119, 90));
      img.fillRect(raw, x1: 88, y1: 245, x2: 234, y2: 251,
          color: img.ColorRgb8(24, 24, 24));
      final source = File('${folder.path}/card_on_notebook.png');
      await source.writeAsBytes(Uint8List.fromList(img.encodePng(raw)));
      final notebook = ImageDetection(imageSize: const Size(320, 420),
        quad: const Quad(
          topLeft: Offset(.075, .075),
          topRight: Offset(.95, .075),
          bottomRight: Offset(.95, .93),
          bottomLeft: Offset(.075, .93),
        ));
      DoclensPlatform.instance = _HolderNativeDetector(notebook);

      final found = await DocumentEdges.detectSafeStillOutline(source.path);
      expect(found?.quad, isNotNull);
      // Notebook still passes the ordinary page policy, but the complete
      // four-corner gold card should win instead.
      expect(found!.quad!.topLeft.dx, closeTo(57 / 320, .05));
      expect(found.quad!.topLeft.dy, closeTo(55 / 420, .05));
      expect(found.quad!.bottomRight.dx, closeTo(264 / 320, .05));
      expect(found.quad!.bottomRight.dy, closeTo(374 / 420, .05));
    } finally {
      DoclensPlatform.instance = originalNative;
      await folder.delete(recursive: true);
    }
  });

  test('Gallery crop and perspective warp work when native pipeline fails',
      () async {
    final folder = await Directory.systemTemp.createTemp('docscanner_test_');
    final native = DoclensPlatform.instance;
    DoclensPlatform.instance = _UnavailableNativeDetector();
    try {
      final raw = img.Image(width: 320, height: 420);
      img.fill(raw, color: img.ColorRgb8(225, 224, 222));
      for (var y = 20; y < 420; y += 30) {
        img.fillRect(raw, x1: 0, y1: y, x2: 319, y2: y + 1,
            color: img.ColorRgb8(102, 112, 147));
      }
      img.fillRect(raw, x1: 77, y1: 71, x2: 260, y2: 353,
          color: img.ColorRgb8(195, 170, 114));
      img.fillRect(raw, x1: 136, y1: 147, x2: 206, y2: 221,
          color: img.ColorRgb8(37, 62, 75));
      final source = File('${folder.path}/source.png');
      await source.writeAsBytes(Uint8List.fromList(img.encodePng(raw)));

      final result = await DocumentEdges.autoCropFiles([source.path]);
      expect(result.croppedCount, 1);
      expect(result.needsReview, 0);
      expect(result.paths.single, isNot(source.path));
      final croppedFile = File(result.paths.single);
      expect(await croppedFile.exists(), isTrue);
      final cropped = img.decodeImage(await croppedFile.readAsBytes());
      expect(cropped, isNotNull);
      expect(cropped!.width, greaterThan(160));
      expect(cropped.width, lessThan(250));
      expect(cropped.height, greaterThan(250));
      expect(cropped.height, lessThan(340));
      // The notebook margin must be gone, but the card has to stay whole.
      expect(cropped.getPixel(8, 8).r, greaterThan(155));
      await croppedFile.delete();
    } finally {
      DoclensPlatform.instance = native;
      await folder.delete(recursive: true);
    }
  });
}
