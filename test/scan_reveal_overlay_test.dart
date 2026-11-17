import 'package:docscanner/src/screens/scan_reveal_overlay.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('scan animation sweeps without blocking while processing',
      (tester) async {
    var revealed = false;
    await tester.pumpWidget(MaterialApp(home: Scaffold(
      body: ScanRevealOverlay(
        data: const ScanRevealData(
          rawPath: '/nonexistent/raw.jpg',
          imageSize: Size(3000, 4000),
          corners: [Offset(600, 900), Offset(2400, 950), Offset(2350, 3100),
            Offset(650, 3050)],
        ),
        onRevealed: () => revealed = true,
      ),
    )));
    // The line keeps sweeping until a result arrives; nothing completes.
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    expect(find.byType(ScanRevealOverlay), findsOneWidget);
    expect(revealed, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a capture without corners highlights the whole photo',
      (tester) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(
      body: ScanRevealOverlay(
        data: const ScanRevealData(rawPath: '/nonexistent/raw.jpg',
            imageSize: Size(1200, 1600), corners: []),
        onRevealed: () {},
      ),
    )));
    await tester.pump(const Duration(milliseconds: 500));
    expect(tester.takeException(), isNull);
  });
}
