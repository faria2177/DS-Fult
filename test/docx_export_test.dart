import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:docscanner/src/models.dart';
import 'package:docscanner/src/services/docx_export.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Word export creates a valid ZIP with editable paragraphs', () {
    final bytes = DocxExport.buildDocxBytes('Example', [
      'First line\nSecond & <third>',
      'বাংলা লেখাও থাকবে',
    ]);
    final zip = ZipDecoder().decodeBytes(bytes, verify: true);
    expect(zip.findFile('[Content_Types].xml'), isNotNull);
    expect(zip.findFile('_rels/.rels'), isNotNull);
    expect(zip.findFile('word/styles.xml'), isNotNull);
    final document = zip.findFile('word/document.xml');
    expect(document, isNotNull);
    final xml = utf8.decode(document!.readBytes()!);
    expect(xml, contains('First line'));
    expect(xml, contains('Second &amp; &lt;third&gt;'));
    expect(xml, contains('বাংলা লেখাও থাকবে'));
    expect(xml, contains('<w:br w:type="page"/>'));
    expect(xml, endsWith('</w:body></w:document>'));
  });

  test('Word export removes invalid control characters safely', () {
    final bytes = DocxExport.buildDocxBytes('Title', ['A\u0000B\u0007C']);
    final zip = ZipDecoder().decodeBytes(bytes, verify: true);
    final xml = utf8.decode(zip.findFile('word/document.xml')!.readBytes()!);
    expect(xml, contains('ABC'));
    expect(xml, isNot(contains('\u0000')));
  });

  test('broken page file cannot discard cached recognized text', () async {
    final doc = ScanDocument(id: 'cached', name: 'Cached',
      createdAt: DateTime(2026, 11, 9), pages: const [
        ScanPage(id: 'a', path: '/not-real-page.jpg',
          originalPath: '/not-real-page.jpg',
          recognizedText: 'Cached text\t25'),
      ]);
    expect(await DocxExport.recognizePageTexts(doc, forceOcr: true),
      ['Cached text\t25']);
  });

  test('Word export persists preview font size and line spacing', () {
    final bytes = DocxExport.buildDocxBytes('Letter', ['Hello world'],
      fontSize: 18, lineSpacing: 1.85);
    final archive = ZipDecoder().decodeBytes(bytes, verify: true);
    final styles = utf8.decode(
      archive.findFile('word/styles.xml')!.readBytes()!);
    expect(styles, contains('<w:sz w:val="36"/>'));
    expect(styles, contains('<w:spacing w:line="444" w:lineRule="auto"/>'));
  });

  test('Word export preserves AI-reconstructed TSV as editable tables', () {
    final bytes = DocxExport.buildDocxBytes('Schedule', [
      'Tournament Groups\nGroup A\tGroup B\tGroup C\n'
      'Dhaka\tKhulna\tRajshahi\nNext paragraph',
    ]);
    final xml = utf8.decode(ZipDecoder().decodeBytes(bytes)
      .findFile('word/document.xml')!.readBytes()!);
    expect(xml, contains('<w:tbl>'));
    expect(xml, contains('<w:tblGrid>'));
    expect(xml, contains('<w:tr>'));
    expect(xml, contains('Group A'));
    expect(xml, contains('Khulna'));
    expect(xml.indexOf('Tournament Groups'), lessThan(xml.indexOf('<w:tbl>')));
    expect(xml.indexOf('</w:tbl>'), lessThan(xml.indexOf('Next paragraph')));
    expect(xml, isNot(contains('Page 1</w:t>')));
  });
}
