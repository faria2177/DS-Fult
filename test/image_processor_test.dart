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

  test('Page rotation changes dimensions and preserves corner orientation', () async {
    final input = img.Image(width: 80, height: 50);
    img.fill(input, color: img.ColorRgb8(240, 240, 240));
    for (var y = 0; y < 18; y++) {
      for (var x = 0; x < 18; x++) {
        input.setPixelRgb(x, y, 245, 10, 10);
        input.setPixelRgb(79 - x, 49 - y, 10, 10, 245);
      }
    }
    final source = Uint8List.fromList(img.encodePng(input));
    final right = img.decodeImage(await ImageProcessor.process(
      source, rotateDegrees: 90,
    ))!;
    expect((right.width, right.height), (50, 80));
    // A clockwise turn moves the original top-left red mark to top-right.
    expect(right.getPixel(42, 8).r, greaterThan(180));
    expect(right.getPixel(8, 72).b, greaterThan(180));

    final halfTurn = img.decodeImage(await ImageProcessor.process(
      source, rotateDegrees: 180,
    ))!;
    expect((halfTurn.width, halfTurn.height), (80, 50));
    expect(halfTurn.getPixel(72, 42).r, greaterThan(180));
    expect(halfTurn.getPixel(8, 8).b, greaterThan(180));
  });

  test('PNG rotation retains transparency for background-removed pages', () async {
    final input = img.Image(width: 18, height: 30, numChannels: 4);
    img.fill(input, color: img.ColorRgba8(255, 0, 0, 0));
    input.setPixelRgba(1, 1, 15, 200, 40, 255);
    final result = img.decodePng(await ImageProcessor.process(
      Uint8List.fromList(img.encodePng(input)),
      rotateDegrees: 90, outputPng: true,
    ))!;
    expect((result.width, result.height), (30, 18));
    expect(result.getPixel(10, 10).a, 0);
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

  test('Cropped-document Enhance lifts gold paper but protects skin and ink',
      () async {
    final input = img.Image(width: 160, height: 200);
    img.fill(input, color: img.ColorRgb8(190, 170, 123));
    for (var y = 64; y < 115; y++) {
      for (var x = 50; x < 109; x++) {
        input.setPixelRgb(x, y, 182, 116, 94); // portrait/skin patch
      }
    }
    for (var x = 35; x < 128; x++) {
      for (var y = 155; y < 162; y++) {
        input.setPixelRgb(x, y, 28, 27, 26); // printed text
      }
    }
    final source = Uint8List.fromList(img.encodePng(input));
    final output = img.decodeImage(await ImageProcessor.process(
      source, filter: ScanFilter.enhance, documentMode: true))!;
    final paper = output.getPixel(25, 35);
    final face = output.getPixel(80, 88);
    final text = output.getPixel(80, 158);
    expect(paper.r, greaterThan(200));
    expect(paper.b, greaterThan(155));
    expect(face.r, lessThan(235));
    expect(text.r, lessThan(85));
  });

  test('Invert effect reverses a mid-tone pixel', () async {
    final input = img.Image(width: 16, height: 16);
    img.fill(input, color: img.ColorRgb8(40, 90, 160));
    final output = img.decodeImage(await ImageProcessor.process(
      Uint8List.fromList(img.encodeJpg(input, quality: 100)),
      filter: ScanFilter.invert,
    ));
    expect(output, isNotNull);
    expect(output!.getPixel(8, 8).r, greaterThan(190));
    expect(output.getPixel(8, 8).b, lessThan(125));
  });

  test('All scanner effect presets produce decodable images', () async {
    final input = img.Image(width: 48, height: 48);
    for (var y = 0; y < 48; y++) {
      for (var x = 0; x < 48; x++) {
        input.setPixelRgb(x, y, x * 4, y * 4, 160);
      }
    }
    final bytes = Uint8List.fromList(img.encodeJpg(input, quality: 100));
    for (final filter in ScanFilter.values.where((v) => v != ScanFilter.original)) {
      final result = img.decodeImage(await ImageProcessor.process(
        bytes, filter: filter,
      ));
      expect(result, isNotNull, reason: filter.name);
      expect(result!.width, 48);
    }
  });
}
