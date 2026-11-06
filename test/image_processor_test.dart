import 'dart:typed_data';

import 'package:docscanner/src/services/image_processor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Original mode does not degrade JPEG bytes', () async {
    final bytes = Uint8List.fromList([1, 2, 3, 4]);
    final result = await ImageProcessor.process(bytes);
    expect(result, same(bytes));
  });

  test('Auto processing brightens gray paper without black output', () async {
    final input = img.Image(width: 24, height: 24);
    for (var y = 0; y < 24; y++) {
      for (var x = 0; x < 24; x++) {
        final value = x < 4 ? 60 : 170;
        input.setPixelRgb(x, y, value, value, value);
      }
    }
    final jpeg = Uint8List.fromList(img.encodeJpg(input, quality: 100));
    final result = img.decodeImage(await ImageProcessor.process(
      jpeg, filter: ScanFilter.auto,
    ));
    expect(result, isNotNull);
    expect(result!.getPixel(18, 15).r, greaterThan(175));
    expect(result.getPixel(1, 15).r, lessThan(165));
  });

  test('Crop processing returns a valid image', () async {
    final input = img.Image(width: 120, height: 80);
    img.fill(input, color: img.ColorRgb8(240, 240, 240));
    final result = img.decodeImage(await ImageProcessor.process(
      Uint8List.fromList(img.encodeJpg(input)),
      crop: CropQuad.inset(),
    ));
    expect(result, isNotNull);
    expect(result!.width, greaterThan(50));
    expect(result.height, greaterThan(30));
  });
}
