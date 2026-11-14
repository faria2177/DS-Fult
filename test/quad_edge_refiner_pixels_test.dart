import 'dart:math' as math;
import 'dart:typed_data';

import 'package:docscanner/src/services/quad_edge_refiner.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

/// Reproducible pixel fixture with a large paper sheet, soft patterned desk
/// and several strong interior ink lines. No network, models or camera needed.
Uint8List makePage({bool showDocument = true}) {
  final image = img.Image(width: 320, height: 240);
  for (var y = 0; y < 240; y++) {
    for (var x = 0; x < 320; x++) {
      final texture = ((x * 7 + y * 11) % 9) - 4;
      var r = 39 + texture, g = 43 + texture, b = 47 + texture;
      if (showDocument && x >= 45 && x < 275 && y >= 25 && y < 210) {
        // Mild illumination gradient across the page.
        final light = 228 + x * 13 ~/ 320;
        r = light;
        g = light;
        b = light - 1;
        if (x > 115 && x < 204 && y > 56 && y < 175 &&
            (y % 16) < 4) {
          r = 75;
          g = 75;
          b = 77;
        }
      }
      image.setPixelRgb(x, y, r, g, b);
    }
  }
  return Uint8List.fromList(img.encodePng(image));
}

double cornerError(List<double> got, List<double> target) {
  var sum = 0.0;
  for (var i = 0; i < 4; i++) {
    sum += math.sqrt(
        math.pow((got[i * 2] - target[i * 2]) * 320, 2) +
        math.pow((got[i * 2 + 1] - target[i * 2 + 1]) * 240, 2));
  }
  return sum / 4;
}

void main() {
  final actual = <double>[
    45 / 320, 25 / 240,
    275 / 320, 25 / 240,
    275 / 320, 210 / 240,
    45 / 320, 210 / 240,
  ];
  final initial = <double>[
    51 / 320, 31 / 240,
    269 / 320, 31 / 240,
    269 / 320, 204 / 240,
    51 / 320, 204 / 240,
  ];

  test('real image pixels refine all four paper edges despite inner text', () {
    final pixels = makePage();
    final result = QuadEdgeRefiner.refineBytes(pixels, initial);
    expect(result, isNotNull);
    final errorBefore = cornerError(initial, actual);
    final errorAfter = cornerError(result!, actual);
    expect(errorAfter, lessThan(errorBefore));
    expect(errorAfter, lessThan(5.0));
  });

  test('flat scene cannot invent corners or enlarge the initial outline', () {
    final result = QuadEdgeRefiner.refineBytes(
        makePage(showDocument: false), initial);
    // The refiner may return null or the unchanged input, never a fabricated
    // quad in the absence of an image edge.
    if (result != null) {
      expect(cornerError(result, initial), lessThan(.25));
    }
  });

  test('malformed image-space corners are rejected before sampling', () {
    final pixels = makePage();
    expect(QuadEdgeRefiner.refineBytes(pixels,
        [-.02, .1, .9, .1, .9, .9, .1, .9]), isNull);
    expect(QuadEdgeRefiner.refineBytes(pixels,
        [.1, .1, .9, .9, .9, .1, .1, .9]), isNull);
  });
}
