import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models.dart';
import 'docx_export.dart';

/// Creates genuine editable Excel OpenXML spreadsheets from recognized text.
/// Columns are inferred only from tabs or repeated spaces; OCR table structure
/// cannot be reconstructed with complete fidelity from a plain transcript.
class XlsxLayout {
  const XlsxLayout({this.fontSize = 11, this.columnWidth = 16,
    this.rowHeight = 24, this.boldFirstRow = false});

  final double fontSize;
  final double columnWidth;
  final double rowHeight;
  final bool boldFirstRow;
}

class XlsxExport {
  /// Matches the actual XLSX cell-splitting rules so the preview can show
  /// the same columns the exported workbook will contain.
  static List<String> cellsFromLine(String line) => line.contains('\t')
      ? line.split('\t') : line.split(RegExp(r' {2,}'));

  static Future<File> createFile(
    ScanDocument document, {
    bool bengali = false,
  }) async {
    final texts = await DocxExport.recognizePageTexts(document, bengali: bengali);
    return createFromPageTexts(document.name, texts);
  }

  /// Export manually corrected OCR cells; do not silently re-recognize them.
  static Future<File> createFromPageTexts(
      String title, List<String> pageTexts, {XlsxLayout layout = const XlsxLayout()}) async {
    if (pageTexts.isEmpty ||
        pageTexts.every((page) => page.trim().isEmpty)) {
      throw const FormatException('No table data to export.');
    }
    final bytes = buildXlsxBytes(pageTexts, layout: layout);
    final directory = await getTemporaryDirectory();
    final name = title.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    final file = File(p.join(directory.path,
        '${name}_${DateTime.now().microsecondsSinceEpoch}.xlsx'));
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  static Future<void> shareFile(File file, String name) async {
    await SharePlus.instance.share(ShareParams(
      files: [XFile(file.path, mimeType:
          'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet')],
      subject: name,
    ));
  }

  static Uint8List buildXlsxBytes(List<String> pageTexts,
      {XlsxLayout layout = const XlsxLayout()}) {
    if (pageTexts.isEmpty) {
      throw const FormatException('At least one page is required.');
    }
    final archive = Archive();
    final types = StringBuffer()
      ..write('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>')
      ..write('<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">')
      ..write('<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>')
      ..write('<Default Extension="xml" ContentType="application/xml"/>')
      ..write('<Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>')
      ..write('<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>');
    for (var i = 0; i < pageTexts.length; i++) {
      types.write('<Override PartName="/xl/worksheets/sheet${i + 1}.xml" '
          'ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>');
    }
    types.write('</Types>');
    archive.addFile(ArchiveFile.string('[Content_Types].xml', types.toString()));
    archive.addFile(ArchiveFile.string('_rels/.rels',
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
      '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>'
      '</Relationships>'));
    final workbook = StringBuffer()
      ..write('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>')
      ..write('<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" '
          'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets>');
    final relations = StringBuffer()
      ..write('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>')
      ..write('<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">');
    for (var i = 0; i < pageTexts.length; i++) {
      final n = i + 1;
      workbook.write('<sheet name="Page $n" sheetId="$n" r:id="rId$n"/>');
      relations.write('<Relationship Id="rId$n" '
          'Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" '
          'Target="worksheets/sheet$n.xml"/>');
      archive.addFile(ArchiveFile.string('xl/worksheets/sheet$n.xml',
          _sheetXml(pageTexts[i], layout)));
    }
    workbook.write('</sheets></workbook>');
    relations.write('<Relationship Id="rId${pageTexts.length + 1}" '
        'Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" '
        'Target="styles.xml"/></Relationships>');
    archive.addFile(ArchiveFile.string('xl/workbook.xml', workbook.toString()));
    archive.addFile(ArchiveFile.string('xl/_rels/workbook.xml.rels',
        relations.toString()));
    archive.addFile(ArchiveFile.string('xl/styles.xml', _stylesXml(layout)));
    return ZipEncoder().encodeBytes(archive);
  }

  static String _stylesXml(XlsxLayout layout) =>
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
      '<fonts count="2"><font><sz val="${layout.fontSize}"/><name val="Calibri"/></font>'
      '<font><b/><sz val="${layout.fontSize}"/><name val="Calibri"/></font></fonts>'
      '<fills count="2"><fill><patternFill patternType="none"/></fill>'
      '<fill><patternFill patternType="gray125"/></fill></fills>'
      '<borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders>'
      '<cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>'
      '<cellXfs count="2"><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>'
      '<xf numFmtId="0" fontId="1" fillId="0" borderId="0" xfId="0"/></cellXfs>'
      '</styleSheet>';

  static String _sheetXml(String contents, XlsxLayout layout) {
    final out = StringBuffer()
      ..write('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>')
      ..write('<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">')
      ..write('<cols><col min="1" max="16384" width="${layout.columnWidth}" customWidth="1"/></cols>')
      ..write('<sheetData>');
    final lines = contents.isEmpty ? [''] : contents.split(RegExp(r'\r?\n'));
    for (var y = 0; y < lines.length; y++) {
      final rowNumber = y + 1;
      out.write('<row r="$rowNumber" ht="${layout.rowHeight}" customHeight="1">');
      final line = lines[y];
      final cells = cellsFromLine(line);
      for (var x = 0; x < cells.length; x++) {
        final reference = '${_columnLetters(x)}$rowNumber';
        final style = layout.boldFirstRow && y == 0 ? ' s="1"' : '';
        out.write('<c r="$reference" t="inlineStr"$style><is><t xml:space="preserve">'
            '${_xmlEscape(cells[x])}</t></is></c>');
      }
      out.write('</row>');
    }
    out.write('</sheetData></worksheet>');
    return out.toString();
  }

  static String _columnLetters(int index) {
    var current = index + 1;
    var text = '';
    while (current > 0) {
      current--;
      text = String.fromCharCode(65 + current % 26) + text;
      current ~/= 26;
    }
    return text;
  }

  static String _xmlEscape(String text) => text
      .replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F]'), '')
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&apos;');
}
