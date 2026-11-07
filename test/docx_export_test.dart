import 'dart:convert';

import 'package:archive/archive.dart';
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
    final xml = utf8.decode(document!.readBytes());
    expect(xml, contains('First line'));
    expect(xml, contains('Second &amp; &lt;third&gt;'));
    expect(xml, contains('বাংলা লেখাও থাকবে'));
    expect(xml, contains('<w:br w:type="page"/>'));
    expect(xml, endsWith('</w:body></w:document>'));
  });

  test('Word export removes invalid control characters safely', () {
    final bytes = DocxExport.buildDocxBytes('Title', ['A\u0000B\u0007C']);
    final zip = ZipDecoder().decodeBytes(bytes, verify: true);
    final xml = utf8.decode(zip.findFile('word/document.xml')!.readBytes());
    expect(xml, contains('ABC'));
    expect(xml, isNot(contains('\u0000')));
  });
}
