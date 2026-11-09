import 'package:docscanner/src/models.dart';
import 'package:docscanner/src/screens/rotate_pages_screen.dart';
import 'package:docscanner/src/storage/document_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _RotateStore extends DocumentStore {
  final ScanDocument document = ScanDocument(
    id: 'scan', name: 'Sample', createdAt: DateTime(2026, 11, 9),
    pages: const [
      ScanPage(id: 'first', path: '/missing-first.jpg',
          originalPath: '/missing-first.jpg'),
      ScanPage(id: 'second', path: '/missing-second.jpg',
          originalPath: '/missing-second.jpg'),
      ScanPage(id: 'third', path: '/missing-third.jpg',
          originalPath: '/missing-third.jpg'),
    ],
  );
  Map<String, int>? saved;

  @override
  ScanDocument? byId(String id) => id == document.id ? document : null;

  @override
  Future<void> rotatePages(String documentId,
      Map<String, int> clockwiseQuarterTurns) async {
    expect(documentId, document.id);
    saved = Map.of(clockwiseQuarterTurns);
  }
}

void main() {
  testWidgets('Rotate Pages stages multi-page turns until Done',
      (tester) async {
    final store = _RotateStore();
    await tester.pumpWidget(MaterialApp(home: RotatePagesScreen(
      store: store, documentId: 'scan',
    )));

    expect(find.text('Rotate Pages'), findsWidgets);
    expect(find.text('0/3 selected'), findsOneWidget);
    expect(tester.widget<OutlinedButton>(
      find.widgetWithText(OutlinedButton, 'Right 90°')).onPressed, isNull);
    await tester.tap(find.text('Select All'));
    await tester.pump();
    expect(find.text('3/3 selected'), findsOneWidget);
    await tester.tap(find.text('Right 90°'));
    await tester.pump();
    expect(store.saved, isNull);
    expect(tester.widget<RotatedBox>(find.byKey(
      const Key('rotate-preview-first'))).quarterTurns, 1);
    expect(find.text('3 page(s) changed • Save with Done'), findsOneWidget);
    await tester.tap(find.text('180°'));
    await tester.pump();
    expect(tester.widget<RotatedBox>(find.byKey(
      const Key('rotate-preview-first'))).quarterTurns, 3);
    await tester.tap(find.byTooltip('Done'));
    await tester.pump();
    expect(store.saved, {'first': 3, 'second': 3, 'third': 3});
  });

  testWidgets('Left 90 and Reset affect only selected pages; Cancel discards',
      (tester) async {
    final store = _RotateStore();
    await tester.pumpWidget(MaterialApp(home: RotatePagesScreen(
      store: store, documentId: 'scan',
    )));
    // The first two thumbnails are in the visible grid row.
    await tester.tapAt(tester.getTopLeft(
      find.byKey(const Key('rotate-page-first'))) + const Offset(90, 90));
    await tester.pump();
    await tester.tap(find.text('Left 90°'));
    await tester.pump();
    expect(tester.widget<RotatedBox>(find.byKey(
      const Key('rotate-preview-first'))).quarterTurns, 3);
    expect(tester.widget<RotatedBox>(find.byKey(
      const Key('rotate-preview-second'))).quarterTurns, 0);

    await tester.tap(find.text('Reset'));
    await tester.pump();
    expect(tester.widget<RotatedBox>(find.byKey(
      const Key('rotate-preview-first'))).quarterTurns, 0);
    expect(find.text('0 page(s) changed • Save with Done'), findsOneWidget);
    await tester.tap(find.text('Right 90°'));
    await tester.pump();
    await tester.tap(find.byTooltip('Cancel'));
    await tester.pump();
    expect(store.saved, isNull);
  });

  testWidgets('net-zero rotation is not persisted', (tester) async {
    final store = _RotateStore();
    await tester.pumpWidget(MaterialApp(home: RotatePagesScreen(
      store: store, documentId: 'scan',
    )));
    await tester.tap(find.text('Select All'));
    await tester.pump();
    await tester.tap(find.text('Left 90°'));
    await tester.pump();
    await tester.tap(find.text('Right 90°'));
    await tester.pump();
    expect(find.text('0 page(s) changed • Save with Done'), findsOneWidget);
    await tester.tap(find.byTooltip('Done'));
    await tester.pump();
    expect(store.saved, isNull);
  });
}
