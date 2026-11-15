import 'package:docscanner/src/screens/smart_erase_screen.dart';
import 'package:docscanner/src/storage/document_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Smart Erase supports all five reference modes', () {
    expect(SmartEraseMode.values, [
      SmartEraseMode.pen,
      SmartEraseMode.rectangle,
      SmartEraseMode.magic,
      SmartEraseMode.handwriting,
      SmartEraseMode.text,
    ]);
  });

  testWidgets('CamScanner-style toolbar switches actual local erase modes',
      (tester) async {
    tester.view.physicalSize = const Size(800, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final store = DocumentStore();
    addTearDown(store.dispose);
    await tester.pumpWidget(MaterialApp(home: SmartEraseScreen(
      store: store,
      documentId: 'missing',
      pageId: 'missing',
    )));
    await tester.pump();
    expect(find.text('Smart Erase'), findsOneWidget);
    expect(find.text('Pen'), findsOneWidget);
    expect(find.text('Rectangle'), findsOneWidget);
    expect(find.text('Magic'), findsOneWidget);
    expect(find.text('Handwriting'), findsOneWidget);
    expect(find.text('Erase Text'), findsOneWidget);
    expect(find.byTooltip('Cancel Smart Erase'), findsOneWidget);
    expect(find.byTooltip('Apply Smart Erase'), findsOneWidget);

    await tester.tap(find.byKey(const Key('smart-erase-rectangle')));
    await tester.pump();
    expect(find.text('Drag a rectangle to remove the selected area'),
        findsOneWidget);

    await tester.tap(find.byKey(const Key('smart-erase-magic')));
    await tester.pump();
    expect(find.text('Brush over a mark: locally match its background'),
        findsOneWidget);

    // The brush-size picker is a bottom sheet, not a popup obscured by
    // the horizontally scrolling toolbar. Verify every choice is visible
    // and tapping a real choice actually returns to Pen mode.
    await tester.tap(find.byKey(const Key('smart-erase-pen')));
    // Modal route transitions need an initial frame to *start* the 250 ms
    // animation, followed by a later frame to complete it. A single
    // pump(Duration) can still leave the sheet below the hit-test viewport.
    // Do not pumpAndSettle: the editor has an intentional endless loading
    // indicator when this test uses a missing source document.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Pen size'), findsOneWidget);
    expect(find.text('Pen · Fine'), findsOneWidget);
    expect(find.text('Pen · Medium'), findsOneWidget);
    expect(find.text('Pen · Large'), findsOneWidget);
    expect(find.text('Pen · Extra large'), findsOneWidget);
    final fine = find.text('Pen · Fine');
    expect(tester.getTopLeft(fine).dy, greaterThanOrEqualTo(0));
    expect(tester.getBottomRight(fine).dy, lessThanOrEqualTo(1100));
    await tester.tap(fine);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Pen size'), findsNothing);
    expect(tester.widget<Slider>(find.byType(Slider)).value,
        closeTo(.006, .00001));
    expect(find.text('Draw a brush stroke to erase the selected mark'),
        findsOneWidget);
  });
}
