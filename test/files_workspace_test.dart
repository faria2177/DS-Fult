import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:docscanner/src/models.dart';
import 'package:docscanner/src/screens/files_workspace.dart';
import 'package:docscanner/src/storage/document_store.dart';

class _FileStore extends DocumentStore {
  final List<ScanDocument> items = [
    ScanDocument(id: 'a', name: 'First form', createdAt: DateTime(2026, 11, 7),
        pages: const [ScanPage(id: 'ap', path: '/missing-a.jpg',
            originalPath: '/missing-a.jpg')]),
    ScanDocument(id: 'b', name: 'Second form', createdAt: DateTime(2026, 11, 6),
        pages: const [ScanPage(id: 'bp', path: '/missing-b.jpg',
            originalPath: '/missing-b.jpg')]),
  ];

  @override
  List<ScanDocument> get documents => List.unmodifiable(items);

  @override
  List<DocumentFolder> get folders => const [];

  @override
  Future<void> renameDocument(String id, String name) async {
    final index = items.indexWhere((doc) => doc.id == id);
    items[index] = items[index].copyWith(name: name);
    notifyListeners();
  }
}

void main() {
  testWidgets('Files supports long-press selection, select all and merge entry',
      (tester) async {
    final store = _FileStore();
    bool? selecting;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: FilesWorkspace(
      store: store,
      onOpen: (_) async {}, onImport: () {}, onScan: () {},
      onSelectionChanged: (value) => selecting = value,
    ))));
    expect(find.text('First form'), findsOneWidget);
    expect(find.text('Second form'), findsOneWidget);
    await tester.longPress(find.text('First form'));
    await tester.pumpAndSettle();
    expect(selecting, true);
    expect(find.text('1 selected'), findsOneWidget);
    expect(find.text('Rename'), findsOneWidget);
    await tester.tap(find.text('Select All'));
    await tester.pumpAndSettle();
    expect(find.text('2 selected'), findsOneWidget);
    expect(find.text('Merge'), findsOneWidget);
    await tester.tap(find.text('Merge'));
    await tester.pumpAndSettle();
    expect(find.text('Merge Documents'), findsWidgets);
    expect(find.text('Keep originals'), findsOneWidget);
    expect(find.text('Add File'), findsOneWidget);
  });
}
