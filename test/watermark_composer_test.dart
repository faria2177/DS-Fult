import 'dart:typed_data';

import 'package:docscanner/src/screens/watermark_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void main() {
  testWidgets('watermark paints text while preserving page corners',
      (tester) async {
    final page = img.Image(width: 240, height: 240);
    img.fill(page, color: img.ColorRgb8(255, 255, 255));
    final result = await tester.runAsync(() => WatermarkComposer.composite(
      Uint8List.fromList(img.encodePng(page)),
      text: 'DS',
      placement: WatermarkPlacement.center,
      color: Colors.black,
      opacity: 1,
      fontFraction: .12,
    ));
    final image = img.decodePng(result!)!;
    final corner = image.getPixel(4, 4);
    expect(corner.r, greaterThan(245));
    var markedPixels = 0;
    for (var y = 65; y < 175; y++) {
      for (var x = 65; x < 175; x++) {
        if (image.getPixel(x, y).r < 180) markedPixels++;
      }
    }
    expect(markedPixels, greaterThan(25));
  });
}
