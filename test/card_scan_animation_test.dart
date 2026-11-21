import 'package:doclens/doclens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('card scan animation sweeps, flattens and finishes once',
      (tester) async {
    var done = 0;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: SizedBox(
      width: 360, height: 600,
      child: CardScanAnimation(
        rawImagePath: '/missing/raw.jpg',
        rawImageSize: const Size(1200, 1600),
        quad: const Quad(
          topLeft: Offset(150, 600), topRight: Offset(1050, 560),
          bottomRight: Offset(1080, 1120), bottomLeft: Offset(170, 1160)),
        croppedImagePath: '/missing/card.jpg',
        onDone: () => done++,
      ),
    ))));
    await tester.pump(const Duration(milliseconds: 300));
    expect(done, 0);
    await tester.pump(const Duration(milliseconds: 600));
    expect(done, 0);
    await tester.pump(const Duration(milliseconds: 500));
    expect(done, 1);
    await tester.pump(const Duration(milliseconds: 500));
    expect(done, 1);
    expect(tester.takeException(), isNull);
  });
}
