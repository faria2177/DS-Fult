import 'dart:typed_data';

import 'package:docscanner/src/models.dart';
import 'package:docscanner/src/screens/long_image_studio_screen.dart';
import 'package:docscanner/src/storage/document_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void main() {
  testWidgets('long image shows preview, watermark and distinct export actions',
      (tester) async {
    final image = img.Image(width: 30, height: 60);
    img.fill(image, color: img.ColorRgb8(220, 220, 220));
    final bytes = Uint8List.fromList(img.encodeJpg(image));
    final watermarkSettings = <bool>[];
    final document = ScanDocument(
      id: 'doc-1', name: 'Sample Scan', createdAt: DateTime(2026, 11, 9),
      pages: const [
        ScanPage(id: 'one', path: '/sample1.jpg', originalPath: '/sample1.jpg'),
        ScanPage(id: 'two', path: '/sample2.jpg', originalPath: '/sample2.jpg'),
      ],
    );
    await tester.pumpWidget(MaterialApp(home: LongImageStudioScreen(
      document: document, store: DocumentStore(),
      builder: (_, watermark) async {
        watermarkSettings.add(watermark);
        return bytes;
      },
    )));
    await tester.pumpAndSettle();

    expect(find.text('PDF to Long Image'), findsOneWidget);
    expect(find.byKey(const Key('long-image-preview')), findsOneWidget);
    expect(find.text('Save as New'), findsOneWidget);
    expect(find.text('Share Image'), findsOneWidget);
    expect(find.text('Share as PDF'), findsOneWidget);
    expect(find.text('Share as Images'), findsOneWidget);
    expect(find.text('Save to Gallery'), findsOneWidget);
    expect(watermarkSettings, [false]);

    await tester.tap(find.text('Add DocScanner watermark'));
    await tester.pumpAndSettle();
    expect(watermarkSettings, [false, true]);
    expect(find.byKey(const Key('long-image-preview')), findsOneWidget);
  });
}
