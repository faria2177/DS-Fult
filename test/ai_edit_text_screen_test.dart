import 'dart:io';
import 'dart:typed_data';

import 'package:docscanner/src/screens/ai_edit_text_screen.dart';
import 'package:docscanner/src/services/image_text_processor.dart';
import 'package:docscanner/src/storage/document_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late Directory base;
  late DocumentStore store;
  late String documentId;
  late String pageId;
  final page = Uint8List.fromList(img.encodePng(
      img.Image(width: 400, height: 240)
        ..clear(img.ColorRgb8(255, 255, 255))));

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    base = await Directory.systemTemp.createTemp('ds_edit_text_');
    final photo = File(p.join(base.path, 'card.png'));
    await photo.writeAsBytes(page);
    store = DocumentStore();
    await store.initialize(baseDirectory: base);
    final doc = await store.createFromPaths([photo.path], name: 'Card');
    documentId = doc.id;
    pageId = doc.pages.single.id;
  });

  tearDown(() => base.delete(recursive: true));

  Widget app({required List<Uint8List> saved,
      required List<String> replaced}) => MaterialApp(
    home: Builder(builder: (context) => Scaffold(body: Center(
      child: TextButton(
        onPressed: () => Navigator.push(context, MaterialPageRoute(
          builder: (_) => AiEditTextScreen(
            store: store, documentId: documentId, pageId: pageId,
            readBytes: (_) async => page,
            recognize: (_, _) async => const [
              EditableTextLine(Rect.fromLTRB(.30, .40, .70, .48),
                  '(Card Business)'),
              EditableTextLine(Rect.fromLTRB(.10, .60, .50, .66),
                  'PUBALI BANK PLC.'),
            ],
            replace: (bytes, _, text) async {
              replaced.add(text);
              return Uint8List.fromList([...bytes]);
            },
            save: (bytes) async => saved.add(bytes),
            minAnalyzeTime: const Duration(milliseconds: 1000),
            minProcessTime: const Duration(milliseconds: 300),
          ))),
        child: const Text('open'))))),
  );

  testWidgets('analyse, edit a line, process and save like CamScanner',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 2200);
    tester.view.devicePixelRatio = 2.7;
    addTearDown(tester.view.reset);
    final saved = <Uint8List>[];
    final replaced = <String>[];
    await tester.pumpWidget(app(saved: saved, replaced: replaced));
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    expect(find.text('DS AI is analyzing'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 800));
    await tester.pump();
    expect(find.text('DS AI is analyzing'), findsNothing);
    expect(find.text('Tap text or image to edit.'), findsOneWidget);
    expect(find.text('32 characters'), findsOneWidget);

    // Tap the "(Card Business)" line: the CamScanner menu appears.
    final canvas = tester.getRect(find.byKey(const Key('edit-text-canvas')));
    await tester.tapAt(Offset(canvas.left + canvas.width * .5,
        canvas.top + canvas.height * .44));
    await tester.pump();
    for (final item in ['Copy', 'Delete', 'Select All', 'DS AI',
        'Edit Text', 'AI Proofread', 'AI Polish']) {
      expect(find.text(item), findsOneWidget, reason: item);
    }

    await tester.tap(find.text('Edit Text'));
    await tester.pumpAndSettle();
    expect(find.text('DS AI matches your text to the original font style.'),
        findsOneWidget);
    final confirm = find.byKey(const Key('edit-text-confirm'));
    expect(tester.widget<FilledButton>(confirm).onPressed, isNull,
        reason: 'Confirm stays disabled until the text changes');
    await tester.enterText(find.byKey(const Key('edit-text-field')),
        '(Card Business Division)');
    await tester.pump();
    await tester.tap(confirm);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('DS AI is processing'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Processing complete'), findsOneWidget);
    expect(replaced, ['(Card Business Division)']);
    expect(find.text('41 characters'), findsOneWidget);
    expect(find.byTooltip('Undo'), findsOneWidget);
    expect(saved, isEmpty, reason: 'nothing is written before Save');

    await tester.tap(find.byKey(const Key('edit-text-save')));
    await tester.pumpAndSettle();
    expect(find.text("Changes can't be undone once saved."), findsOneWidget);
    expect(find.text("Don't ask again for 7 days"), findsOneWidget);
    await tester.tap(find.byKey(const Key('edit-text-save-confirm')));
    await tester.pumpAndSettle();
    expect(saved, hasLength(1));
    expect(find.byType(AiEditTextScreen), findsNothing);
  });

  testWidgets('closing with unsaved edits asks first', (tester) async {
    tester.view.physicalSize = const Size(1080, 2200);
    tester.view.devicePixelRatio = 2.7;
    addTearDown(tester.view.reset);
    final saved = <Uint8List>[];
    await tester.pumpWidget(app(saved: saved, replaced: []));
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1500));
    await tester.pump();
    final canvas = tester.getRect(find.byKey(const Key('edit-text-canvas')));
    await tester.tapAt(Offset(canvas.left + canvas.width * .3,
        canvas.top + canvas.height * .63));
    await tester.pump();
    await tester.tap(find.text('Delete'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('15 characters'), findsOneWidget);

    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    expect(find.text('Discard changes?'), findsOneWidget);
    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();
    expect(find.byType(AiEditTextScreen), findsNothing);
    expect(saved, isEmpty);
  });

  test('centred lines stay centred and may grow to both sides', () {
    final centred = ImageTextProcessor.lineLayout(
        rect: const Rect.fromLTRB(120, 90, 280, 110), imageWidth: 400);
    expect(centred.centered, isTrue);
    expect(centred.maxWidth, closeTo(376, .01));
    final left = ImageTextProcessor.lineLayout(
        rect: const Rect.fromLTRB(40, 140, 200, 160), imageWidth: 400);
    expect(left.centered, isFalse);
    expect(left.maxWidth, closeTo(348, .01));
  });
}
