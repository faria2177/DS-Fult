import 'dart:typed_data';
import 'dart:ui';

import 'package:docscanner/src/services/text_style_matcher.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

/// A grainy paper page with dark "glyph" bars on one line and a vertical
/// table border running through it.
Uint8List page() {
  final image = img.Image(width: 200, height: 100);
  for (var y = 0; y < 100; y++) {
    for (var x = 0; x < 200; x++) {
      final grain = ((x * 7 + y * 13) % 9) - 4; // deterministic texture
      image.setPixelRgb(x, y, 236 + grain, 233 + grain, 226 + grain);
    }
  }
  // Glyphs: three dark navy bars between y 40..52.
  for (final x0 in [40, 60, 80]) {
    for (var y = 40; y < 52; y++) {
      for (var x = x0; x < x0 + 10; x++) {
        image.setPixelRgb(x, y, 20, 30, 70);
      }
    }
  }
  // Vertical table border through the line box.
  for (var y = 0; y < 100; y++) {
    image.setPixelRgb(120, y, 0, 0, 0);
  }
  return Uint8List.fromList(img.encodePng(image));
}

void main() {
  test('erasing a line removes only the glyphs and keeps paper and borders',
      () {
    final result = LineAnalysis.fromMap(analyzeAndEraseLine({
      'bytes': page(),
      'area': [.18, .38, .65, .54],
    }));
    final out = img.decodePng(result.cleared)!;

    // Glyph pixels became paper-coloured.
    final glyph = out.getPixel(45, 46);
    expect(glyph.r, greaterThan(215));
    // The table border crossing the line survives.
    expect(out.getPixel(120, 46).r, lessThan(40));
    // Paper away from glyphs is untouched (texture kept, no flat patch).
    final original = img.decodePng(page())!;
    expect(out.getPixel(100, 46).r, original.getPixel(100, 46).r);
    expect(out.getPixel(5, 5).r, original.getPixel(5, 5).r);

    // Ink colour is the navy of the strokes; box hugs the glyphs.
    expect(result.ink[2], greaterThan(result.ink[0]));
    expect(result.ink[0], lessThan(60));
    expect(result.inkBox.left, closeTo(40, 1));
    expect(result.inkBox.right, closeTo(90, 1));
    expect(result.inkBox.top, closeTo(40, 1));
    expect(result.inkBox.bottom, closeTo(52, 1));
  });

  test('mask similarity prefers the matching shape', () {
    Uint8List bars(List<int> starts, int w, int h, {int bar = 4}) {
      final m = Uint8List(w * h);
      for (final s in starts) {
        for (var y = 0; y < h; y++) {
          for (var x = s; x < s + bar && x < w; x++) {
            m[y * w + x] = 1;
          }
        }
      }
      return m;
    }

    final printed = bars([0, 8, 16], 20, 10);
    const box = Rect.fromLTRB(0, 0, 20, 10);
    final same = maskSimilarity(a: printed, aStride: 20, aBox: box,
        b: bars([0, 16, 32], 40, 10, bar: 8), bStride: 40,
        bBox: const Rect.fromLTRB(0, 0, 40, 10));
    final different = maskSimilarity(a: printed, aStride: 20, aBox: box,
        b: bars([0, 4, 8, 12, 16], 20, 10), bStride: 20, bBox: box);
    expect(same, greaterThan(.8));
    expect(same, greaterThan(different));
  });

  test('alignment follows the neighbouring lines', () {
    const body = [
      Rect.fromLTRB(.10, .30, .90, .33),
      Rect.fromLTRB(.10, .35, .70, .38),
    ];
    expect(guessAlignment(const Rect.fromLTRB(.10, .40, .50, .43), body),
        LineAlignment.left);
    expect(guessAlignment(const Rect.fromLTRB(.35, .20, .65, .23), body),
        LineAlignment.center);
    expect(guessAlignment(const Rect.fromLTRB(.62, .12, .90, .15), [
      ...body, const Rect.fromLTRB(.70, .08, .90, .11),
    ]), LineAlignment.right);
  });
}
