import 'dart:typed_data';

import 'package:docscanner/src/screens/signature_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void main() {
  testWidgets('signature is applied only to the chosen stroke location', (tester) async {
    final page = img.Image(width: 100, height: 100);
    img.fill(page, color: img.ColorRgb8(255, 255, 255));
    final input = Uint8List.fromList(img.encodePng(page));

    // Image codec and GPU-backed picture encoding need the real async clock.
    final signed = await tester.runAsync(() => SignatureComposer.composite(input, [
      [const Offset(.20, .50), const Offset(.80, .50)],
    ]));
    expect(signed, isNotNull);
    final result = img.decodePng(signed!)!;
    final inside = result.getPixel(50, 50);
    final outside = result.getPixel(50, 10);

    expect(inside.r, lessThan(100));
    expect(outside.r, greaterThan(245));
  });

  testWidgets('brush preserves distinct colors for individual strokes',
      (tester) async {
    final page = img.Image(width: 150, height: 150);
    img.fill(page, color: img.ColorRgb8(255, 255, 255));
    final result = await tester.runAsync(() => SignatureComposer.composite(
      Uint8List.fromList(img.encodePng(page)), [
        [const Offset(.2, .3), const Offset(.8, .3)],
        [const Offset(.2, .7), const Offset(.8, .7)],
      ], strokeColors: [Colors.red, Colors.blue], strokeScales: [.02, .02],
    ));
    final image = img.decodePng(result!)!;
    final red = image.getPixel(75, 45);
    final blue = image.getPixel(75, 105);
    expect(red.r, greaterThan(red.b + 100));
    expect(blue.b, greaterThan(blue.r + 100));
  });
}
