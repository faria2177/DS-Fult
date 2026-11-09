import 'dart:typed_data';

import 'package:docscanner/src/services/pdf_image_export.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void main() {
  test('PDF image output JPEG/PNG retains full source dimensions', () {
    final page = img.Image(width: 240, height: 360);
    img.fill(page, color: img.ColorRgb8(20, 150, 110));
    final source = Uint8List.fromList(img.encodePng(page));

    final jpeg = img.decodeJpg(PdfImageExport.transcode(
        source, png: false))!;
    final png = img.decodePng(PdfImageExport.transcode(
        source, png: true))!;
    expect(jpeg.width, 240);
    expect(jpeg.height, 360);
    expect(png.width, 240);
    expect(png.height, 360);
    expect(jpeg.getPixel(0, 0).g, greaterThan(jpeg.getPixel(0, 0).r));
    expect(png.getPixel(0, 0).g, greaterThan(png.getPixel(0, 0).r));
  });

  test('image converter rejects bad input without modifying it', () {
    final broken = Uint8List.fromList([0, 1, 2, 3]);
    expect(() => PdfImageExport.transcode(broken, png: true),
        throwsFormatException);
    expect(broken, [0, 1, 2, 3]);
  });
}
