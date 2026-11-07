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
  static Future<File> createFile(
    ScanDocument document, {
    bool bengali = false,
  }) async {
    final texts = await recognizePageTexts(document, bengali: bengali);
    final bytes = buildDocxBytes(document.name, texts);
    final directory = await getTemporaryDirectory();
    final name = document.name.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
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
  }) async {
    if (document.pages.isEmpty) {
      throw const FormatException('This document has no pages.');
    }
    TextRecognizer? latinRecognizer;
    final texts = <String>[];
    try {
      for (final page in document.pages) {
        var text = page.recognizedText.trim();
        if (text.isEmpty) {
          if (bengali) {
            text = (await FlutterTesseractOcr.extractText(
              page.path,
              language: 'ben',
              args: const {'psm': '3', 'preserve_interword_spaces': '1'},
            )).trim();
          } else {
            latinRecognizer ??= TextRecognizer(script: TextRecognitionScript.latin);
            final result = await latinRecognizer.processImage(
              InputImage.fromFilePath(page.path),
            );
            text = result.text.trim();
          }
        }
        texts.add(text);
      }
    } finally {
      await latinRecognizer?.close();
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
  static Uint8List buildDocxBytes(String title, List<String> pageTexts) {
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
      '<w:rPr><w:sz w:val="22"/></w:rPr></w:style>'
      '<w:style w:type="paragraph" w:styleId="Title"><w:name w:val="Title"/>'
      '<w:basedOn w:val="Normal"/><w:rPr><w:b/><w:sz w:val="34"/></w:rPr></w:style>'
      '<w:style w:type="paragraph" w:styleId="Heading2"><w:name w:val="heading 2"/>'
      '<w:basedOn w:val="Normal"/><w:rPr><w:b/><w:sz w:val="28"/></w:rPr></w:style>'
      '</w:styles>'));
    archive.addFile(ArchiveFile.string('word/document.xml',
        _buildDocumentXml(title, pageTexts)));
    return ZipEncoder().encodeBytes(archive);
  }

  static String _buildDocumentXml(String title, List<String> pages) {
    final out = StringBuffer()
      ..write('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>')
      ..write('<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:body>')
      ..write(_paragraph(title, style: 'Title'));
    for (var page = 0; page < pages.length; page++) {
      out.write(_paragraph('Page ${page + 1}', style: 'Heading2'));
      if (pages[page].trim().isEmpty) {
        out.write(_paragraph('[No recognizable text on this page]'));
      } else {
        for (final line in pages[page].split(RegExp(r'\r?\n'))) {
          out.write(_paragraph(line));
        }
      }
      if (page != pages.length - 1) {
        out.write('<w:p><w:r><w:br w:type="page"/></w:r></w:p>');
      }
    }
    out.write('<w:sectPr><w:pgSz w:w="11906" w:h="16838"/>')
      ..write('<w:pgMar w:top="1100" w:right="1100" w:bottom="1100" w:left="1100"/></w:sectPr>')
      ..write('</w:body></w:document>');
    return out.toString();
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
