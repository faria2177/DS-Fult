import 'dart:typed_data';

import 'package:docscanner/src/models.dart';
import 'package:docscanner/src/screens/image_to_pdf_screen.dart';
import 'package:docscanner/src/services/pdf_file_delivery.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

final _source = ScanDocument(
  id: 'source', name: 'My Scan', createdAt: DateTime(2026, 11, 9),
  pages: const [
    ScanPage(id: 'one', path: '/not-found-1.jpg',
        originalPath: '/not-found-1.jpg'),
    ScanPage(id: 'two', path: '/not-found-2.jpg',
        originalPath: '/not-found-2.jpg'),
    ScanPage(id: 'three', path: '/not-found-3.jpg',
        originalPath: '/not-found-3.jpg'),
  ],
);

Uint8List get _fakePdf => Uint8List.fromList('%PDF-1.4 test'.codeUnits);

void main() {
  test('PDF filenames are safe and do not add a duplicate extension', () {
    expect(PdfFileDelivery.filenameFor('My Scan'), 'My Scan.pdf');
    expect(PdfFileDelivery.filenameFor('report.pdf'), 'report.pdf');
    expect(PdfFileDelivery.filenameFor('A/B:C'), 'A_B_C.pdf');
    expect(PdfFileDelivery.filenameFor(''), 'DocScanner.pdf');
  });

  testWidgets('Image to PDF saves reordered pages without editing the source',
      (tester) async {
    List<String>? exportedIds;
    String? savedFilename;
    await tester.pumpWidget(MaterialApp(home: ImageToPdfScreen(
      document: _source,
      pdfBuilder: (document) async {
        exportedIds = document.pages.map((page) => page.id).toList();
        return _fakePdf;
      },
      pdfSaver: (bytes, fileName) async {
        savedFilename = fileName;
        return true;
      },
    )));
    expect(find.text('3/3 selected'), findsOneWidget);
    await tester.tap(find.byTooltip('Move page 2 up'));
    await tester.pump();
    await tester.tap(find.byKey(const Key('image-pdf-save')));
    await tester.pump();
    expect(exportedIds, ['two', 'one', 'three']);
    expect(savedFilename, 'My Scan.pdf');
    expect(_source.pages.map((page) => page.id), ['one', 'two', 'three']);
    expect(find.text('My Scan.pdf saved to the selected folder'), findsOneWidget);
  });

  testWidgets('Image to PDF refuses empty selection; Share exports selected',
      (tester) async {
    List<String>? exportedIds;
    var shared = false;
    await tester.pumpWidget(MaterialApp(home: ImageToPdfScreen(
      document: _source,
      pdfBuilder: (document) async {
        exportedIds = document.pages.map((page) => page.id).toList();
        return _fakePdf;
      },
      pdfSharer: (bytes, fileName) async { shared = true; },
    )));
    await tester.tap(find.text('Deselect All'));
    await tester.pump();
    expect(find.text('0/3 selected'), findsOneWidget);
    expect(tester.widget<FilledButton>(
      find.byKey(const Key('image-pdf-save'))).onPressed, isNull);
    expect(tester.widget<OutlinedButton>(
      find.byKey(const Key('image-pdf-share'))).onPressed, isNull);
    await tester.tap(find.text('Select All'));
    await tester.pump();
    await tester.tap(find.byKey(const Key('image-pdf-include-one')));
    await tester.pump();
    expect(find.text('2/3 selected'), findsOneWidget);
    await tester.tap(find.byKey(const Key('image-pdf-share')));
    await tester.pump();
    expect(shared, isTrue);
    expect(exportedIds, ['two', 'three']);
  });

  testWidgets('cancelling Android Save As reports no saved PDF',
      (tester) async {
    await tester.pumpWidget(MaterialApp(home: ImageToPdfScreen(
      document: _source,
      pdfBuilder: (document) async => _fakePdf,
      pdfSaver: (bytes, fileName) async => false,
    )));
    await tester.tap(find.byKey(const Key('image-pdf-save')));
    await tester.pump();
    expect(find.textContaining('saved to the selected folder'), findsNothing);
    expect(_source.pages.length, 3);
  });
}
