import 'dart:typed_data';

import 'package:docscanner/src/services/photo_studio_operations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

Uint8List sampleImage(int width, int height) {
  final source = img.Image(width: width, height: height);
  img.fill(source, color: img.ColorRgb8(255, 255, 255));
  for (var y = height ~/ 4; y < height * 3 ~/ 4; y++) {
    for (var x = width ~/ 4; x < width * 3 ~/ 4; x++) {
      source.setPixelRgb(x, y, 200, 20, 20);
    }
  }
  return Uint8List.fromList(img.encodePng(source));
}

void main() {
  test('resizer accepts custom pixels, JPEG and PNG without distorting', () {
    final source = sampleImage(160, 200);
    final jpeg = img.decodeJpg(PhotoStudioOperations.resizeBytes(source,
      width: 80, height: 100, quality: 86))!;
    final png = img.decodePng(PhotoStudioOperations.resizeBytes(source,
      width: 40, height: 50, png: true))!;
    expect(jpeg.width, 80);
    expect(jpeg.height, 100);
    expect(png.width, 40);
    expect(png.height, 50);
    expect(() => PhotoStudioOperations.resizeBytes(source,
      width: 10000, height: 10000), throwsFormatException);
  });

  test('offline remover clears connected studio background, not subject', () {
    final source = sampleImage(64, 80);
    final transparent = img.decodePng(
      PhotoStudioOperations.removeBackgroundBytes(
        source, tolerance: 35, feather: 0))!;
    expect(transparent.getPixel(0, 0).a, 0);
    expect(transparent.getPixel(30, 40).a, 255);
    expect(transparent.getPixel(30, 40).r, greaterThan(transparent.getPixel(30, 40).g));
    final blue = img.decodePng(
      PhotoStudioOperations.removeBackgroundBytes(source,
        tolerance: 35, replacementArgb: 0xFF4D9AD8))!;
    expect(blue.getPixel(0, 0).b, greaterThan(blue.getPixel(0, 0).r));
    expect(blue.getPixel(0, 0).a, 255);
  });

  test('passport maker produces correct 300 DPI single and print dimensions', () {
    final source = sampleImage(120, 150);
    final single = PhotoStudioOperations.passportBytes(source,
      size: PhotoSizePreset.mm35x45);
    final portrait = img.decodeJpg(single)!;
    expect(portrait.width, 413);
    expect(portrait.height, 531);
    expect(PhotoStudioOperations.sheetCapacity(PhotoSizePreset.mm35x45), 6);
    expect(PhotoStudioOperations.sheetCapacity(PhotoSizePreset.inch2x2), 2);
    final sheet = img.decodeJpg(PhotoStudioOperations.passportSheetBytes(
      single, copies: 6))!;
    expect(sheet.width, 1200);
    expect(sheet.height, 1800);
    expect(() => PhotoStudioOperations.passportSheetBytes(
      single, copies: 7), throwsFormatException);
  });

  test('passport output supports controlled crop and solid background', () {
    final source = sampleImage(90, 120);
    final photo = PhotoStudioOperations.passportBytes(source,
      size: PhotoSizePreset.mm30x40,
      zoom: 1.5, horizontalShift: .3, verticalShift: -.2,
      backdrop: PhotoBackdrop.lightBlue);
    final decoded = img.decodeJpg(photo)!;
    expect(decoded.width, PhotoSizePreset.mm30x40.widthPixels());
    expect(decoded.height, PhotoSizePreset.mm30x40.heightPixels());
    expect(decoded.getPixel(0, 0).b, greaterThan(decoded.getPixel(0, 0).r));
  });
}
