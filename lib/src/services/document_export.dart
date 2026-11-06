import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../models.dart';

class DocumentExport {
  static Future<Uint8List> toPdf(ScanDocument document) async {
    final pdf = pw.Document();
    if (document.kind.twoSided) {
      final pictures = <pw.MemoryImage>[];
      for (final page in document.pages.take(2)) {
        pictures.add(pw.MemoryImage(await File(page.path).readAsBytes()));
      }
      pdf.addPage(pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (_) => pw.Column(
          mainAxisAlignment: pw.MainAxisAlignment.center,
          children: [
            for (var i = 0; i < pictures.length; i++) ...[
              pw.SizedBox(
                height: 168,
                width: 390,
                child: pw.Image(pictures[i], fit: pw.BoxFit.contain),
              ),
              if (i == 0) pw.SizedBox(height: 58),
            ],
          ],
        ),
      ));
    } else {
      for (final page in document.pages) {
        final bytes = await File(page.path).readAsBytes();
        pdf.addPage(pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(16),
          build: (_) => pw.Center(
            child: pw.Image(pw.MemoryImage(bytes), fit: pw.BoxFit.contain),
          ),
        ));
      }
    }
    return pdf.save();
  }

  static Future<File> savePdf(ScanDocument document) async {
    final dir = await getTemporaryDirectory();
    final name = document.name.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    final file = File(p.join(dir.path, '${name}_${document.id}.pdf'));
    await file.writeAsBytes(await toPdf(document), flush: true);
    return file;
  }

  static Future<void> sharePdf(ScanDocument document) async {
    final file = await savePdf(document);
    await SharePlus.instance.share(ShareParams(
      files: [XFile(file.path)],
      subject: document.name,
    ));
  }

  static Future<void> printPdf(ScanDocument document) async {
    final bytes = await toPdf(document);
    await Printing.layoutPdf(name: document.name, onLayout: (_) async => bytes);
  }

  static Future<void> shareImages(ScanDocument document) async {
    await SharePlus.instance.share(ShareParams(
      files: [for (final page in document.pages) XFile(page.path)],
      subject: document.name,
    ));
  }

  static Future<void> shareText(String text, String name) async {
    final dir = await getTemporaryDirectory();
    final file = File(p.join(dir.path, 'docscanner_text.txt'));
    await file.writeAsString(text, flush: true);
    await SharePlus.instance.share(ShareParams(
      files: [XFile(file.path, mimeType: 'text/plain')],
      subject: name,
    ));
  }

  static void reportError(Object error) => debugPrint('Export error: $error');
}
