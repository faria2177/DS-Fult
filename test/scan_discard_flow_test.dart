import 'dart:io';

import 'package:docscanner/src/screens/document_screen.dart';
import 'package:docscanner/src/screens/scan_dialogs.dart';
import 'package:docscanner/src/storage/document_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory base;
  late File photo;

  setUp(() async {
    base = await Directory.systemTemp.createTemp('ds_discard_');
    photo = File(p.join(base.path, 'photo.png'));
    await photo.writeAsBytes(_onePixelPng);
  });

  tearDown(() => base.delete(recursive: true));

  Future<DocumentStore> open() async {
    final store = DocumentStore();
    await store.initialize(baseDirectory: base);
    return store;
  }

  test('a discarded scan leaves no document and no copied images', () async {
    final store = await open();
    final kept = await store.createFromPaths([photo.path], name: 'Kept');
    final draft = await store.createFromPaths([photo.path], name: 'Draft');
    final draftImage = draft.pages.single.path;
    expect(File(draftImage).existsSync(), isTrue);

    await store.discardScan(draft.id);

    expect(store.byId(draft.id), isNull);
    expect(File(draftImage).existsSync(), isFalse);
    expect(File(kept.pages.single.path).existsSync(), isTrue);
    expect(photo.existsSync(), isTrue, reason: 'never touch the source');
    expect((await open()).documents.map((d) => d.name), ['Kept']);
  });

  Future<void> pushScreen(WidgetTester tester, DocumentStore store,
      String id) async {
    var finished = false;
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) =>
        Scaffold(body: Center(child: TextButton(
          onPressed: () async {
            await Navigator.push<bool>(context, MaterialPageRoute(
              builder: (_) => DocumentScreen(store: store, documentId: id,
                  initialPreview: true, confirmDiscard: true),
            ));
            finished = true;
          },
          child: const Text('open'),
        ))))));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(finished, isFalse);
  }

  testWidgets('back on a new scan asks before discarding', (tester) async {
    final store = await tester.runAsync(open);
    final doc = await tester.runAsync(
        () => store!.createFromPaths([photo.path], name: 'Draft'));
    await pushScreen(tester, store!, doc!.id);

    // Back does not leave silently.
    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    await navigator.maybePop();
    await tester.pumpAndSettle();
    expect(find.text('Discard Scans'), findsOneWidget);
    expect(find.text('Closing will discard the scans you captured.'),
        findsOneWidget);

    // Cancel keeps the user on the scan.
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Discard Scans'), findsNothing);
    expect(find.byType(DocumentScreen), findsOneWidget);

    // Discard leaves the screen.
    await navigator.maybePop();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();
    expect(find.byType(DocumentScreen), findsNothing);
    expect(find.text('open'), findsOneWidget);
  });

  testWidgets('processing dialog shows percent and count', (tester) async {
    final progress = ValueNotifier(const ScanProgress(0, 2));
    late VoidCallback close;
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) =>
        Scaffold(body: TextButton(
          onPressed: () => close = showProcessingDialog(context, progress),
          child: const Text('go'))))));
    await tester.tap(find.text('go'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Processing… 0%'), findsOneWidget);
    expect(find.text('0/2'), findsOneWidget);

    progress.value = const ScanProgress(1, 2);
    await tester.pump();
    expect(find.text('Processing… 50%'), findsOneWidget);
    expect(find.text('1/2'), findsOneWidget);

    close();
    close(); // closing twice must not pop the page underneath
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('processing-label')), findsNothing);
    expect(find.text('go'), findsOneWidget);
  });
}

/// A valid 1×1 white PNG so Image.file never reports a decode error.
const _onePixelPng = <int>[137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 13, 73, 72, 68, 82, 0, 0, 0, 1, 0, 0, 0, 1, 8, 2, 0, 0, 0, 144, 119, 83, 222, 0, 0, 0, 12, 73, 68, 65, 84, 120, 156, 99, 248, 255, 255, 63, 0, 5, 254, 2, 254, 13, 239, 70, 184, 0, 0, 0, 0, 73, 69, 78, 68, 174, 66, 96, 130];
