import 'dart:io';
import 'dart:typed_data';

import 'package:docscanner/src/models.dart';
import 'package:docscanner/src/services/document_export.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('PDF is valid with compressed image and text watermark', () async {
    final temp = await Directory.systemTemp.createTemp('docscanner_pdf_test_');
    try {
      final image = img.Image(width: 120, height: 180);
      img.fill(image, color: img.ColorRgb8(245, 245, 245));
      final file = File('${temp.path}/sample.jpg');
      await file.writeAsBytes(img.encodeJpg(image));

      final document = ScanDocument(
        id: 'pdf-test',
        name: 'PDF test',
        createdAt: DateTime(2026, 11, 6),
        pages: [ScanPage(id: 'p1', path: file.path, originalPath: file.path)],
      );
      final bytes = await DocumentExport.toPdf(document,
          imageQuality: 55, watermark: 'DS');
      expect(bytes, isA<Uint8List>());
      expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
      expect(bytes.length, greaterThan(500));
    } finally {
      await temp.delete(recursive: true);
    }
  });
}
