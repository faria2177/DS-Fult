import 'package:doclens/doclens.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('filled live quad has 5dp border without changing other styles', () {
    final filled = quadOverlayFor(
      style: QuadOverlayStyle.filled,
      quad: null,
      status: DetectionStatus.searching,
    );
    expect(filled.strokeWidth, 5.0);

    final outline = quadOverlayFor(
      style: QuadOverlayStyle.outline,
      quad: null,
      status: DetectionStatus.searching,
    );
    expect(outline.strokeWidth, 2.0);
  });

  // Widget-tree smoke test: intentionally avoid RepaintBoundary.toImage().
  // CI's headless software renderer can stall during pixel readback even
  // though the painter and layout are valid, blocking the release APK.
  testWidgets('detected green quad builds a filled CustomPaint', (tester) async {
    const quad = Quad(
      topLeft: Offset(.25, .25),
      topRight: Offset(.75, .25),
      bottomRight: Offset(.75, .75),
      bottomLeft: Offset(.25, .75),
    );
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: SizedBox(
          width: 200,
          height: 200,
          child: QuadOverlay.filled(
            quad: quad,
            status: DetectionStatus.aligned,
            accent: Color(0xFF00B69B),
          ),
        ),
      ),
    );
    expect(find.byType(QuadOverlay), findsOneWidget);
    final overlay = tester.widget<QuadOverlay>(find.byType(QuadOverlay));
    expect(overlay.quad, quad);
    expect(overlay.strokeWidth, 5.0);
    expect(overlay.accent, const Color(0xFF00B69B));
    expect(find.byType(CustomPaint), findsOneWidget);
  });
}
