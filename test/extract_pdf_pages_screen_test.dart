import 'package:docscanner/src/models.dart';
import 'package:docscanner/src/screens/extract_pdf_pages_screen.dart';
import 'package:docscanner/src/storage/document_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _ExtractStore extends DocumentStore {
  final ScanDocument source = ScanDocument(
    id: 'source', name: 'Report', createdAt: DateTime(2026, 11, 9),
    pages: const [
      ScanPage(id: 'one', path: '/not-found-1.jpg',
          originalPath: '/not-found-1.jpg'),
      ScanPage(id: 'two', path: '/not-found-2.jpg',
          originalPath: '/not-found-2.jpg'),
      ScanPage(id: 'three', path: '/not-found-3.jpg',
          originalPath: '/not-found-3.jpg'),
    ],
  );
  ScanDocument? extracted;
  List<int>? selected;

  @override
  ScanDocument? byId(String id) {
    if (id == source.id) return source;
    if (id == extracted?.id) return extracted;
    return null;
  }

  @override
  Future<ScanDocument> duplicatePages(
      String documentId, List<int> indices, String name) async {
    selected = List.of(indices);
    extracted = ScanDocument(
      id: 'extracted', name: name, createdAt: DateTime(2026, 11, 9),
      pages: [for (final index in indices) source.pages[index]],
    );
    return extracted!;
  }
}

void main() {
  testWidgets('page extraction requires selection and preserves source',
      (tester) async {
    final store = _ExtractStore();
    await tester.pumpWidget(MaterialApp(home: ExtractPdfPagesScreen(
      store: store, documentId: store.source.id,
    )));
    await tester.pump();
    expect(find.text('Extract PDF Pages'), findsOneWidget);
    expect(find.text('0/3 selected'), findsOneWidget);
    var extract = tester.widget<FilledButton>(
        find.byKey(const Key('extract-confirm')));
    expect(extract.onPressed, isNull);

    await tester.ensureVisible(find.text('Page 3'));
    await tester.tap(find.text('Page 3'));
    await tester.pump();
    expect(find.text('1/3 selected'), findsOneWidget);
    await tester.ensureVisible(find.text('Page 1'));
    await tester.tap(find.text('Page 1'));
    await tester.pump();
    expect(find.text('2/3 selected'), findsOneWidget);
    extract = tester.widget<FilledButton>(
        find.byKey(const Key('extract-confirm')));
    expect(extract.onPressed, isNotNull);

    await tester.tap(find.byKey(const Key('extract-confirm')));
    await tester.pump();
    expect(store.selected, [0, 2]);
    expect(store.source.pages.length, 3);
    expect(store.extracted?.pages.map((page) => page.id).toList(),
        ['one', 'three']);
  });

  testWidgets('select all and deselect all only alter staged selection',
      (tester) async {
    final store = _ExtractStore();
    await tester.pumpWidget(MaterialApp(home: ExtractPdfPagesScreen(
      store: store, documentId: store.source.id,
    )));
    await tester.tap(find.text('Select All'));
    await tester.pump();
    expect(find.text('3/3 selected'), findsOneWidget);
    await tester.tap(find.text('Deselect All'));
    await tester.pump();
    expect(find.text('0/3 selected'), findsOneWidget);
    expect(store.selected, isNull);
    expect(store.source.pages.length, 3);
  });
}
