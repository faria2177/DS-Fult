import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:docscanner/src/services/xlsx_export.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Excel export has a worksheet for each page and editable cells', () {
    final bytes = XlsxExport.buildXlsxBytes([
      'Account\tAmount\n9060012345\t15000',
      'Name  City\nJahid  Dhaka',
    ]);
    final archive = ZipDecoder().decodeBytes(bytes, verify: true);
    final workbook = utf8.decode(archive.findFile('xl/workbook.xml')!.readBytes()!);
    final sheet1 = utf8.decode(archive.findFile('xl/worksheets/sheet1.xml')!.readBytes()!);
    final sheet2 = utf8.decode(archive.findFile('xl/worksheets/sheet2.xml')!.readBytes()!);

    expect(workbook, contains('name="Page 1"'));
    expect(workbook, contains('name="Page 2"'));
    expect(sheet1, contains('<c r="A2" t="inlineStr">'));
    expect(sheet1, contains('9060012345'));
    expect(sheet1, contains('<c r="B2" t="inlineStr">'));
    expect(sheet2, contains('Dhaka'));
  });

  test('Excel export escapes special characters and keeps Bengali text', () {
    final zip = ZipDecoder().decodeBytes(
      XlsxExport.buildXlsxBytes(['বাংলা\tA&B\n<cell>\tYes']),
      verify: true,
    );
    final xml = utf8.decode(zip.findFile('xl/worksheets/sheet1.xml')!.readBytes()!);
    expect(xml, contains('বাংলা'));
    expect(xml, contains('A&amp;B'));
    expect(xml, contains('&lt;cell&gt;'));
  });

  test('Excel export uses the review screen font, dimensions and header style', () {
    final zip = ZipDecoder().decodeBytes(XlsxExport.buildXlsxBytes([
      'Item\tValue\nTeam A\t125',
    ], layout: const XlsxLayout(fontSize: 14, columnWidth: 22,
      rowHeight: 38, boldFirstRow: true)), verify: true);
    final sheet = utf8.decode(
        zip.findFile('xl/worksheets/sheet1.xml')!.readBytes()!);
    final styles = utf8.decode(zip.findFile('xl/styles.xml')!.readBytes()!);
    final relations = utf8.decode(
        zip.findFile('xl/_rels/workbook.xml.rels')!.readBytes()!);
    expect(sheet, contains('width="22.0"'));
    expect(sheet, contains('ht="38.0"'));
    expect(sheet, contains('s="1"><is>'));
    expect(styles, contains('<b/>'));
    expect(styles, contains('val="14.0"'));
    expect(relations, contains('Target="styles.xml"'));
  });
}
