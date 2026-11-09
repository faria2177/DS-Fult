import 'dart:typed_data';

import 'package:docscanner/src/services/image_tool_operations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void main() {
  test('long image exports pages in the original top-to-bottom order', () {
    final red = img.Image(width: 20, height: 15);
    final green = img.Image(width: 20, height: 15);
    img.fill(red, color: img.ColorRgb8(240, 10, 10));
    img.fill(green, color: img.ColorRgb8(10, 240, 10));

    final output = ImageToolOperations.buildLongImageBytes([
      Uint8List.fromList(img.encodePng(red)),
      Uint8List.fromList(img.encodePng(green)),
    ]);
    final decoded = img.decodeJpg(output)!;

    expect(decoded.width, 1100);
    expect(decoded.height, 1650);
    final first = decoded.getPixel(30, 30);
    final second = decoded.getPixel(30, 1000);
    expect(first.r, greaterThan(first.g));
    expect(second.g, greaterThan(second.r));
  });

  test('very long images are rejected rather than exhausting device RAM', () {
    final tall = img.Image(width: 10, height: 200);
    img.fill(tall, color: img.ColorRgb8(255, 255, 255));
    expect(
      () => ImageToolOperations.buildLongImageBytes([
        Uint8List.fromList(img.encodePng(tall)),
      ]),
      throwsFormatException,
    );
  });

  test('long image watermark has its own footer and preserves page pixels', () {
    final page = img.Image(width: 20, height: 15);
    img.fill(page, color: img.ColorRgb8(210, 30, 30));
    final input = Uint8List.fromList(img.encodePng(page));
    final plain = img.decodeJpg(
        ImageToolOperations.buildLongImageBytes([input]))!;
    final marked = img.decodeJpg(
        ImageToolOperations.buildLongImageBytes([input], watermark: true))!;

    expect(plain.height, 825);
    expect(marked.height, plain.height + 56);
    expect(marked.getPixel(20, 20).r, greaterThan(180));
    final footerPixel = marked.getPixel(10, marked.height - 10);
    expect(footerPixel.r, greaterThan(220));
    expect(footerPixel.g, greaterThan(220));
  });

  test('long image cannot be created without source pages', () {
    expect(() => ImageToolOperations.buildLongImageBytes([]),
        throwsFormatException);
  });

  test('long image PDF splits tall content into readable A4 pages', () async {
    final page = img.Image(width: 20, height: 35);
    img.fill(page, color: img.ColorRgb8(70, 120, 160));
    final jpg = ImageToolOperations.buildLongImageBytes([
      Uint8List.fromList(img.encodePng(page)),
    ]);
    final pdf = await ImageToolOperations.longImagePdfBytes(jpg);
    expect(String.fromCharCodes(pdf.take(5)), '%PDF-');
    final body = String.fromCharCodes(pdf);
    expect(RegExp(r'/Type\s*/Page\b').allMatches(body).length,
        greaterThan(1));
  });

  test('collage lays out pages in a two-column grid', () {
    final red = img.Image(width: 30, height: 20);
    final blue = img.Image(width: 30, height: 20);
    img.fill(red, color: img.ColorRgb8(240, 0, 0));
    img.fill(blue, color: img.ColorRgb8(0, 0, 240));
    final collage = img.decodeJpg(ImageToolOperations.buildCollageBytes([
      Uint8List.fromList(img.encodePng(red)),
      Uint8List.fromList(img.encodePng(blue)),
    ]))!;
    expect(collage.width, 1116);
    expect(collage.height, 784);
    final left = collage.getPixel(270, 380);
    final right = collage.getPixel(830, 380);
    expect(left.r, greaterThan(left.b));
    expect(right.b, greaterThan(right.r));
  });
}
