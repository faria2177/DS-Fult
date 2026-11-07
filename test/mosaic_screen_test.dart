import 'dart:typed_data';
import 'dart:ui';

import 'package:docscanner/src/screens/mosaic_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void main() {
  test('mosaic changes only the selected region', () {
    final source = img.Image(width: 96, height: 96);
    for (var y = 0; y < 96; y++) {
      for (var x = 0; x < 96; x++) {
        source.setPixelRgb(x, y, x * 2, y * 2, 40);
      }
    }
    final output = mosaicImageBytes(
      Uint8List.fromList(img.encodePng(source)),
      const Rect.fromLTRB(.25, .25, .75, .75),
    );
    final decoded = img.decodeJpg(output)!;
    final a = decoded.getPixel(30, 30);
    final b = decoded.getPixel(36, 36);
    final outside = decoded.getPixel(4, 4);
    expect((a.r - b.r).abs(), lessThan(8));
    expect(outside.r, lessThan(20));
  });
}
