import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_tesseract_ocr/flutter_tesseract_ocr.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models.dart';

/// Generates a standard, editable OpenXML Word document from scanned-page OCR.
/// The document contents are processed locally, never uploaded to a service.
class DocxExport {
  /// Export text edited in Extract Text without silently running OCR again or
  /// discarding the user's corrections.
  static Future<File> createFromText(String title, String text) async {
    if (text.trim().isEmpty) {
      throw const FormatException('There is no text to export.');
    }
    final bytes = buildDocxBytes(title, [text]);
    final directory = await getTemporaryDirectory();
    final safeTitle = title.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    final file = File(p.join(directory.path,
        '${safeTitle}_${DateTime.now().microsecondsSinceEpoch}.docx'));
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  static Future<File> createFile(
    ScanDocument document, {
    bool bengali = false,
  }) async {
    final texts = await recognizePageTexts(document, bengali: bengali);
    return createFromPageTexts(document.name, texts);
  }

  /// Export the user's reviewed OCR pages without another OCR pass.
  static Future<File> createFromPageTexts(
      String title, List<String> pageTexts, {
      double fontSize = 11,
      double lineSpacing = 1.2,
      }) async {
    if (pageTexts.isEmpty ||
        pageTexts.every((page) => page.trim().isEmpty)) {
      throw const FormatException('No text to export.');
    }
    final bytes = buildDocxBytes(title, pageTexts,
      fontSize: fontSize, lineSpacing: lineSpacing);
    final directory = await getTemporaryDirectory();
    final name = title.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    final path = p.join(directory.path,
        '${name}_${DateTime.now().microsecondsSinceEpoch}.docx');
    final file = File(path);
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  /// Reused by Excel export so both formats use exactly the same offline OCR.
  static Future<List<String>> recognizePageTexts(
    ScanDocument document, {
    bool bengali = false,
    bool forceOcr = false,
  }) async {
    if (document.pages.isEmpty) {
      throw const FormatException('This document has no pages.');
    }
    TextRecognizer? latinRecognizer;
    final texts = <String>[];
    try {
      for (final page in document.pages) {
        final cached = page.recognizedText.trim();
        var text = cached;
        if (text.isEmpty || forceOcr) {
          if (!await File(page.path).exists()) {
            if (cached.isEmpty) {
              throw const FormatException('The selected page image is missing.');
            }
            texts.add(cached);
            continue;
          }
          try {
            if (bengali) {
              text = (await FlutterTesseractOcr.extractText(page.path,
                language: 'ben+eng',
                args: const {'psm': '3', 'preserve_interword_spaces': '1'},
              )).trim();
            } else {
              // Some Android releases fail while initializing ML Kit. Retry
              // with the bundled English Tesseract model, without a network
              // call or leaking the platform stack trace to the UI.
              try {
                latinRecognizer ??= TextRecognizer(
                  script: TextRecognitionScript.latin);
                final result = await latinRecognizer.processImage(
                  InputImage.fromFilePath(page.path));
                text = result.text.trim();
              } catch (_) {
                text = (await FlutterTesseractOcr.extractText(page.path,
                  language: 'eng',
                  args: const {'psm': '3', 'preserve_interword_spaces': '1'},
                )).trim();
              }
            }
          } catch (_) {
            if (cached.isEmpty) {
              throw const FormatException('On-device OCR failed on this page. '
                'Retry with AI vision or import a clearer scan.');
            }
            text = cached;
          }
          if (text.isEmpty) text = cached;
        }
        texts.add(text);
      }
    } finally {
      try {
        await latinRecognizer?.close();
      } catch (_) {
        // A broken native ML Kit session must not erase the successful
        // Tesseract fallback or an already recognized page.
      }
    }
    if (texts.every((page) => page.isEmpty)) {
      throw const FormatException('No text could be recognized. '
          'Open Extract Text, check the scan, then try again.');
    }
    return texts;
  }

  static Future<void> shareFile(File file, String name) async {
    await SharePlus.instance.share(ShareParams(
        files: [XFile(file.path, mimeType:
            'application/vnd.openxmlformats-officedocument.wordprocessingml.document')],
        subject: name,
      ));
  }

  /// Pure conversion is independently unit-testable without ML Kit or Tesseract.
  static Uint8List buildDocxBytes(String title, List<String> pageTexts, {
    double fontSize = 11,
    double lineSpacing = 1.2,
  }) {
    final sizeHalfPoints = (fontSize.clamp(8.0, 32.0) * 2).round();
    final lineTwips = (lineSpacing.clamp(1.0, 2.5) * 240).round();
    final archive = Archive();
    archive.addFile(ArchiveFile.string('[Content_Types].xml',
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
      '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
      '<Default Extension="xml" ContentType="application/xml"/>'
      '<Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>'
      '<Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/>'
      '</Types>'));
    archive.addFile(ArchiveFile.string('_rels/.rels',
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
      '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>'
      '</Relationships>'));
    archive.addFile(ArchiveFile.string('word/_rels/document.xml.rels',
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
      '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>'
      '</Relationships>'));
    archive.addFile(ArchiveFile.string('word/styles.xml',
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<w:styles xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">'
      '<w:style w:type="paragraph" w:default="1" w:styleId="Normal"><w:name w:val="Normal"/>'
      '<w:pPr><w:spacing w:line="$lineTwips" w:lineRule="auto"/></w:pPr>'
      '<w:rPr><w:sz w:val="$sizeHalfPoints"/></w:rPr></w:style>'
      '<w:style w:type="paragraph" w:styleId="Title"><w:name w:val="Title"/>'
      '<w:basedOn w:val="Normal"/><w:rPr><w:b/><w:sz w:val="34"/></w:rPr></w:style>'
      '<w:style w:type="paragraph" w:styleId="Heading2"><w:name w:val="heading 2"/>'
      '<w:basedOn w:val="Normal"/><w:rPr><w:b/><w:sz w:val="28"/></w:rPr></w:style>'
      '</w:styles>'));
    archive.addFile(ArchiveFile.string('word/document.xml',
        _buildDocumentXml(pageTexts)));
    return ZipEncoder().encodeBytes(archive);
  }

  static String _buildDocumentXml(List<String> pages) {
    final out = StringBuffer()
      ..write('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>')
      ..write('<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:body>');
    for (var page = 0; page < pages.length; page++) {
      if (pages[page].trim().isEmpty) {
        out.write(_paragraph('[No recognizable text on this page]'));
      } else {
        // The AI vision path produces TSV for tabular regions. Render those
        // rows as real, editable Word tables instead of flat lines of text.
        // Ordinary OCR paragraphs keep their original order and line breaks.
        final lines = pages[page].split(RegExp(r'\r?\n'));
        for (var index = 0; index < lines.length;) {
          if (!lines[index].contains('\t')) {
            out.write(_paragraph(lines[index++]));
            continue;
          }
          final rows = <List<String>>[];
          while (index < lines.length && lines[index].contains('\t')) {
            rows.add(lines[index++].split('\t'));
          }
          out.write(_table(rows));
        }
      }
      if (page != pages.length - 1) {
        out.write('<w:p><w:r><w:br w:type="page"/></w:r></w:p>');
      }
    }
    out..write('<w:sectPr><w:pgSz w:w="11906" w:h="16838"/>')
      ..write('<w:pgMar w:top="1100" w:right="1100" w:bottom="1100" w:left="1100"/></w:sectPr>')
      ..write('</w:body></w:document>');
    return out.toString();
  }

  static String _table(List<List<String>> rows) {
    final columns = rows.fold<int>(2, (count, row) =>
      row.length > count ? row.length : count).clamp(2, 16).toInt();
    const availableWidth = 9706;
    final cellWidth = availableWidth ~/ columns;
    final out = StringBuffer()
      ..write('<w:tbl><w:tblPr><w:tblW w:w="9706" w:type="dxa"/>')
      ..write('<w:tblBorders>');
    for (final edge in ['top', 'left', 'bottom', 'right', 'insideH', 'insideV']) {
      out.write('<w:$edge w:val="single" w:sz="4" w:color="888888"/>');
    }
    out.write('</w:tblBorders></w:tblPr><w:tblGrid>');
    for (var col = 0; col < columns; col++) {
      out.write('<w:gridCol w:w="$cellWidth"/>');
    }
    out.write('</w:tblGrid>');
    for (final row in rows) {
      out.write('<w:tr>');
      for (var col = 0; col < columns; col++) {
        final cell = col < row.length ? row[col] : '';
        out.write('<w:tc><w:tcPr><w:tcW w:w="$cellWidth" w:type="dxa"/>');
        out.write('</w:tcPr>${_paragraph(cell)}</w:tc>');
      }
      out.write('</w:tr>');
    }
    return (out..write('</w:tbl>')).toString();
  }

  static String _paragraph(String text, {String? style}) {
    final clean = _xmlEscape(text);
    final paragraphStyle = style == null ? ''
        : '<w:pPr><w:pStyle w:val="$style"/></w:pPr>';
    return '<w:p>$paragraphStyle<w:r><w:t xml:space="preserve">$clean</w:t></w:r></w:p>';
  }

  static String _xmlEscape(String text) => text
      .replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F]'), '')
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&apos;');
}
