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

  test('Convex skewed document corners are accepted', () {
    final quad = CropQuad(const [
      Offset(.08, .18), Offset(.88, .06),
      Offset(.96, .94), Offset(.03, .82),
    ]);
    expect(quad.isValid, isTrue);
  });

  test('Crossed, collapsed and out-of-frame corners are rejected', () {
    final invalid = [
      CropQuad(const [
        Offset(.05, .05), Offset(.95, .95),
        Offset(.95, .05), Offset(.05, .95),
      ]),
      CropQuad(const [
        Offset(.1, .1), Offset(.1, .1),
        Offset(.9, .9), Offset(.1, .9),
      ]),
      CropQuad(const [
        Offset(-.1, .1), Offset(.9, .1),
        Offset(.9, .9), Offset(.1, .9),
      ]),
    ];
    for (final quad in invalid) {
      expect(quad.isValid, isFalse);
    }
  });

  test('Perspective transform refuses a self-intersecting crop', () async {
    final input = img.Image(width: 120, height: 90);
    img.fill(input, color: img.ColorRgb8(255, 255, 255));
    final bytes = Uint8List.fromList(img.encodeJpg(input));
    await expectLater(
      ImageProcessor.process(bytes, crop: CropQuad(const [
        Offset(.05, .05), Offset(.95, .95),
        Offset(.95, .05), Offset(.05, .95),
      ])),
      throwsA(isA<FormatException>()),
    );
  });

  test('Shadow Free reduces a paper illumination gradient', () async {
    final input = img.Image(width: 144, height: 96);
    for (var y = 0; y < input.height; y++) {
      for (var x = 0; x < input.width; x++) {
        final paper = 115 + (x * 120 ~/ input.width);
        final value = y >= 40 && y < 47 ? paper ~/ 5 : paper;
        input.setPixelRgb(x, y, value, value, value);
      }
    }
    final jpeg = Uint8List.fromList(img.encodeJpg(input, quality: 100));
    final result = img.decodeImage(await ImageProcessor.process(
      jpeg, filter: ScanFilter.shadowFree,
    ));
    expect(result, isNotNull);
    expect(result!.getPixel(8, 75).r, greaterThan(145));
    expect(result.getPixel(8, 43).r, lessThan(result.getPixel(8, 75).r));
  });
}
