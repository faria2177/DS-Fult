import 'dart:io';
import 'dart:typed_data';

import 'package:doclens/doclens.dart';
import 'package:docscanner/src/services/document_edges.dart';
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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
