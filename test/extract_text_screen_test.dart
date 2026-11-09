import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:docscanner/src/models.dart';
import 'package:docscanner/src/screens/extract_text_screen.dart';
import 'package:docscanner/src/services/docx_export.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

final _document = ScanDocument(
  id: 'source',
  name: 'Letter',
  createdAt: _date,
  pages: const [ScanPage(id: 'page1', path: '/not-a-real-image.jpg',
      originalPath: '/not-a-real-image.jpg')],
);

final _date = DateTime(2026, 11, 9);

void main() {
  testWidgets('Extract Text opens OCR results directly and permits editing',
      (tester) async {
    final languages = <bool>[];
    await tester.pumpWidget(MaterialApp(home: ExtractTextScreen(
      document: _document,
      recognizer: (_, bengali) async {
        languages.add(bengali);
        return [bengali ? 'বাংলা লেখা' : 'Recognized line'];
      },
    )));
    await tester.pumpAndSettle();

    final field = find.byKey(const Key('extracted-text'));
    expect(tester.widget<TextField>(field).controller!.text,
        'Recognized line');
    expect(find.text('Copy'), findsOneWidget);
    expect(find.text('Select All'), findsOneWidget);
    expect(find.text('To Word'), findsOneWidget);
    expect(find.text('Share Text'), findsOneWidget);

    await tester.enterText(field, 'Corrected text & more');
    await tester.tap(find.text('Select All'));
    await tester.pump();
    final controller = tester.widget<TextField>(field).controller!;
    expect(controller.selection.baseOffset, 0);
    expect(controller.selection.extentOffset, controller.text.length);

    await tester.tap(find.text('বাংলা / Bengali'));
    await tester.pumpAndSettle();
    expect(languages, [false, true]);
    expect(controller.text, 'বাংলা লেখা');
  });

  testWidgets('failed re-recognition retains user-edited text', (tester) async {
    var count = 0;
    await tester.pumpWidget(MaterialApp(home: ExtractTextScreen(
      document: _document,
      recognizer: (_, _) async {
        if (count++ > 0) throw const FormatException('OCR unavailable');
        return ['First result'];
      },
    )));
    await tester.pumpAndSettle();
    final field = find.byKey(const Key('extracted-text'));
    await tester.enterText(field, 'Edits are valuable');
    await tester.tap(find.byTooltip('Recognize again'));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(field).controller!.text,
        'Edits are valuable');
    expect(find.textContaining('OCR could not finish'), findsOneWidget);
  });

  test('Extract Text Word export encodes corrected Bengali/Latin text', () {
    final bytes = DocxExport.buildDocxBytes('Letter',
        ['Edited & checked\nবাংলা লেখা']);
    final archive = ZipDecoder().decodeBytes(bytes, verify: true);
    final xml = utf8.decode(
        archive.findFile('word/document.xml')!.readBytes()!);
    expect(xml, contains('Edited &amp; checked'));
    expect(xml, contains('বাংলা লেখা'));
  });
}
