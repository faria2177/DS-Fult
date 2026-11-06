import 'dart:typed_data';
import 'dart:ui';

import 'package:docscanner/src/services/image_text_processor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Erasing a region leaves other image pixels unchanged', () async {
    final source = img.Image(width: 80, height: 60);
    img.fill(source, color: img.ColorRgb8(238, 238, 238));
    for (var y = 23; y < 29; y++) {
      for (var x = 15; x < 56; x++) {
        source.setPixelRgb(x, y, 0, 0, 0);
      }
    }
    final bytes = Uint8List.fromList(img.encodePng(source));
    final output = img.decodeImage(await ImageTextProcessor.replace(bytes,
      normalizedArea: const Rect.fromLTRB(.17, .35, .75, .50),
      replacement: '',
    ));
    expect(output, isNotNull);
    expect(output!.getPixel(30, 25).r, greaterThan(220));
    expect(output.getPixel(5, 5).r, 238);
  });
}
