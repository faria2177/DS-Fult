import 'package:docscanner/src/models.dart';
import 'package:docscanner/src/screens/compress_screen.dart';
import 'package:docscanner/src/screens/lock_document_screen.dart';
import 'package:docscanner/src/screens/reorder_pages_screen.dart';
import 'package:docscanner/src/storage/document_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _ToolStore extends DocumentStore {
  ScanDocument doc = ScanDocument(
    id: 'document-1', name: 'Test Scan',
    createdAt: DateTime(2026, 11, 8),
    pages: const [
      ScanPage(id: 'page-1', path: '/missing-1.jpg',
          originalPath: '/missing-1.jpg'),
      ScanPage(id: 'page-2', path: '/missing-2.jpg',
          originalPath: '/missing-2.jpg'),
    ],
  );
  List<String>? committedOrder;

  @override
  ScanDocument? byId(String id) => id == doc.id ? doc : null;

  @override
  Future<void> setPageOrder(String documentId, List<String> pageIds) async {
    committedOrder = List.of(pageIds);
    doc = doc.copyWith(pages: [
      for (final id in pageIds) doc.pages.firstWhere((page) => page.id == id),
    ]);
    notifyListeners();
  }

  @override
  Future<void> setLockHash(String documentId, String? hash) async {
    doc = doc.copyWith(lockHash: hash, clearLock: hash == null);
    notifyListeners();
  }
}

void main() {
  test('watermark backup survives JSON, but later edits may clear it', () {
    const page = ScanPage(id: 'page', path: '/after.png',
        originalPath: '/original.png',
        watermarkBackupPath: '/before.png');
    expect(ScanPage.fromJson(page.toJson()).watermarkBackupPath, '/before.png');
    expect(page.copyWith(path: '/other.png', clearWatermark: true)
        .watermarkBackupPath, isNull);
  });

  test('compression level names map to different quality presets', () {
    expect(CompressionLevel.medium.imageQuality,
        greaterThan(CompressionLevel.high.imageQuality));
    expect(CompressionLevel.high.label, 'High');
  });

  testWidgets('page reorder is staged until user confirms', (tester) async {
    final store = _ToolStore();
    await tester.pumpWidget(MaterialApp(home: ReorderPagesScreen(
      store: store, documentId: store.doc.id,
    )));
    await tester.pump();
    expect(find.text('01'), findsOneWidget);
    expect(find.text('02'), findsOneWidget);
    expect(store.committedOrder, isNull);
    await tester.tap(find.byTooltip('Cancel'));
    await tester.pump();
    expect(store.committedOrder, isNull);
  });

  testWidgets('lock requires matching passwords of at least six characters',
      (tester) async {
    final store = _ToolStore();
    await tester.pumpWidget(MaterialApp(home: LockDocumentScreen(
      store: store, documentId: store.doc.id,
    )));
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), '123');
    await tester.enterText(fields.at(1), '123');
    await tester.tap(find.widgetWithText(FilledButton, 'Lock'));
    await tester.pump();
    expect(find.text('Password must be at least 6 characters.'), findsWidgets);
    expect(store.doc.lockHash, isNull);
    await tester.enterText(fields.at(0), 'correct123');
    await tester.enterText(fields.at(1), 'incorrect123');
    await tester.tap(find.widgetWithText(FilledButton, 'Lock'));
    await tester.pump();
    expect(find.text('Passwords do not match.'), findsOneWidget);
    expect(store.doc.lockHash, isNull);
    await tester.enterText(fields.at(1), 'correct123');
    await tester.tap(find.widgetWithText(FilledButton, 'Lock'));
    await tester.pump();
    expect(store.doc.lockHash, isNotNull);
    expect(store.doc.lockHash, isNot('correct123'));
  });
}
