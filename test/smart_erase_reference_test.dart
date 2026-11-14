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

    await tester.tap(find.text('Pen'));
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.text('Pen · Fine'), findsOneWidget);
    await tester.tap(find.text('Pen · Fine'));
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.text('Draw a brush stroke to erase the selected mark'),
        findsOneWidget);
  });
}
