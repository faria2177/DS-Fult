import 'package:docscanner/src/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a processed scan keeps the original photo in a separate field', () {
    const page = ScanPage(
      id: 'p1',
      path: '/docs/cropped.jpg',
      originalPath: '/docs/cropped.jpg',
      rawSourcePath: '/docs/raw-upright.jpg',
    );
    final decoded = ScanPage.fromJson(page.toJson());
    expect(decoded.path, '/docs/cropped.jpg');
    expect(decoded.originalPath, '/docs/cropped.jpg');
    expect(decoded.rawSourcePath, '/docs/raw-upright.jpg');

    final filtered = decoded.copyWith(path: '/docs/filtered.jpg');
    expect(filtered.originalPath, '/docs/cropped.jpg');
    expect(filtered.rawSourcePath, '/docs/raw-upright.jpg');

    final recropped = filtered.copyWith(
      path: '/docs/recropped.jpg',
      originalPath: '/docs/recropped.jpg',
    );
    expect(recropped.rawSourcePath, '/docs/raw-upright.jpg');
    expect(recropped.originalPath, '/docs/recropped.jpg');
  });

  test('older stored pages without a raw photo remain readable', () {
    final old = ScanPage.fromJson({
      'id': 'legacy',
      'path': '/docs/legacy.jpg',
      'originalPath': '/docs/legacy.jpg',
    });
    expect(old.rawSourcePath, isNull);
    expect(old.originalPath, '/docs/legacy.jpg');
  });
}
