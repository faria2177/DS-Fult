import 'package:doclens/doclens.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

const page = Quad(
  topLeft: Offset(.22, .20),
  topRight: Offset(.78, .18),
  bottomRight: Offset(.80, .82),
  bottomLeft: Offset(.20, .84),
);

Quad? paintedQuad(WidgetTester tester) {
  final paint = tester.widget<CustomPaint>(find.descendant(
    of: find.byType(ScanFrameOverlay),
    matching: find.byType(CustomPaint),
  ).first);
  return (paint.painter as dynamic).quad as Quad?;
}

Widget host(Quad? quad, {Rect region = DoclensVisibleRegion.full}) =>
    Directionality(
      textDirection: TextDirection.ltr,
      child: SizedBox(width: 300, height: 400,
        child: DoclensVisibleRegion(rect: region,
          child: ScanFrameOverlay(quad: quad,
              status: quad == null ? DetectionStatus.searching
                  : DetectionStatus.aligned))),
    );

void main() {
  test('visible region of a 4:3 buffer on a tall screen', () {
    // 480×640 buffer shown cover-fit in a 360×800 viewport: the sides of
    // the buffer are cropped away.
    final r = DoclensVisibleRegion.coverRegion(
        const Size(480, 640), const Size(360, 800));
    expect(r.top, closeTo(0, 1e-9));
    expect(r.height, closeTo(1, 1e-9));
    expect(r.width, closeTo(.6, 1e-6));
    expect(r.left, closeTo(.2, 1e-6));
  });

  testWidgets('searching shows a frame along the screen edges', (tester) async {
    await tester.pumpWidget(host(null));
    final q = paintedQuad(tester)!;
    expect(q.topLeft.dx, lessThan(.02));
    expect(q.topLeft.dy, lessThan(.02));
    expect(q.bottomRight.dx, greaterThan(.98));
    expect(q.bottomRight.dy, greaterThan(.98));
  });

  testWidgets('idle frame follows the visible preview area', (tester) async {
    await tester.pumpWidget(host(null,
        region: const Rect.fromLTWH(.2, 0, .6, 1)));
    final q = paintedQuad(tester)!;
    expect(q.topLeft.dx, closeTo(.2, .02));
    expect(q.topRight.dx, closeTo(.8, .02));
  });

  testWidgets('the frame glides onto the page and back out', (tester) async {
    await tester.pumpWidget(host(null));
    await tester.pumpWidget(host(page));
    await tester.pump(const Duration(milliseconds: 100));
    final midway = paintedQuad(tester)!;
    expect(midway.topLeft.dx, inExclusiveRange(.01, .22));

    await tester.pumpAndSettle();
    expect(paintedQuad(tester)!.maxCornerDistance(page), lessThan(1e-6));

    await tester.pumpWidget(host(null));
    await tester.pumpAndSettle();
    expect(paintedQuad(tester)!.topLeft.dx, lessThan(.02));
  });

  testWidgets('small tracking moves follow the page directly', (tester) async {
    await tester.pumpWidget(host(page));
    await tester.pumpAndSettle();
    final moved = Quad.interpolate(page, const Quad(
      topLeft: Offset(.25, .22), topRight: Offset(.81, .20),
      bottomRight: Offset(.83, .84), bottomLeft: Offset(.23, .86)), 1);
    await tester.pumpWidget(host(moved));
    expect(paintedQuad(tester)!.maxCornerDistance(moved), lessThan(1e-6));
  });
}
