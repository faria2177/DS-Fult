import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// A visible, offline PDF fallback for OCR text with Bengali and other
/// non-Latin characters. Flutter performs full native text shaping before a
/// page image is embedded into PDF. This PDF is legible but image-based;
/// users wanting selectable Unicode text should export the editable DOCX.
abstract final class UnicodeTextPdfExport {
  static const _width = 1190;
  static const _height = 1684;
  static const _margin = 88.0;

  static Future<File> create(String title, List<String> pageTexts,
      {double fontSize = 15, double lineSpacing = 1.4}) async {
    final bytes = await build(pageTexts, fontSize: fontSize,
      lineSpacing: lineSpacing);
    final directory = await getTemporaryDirectory();
    final safe = title.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    final file = File(p.join(directory.path,
      '${safe}_${DateTime.now().microsecondsSinceEpoch}.pdf'));
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  static Future<Uint8List> build(List<String> pageTexts,
      {double fontSize = 15, double lineSpacing = 1.4}) async {
    if (pageTexts.isEmpty || pageTexts.every((text) => text.trim().isEmpty)) {
      throw const FormatException('There is no text to export.');
    }
    final document = pw.Document();
    final maxHeight = _height - _margin * 2;
    var count = 0;
    for (final text in pageTexts) {
      final painter = TextPainter(
        text: TextSpan(text: text, style: TextStyle(
          color: Colors.black, fontSize: fontSize * 1.85,
          height: lineSpacing, fontWeight: FontWeight.normal)),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: _width - _margin * 2);
      try {
        final slices = math.max(1, (painter.height / maxHeight).ceil());
        if (count + slices > 60) {
          throw const FormatException('Too much text for a PDF preview. '
            'Use Share as Word for this document.');
        }
        for (var section = 0; section < slices; section++) {
          final recorder = ui.PictureRecorder();
          final canvas = ui.Canvas(recorder);
          canvas.drawColor(Colors.white, ui.BlendMode.src);
          canvas.save();
          canvas.clipRect(ui.Rect.fromLTWH(_margin, _margin,
            _width - 2 * _margin, maxHeight));
          painter.paint(canvas, ui.Offset(_margin,
            _margin - section * maxHeight));
          canvas.restore();
          final rendered = await recorder.endRecording().toImage(_width, _height);
          final data = await rendered.toByteData(format: ui.ImageByteFormat.png);
          rendered.dispose();
          if (data == null) throw const FormatException('PDF rendering failed.');
          final image = pw.MemoryImage(data.buffer.asUint8List());
          document.addPage(pw.Page(pageFormat: PdfPageFormat.a4,
            margin: const pw.EdgeInsets.all(0),
            build: (_) => pw.Image(image, fit: pw.BoxFit.fill)));
          count++;
        }
      } finally {
        painter.dispose();
      }
    }
    return document.save();
  }
}
