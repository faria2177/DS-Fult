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
class XlsxExport {
  static Future<File> createFile(
    ScanDocument document, {
    bool bengali = false,
  }) async {
    final texts = await DocxExport.recognizePageTexts(document, bengali: bengali);
    final bytes = buildXlsxBytes(texts);
    final directory = await getTemporaryDirectory();
    final name = document.name.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
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

  static Uint8List buildXlsxBytes(List<String> pageTexts) {
    if (pageTexts.isEmpty) {
      throw const FormatException('At least one page is required.');
    }
    final archive = Archive();
    final types = StringBuffer()
      ..write('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>')
      ..write('<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">')
      ..write('<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>')
      ..write('<Default Extension="xml" ContentType="application/xml"/>')
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
          _sheetXml(pageTexts[i])));
    }
    workbook.write('</sheets></workbook>');
    relations.write('</Relationships>');
    archive.addFile(ArchiveFile.string('xl/workbook.xml', workbook.toString()));
    archive.addFile(ArchiveFile.string('xl/_rels/workbook.xml.rels',
        relations.toString()));
    return ZipEncoder().encodeBytes(archive);
  }

  static String _sheetXml(String contents) {
    final out = StringBuffer()
      ..write('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>')
      ..write('<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetData>');
    final lines = contents.isEmpty ? [''] : contents.split(RegExp(r'\r?\n'));
    for (var y = 0; y < lines.length; y++) {
      final rowNumber = y + 1;
      out.write('<row r="$rowNumber">');
      final line = lines[y];
      final cells = line.contains('\t')
          ? line.split('\t')
          : line.split(RegExp(r' {2,}'));
      for (var x = 0; x < cells.length; x++) {
        final reference = '${_columnLetters(x)}$rowNumber';
        out.write('<c r="$reference" t="inlineStr"><is><t xml:space="preserve">'
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
