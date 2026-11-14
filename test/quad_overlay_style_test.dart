import 'dart:ui' as ui;

import 'package:doclens/doclens.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('live filled green quad uses the more visible border', () {
    final filled = quadOverlayFor(
      style: QuadOverlayStyle.filled,
      quad: null,
      status: DetectionStatus.searching,
    );
    expect(filled.strokeWidth, 5.0);

    // Other overlay modes retain their original stroke proportions.
    final outline = quadOverlayFor(
      style: QuadOverlayStyle.outline,
      quad: null,
      status: DetectionStatus.searching,
    );
    expect(outline.strokeWidth, 2.0);
  });

  testWidgets('green line is opaque and fill stays very faint', (tester) async {
    final key = GlobalKey();
    const quad = Quad(
      topLeft: Offset(.25, .25),
      topRight: Offset(.75, .25),
      bottomRight: Offset(.75, .75),
      bottomLeft: Offset(.25, .75),
    );
    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: Center(
        child: RepaintBoundary(
          key: key,
          child: const SizedBox(
            width: 200,
            height: 200,
            child: QuadOverlay.filled(
              quad: quad,
              status: DetectionStatus.aligned,
              accent: Color(0xFF00B69B),
            ),
          ),
        ),
      ),
    ));
    await tester.pump();
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(key),
    );
    final frame = await boundary.toImage(pixelRatio: 1);
    try {
      final data = await frame.toByteData(format: ui.ImageByteFormat.rawRgba);
      expect(data, isNotNull);
      final rgba = data!.buffer.asUint8List();
      int alphaAt(int x, int y) => rgba[(y * 200 + x) * 4 + 3];
      // Strong green on the centre of the detected border.
      expect(alphaAt(50, 100), greaterThan(210));
      expect(alphaAt(49, 100), greaterThan(210));
      // Outside has no permanent camera-frame border.
      expect(alphaAt(40, 100), lessThan(25));
      // Interior mint stays very subtle, not a solid overlay on text.
      expect(alphaAt(80, 100), greaterThan(0));
      expect(alphaAt(80, 100), lessThan(40));
    } finally {
      frame.dispose();
    }
  });
}
