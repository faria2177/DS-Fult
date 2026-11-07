import 'package:doclens/doclens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('framed scanner keeps the preview separate from controls',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    var captured = 0;
    bool? switchedToBatch;
    var openedIds = 0;

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ReferenceScanChrome(
          preview: const ColoredBox(color: Colors.red),
          flashMode: FlashMode.off,
          batchMode: false,
          pageCount: 0,
          capturing: false,
          accent: const Color(0xFF15BFA9),
          onClose: () {},
          onFlash: () {},
          onCapture: () => captured++,
          onBatchChanged: (value) => switchedToBatch = value,
          onFinishBatch: () {},
          onImportFiles: () {},
          onImportImages: () {},
          onIdCards: () => openedIds++,
        ),
      ),
    ));

    expect(find.text('Single'), findsOneWidget);
    expect(find.text('Batch'), findsOneWidget);
    expect(find.text('Scan'), findsOneWidget);
    expect(find.text('ID Cards'), findsOneWidget);
    expect(find.text('Import Files'), findsOneWidget);
    expect(find.text('Import\nImages'), findsOneWidget);

    final view = tester.getRect(find.byKey(const Key('reference-preview')));
    expect(view.top, greaterThan(60));
    expect(view.bottom, lessThan(710));

    await tester.tap(find.byKey(const Key('reference-shutter')));
    await tester.pump();
    expect(captured, 1);

    await tester.tap(find.text('Batch'));
    expect(switchedToBatch, isTrue);

    await tester.tap(find.text('ID Cards'));
    expect(openedIds, 1);
  });
}
