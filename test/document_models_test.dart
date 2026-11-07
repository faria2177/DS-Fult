import 'package:docscanner/src/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('document model round-trips with pages and local path', () {
    final original = ScanDocument(
      id: 'doc1',
      name: 'My scan',
      createdAt: DateTime.utc(2026, 11, 6),
      pages: const [
        ScanPage(id: 'p1', path: '/tmp/edited.jpg',
            originalPath: '/tmp/scan.jpg', recognizedText: 'Hello world'),
      ],
      kind: DocumentKind.idCard,
      folderId: 'folder1',
      tags: const ['Work', 'Receipt'],
      lockHash: 'example-hash',
    );
    final loaded = ScanDocument.fromJson(original.toJson());
    expect(loaded.name, original.name);
    expect(loaded.kind, DocumentKind.idCard);
    expect(loaded.folderId, 'folder1');
    expect(loaded.pages.first.recognizedText, 'Hello world');
    expect(loaded.pages.first.originalPath, '/tmp/scan.jpg');
    expect(loaded.tags, ['Work', 'Receipt']);
    expect(loaded.lockHash, 'example-hash');
    final titled = loaded.pages.first.copyWith(title: 'Back');
    expect(ScanPage.fromJson(titled.toJson()).title, 'Back');
    final retaken = titled.copyWith(path: '/tmp/new.jpg',
        originalPath: '/tmp/new.jpg');
    expect(retaken.originalPath, '/tmp/new.jpg');
  });

  test('two-sided kinds have a documented two-image limit', () {
    expect(DocumentKind.idCard.twoSided, isTrue);
    expect(DocumentKind.driverLicense.twoSided, isTrue);
    expect(DocumentKind.bankCard.twoSided, isTrue);
    expect(DocumentKind.document.twoSided, isFalse);
  });
}
