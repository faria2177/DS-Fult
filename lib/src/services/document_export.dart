import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../models.dart';

class DocumentExport {
  static const MethodChannel _galleryChannel = MethodChannel('doclens/methods');

  /// Uses Android MediaStore through the bundled doclens native plugin.
  /// This writes actual gallery entries rather than merely opening Share.
  static Future<int> saveImagesToGallery(ScanDocument document) async {
    var saved = 0;
    for (final page in document.pages) {
      await saveImageFileToGallery(page.path);
      saved++;
    }
    return saved;
  }

  /// Used by tools that create a new image but have not yet saved a document.
  static Future<void> saveImageFileToGallery(String imagePath) async {
    final success = await _galleryChannel.invokeMethod<bool>(
        'saveImageToGallery', {'imagePath': imagePath});
    if (success != true) {
      throw StateError('Could not save image to Gallery. '
          'Android 10 or newer is required.');
    }
  }
  static Future<Uint8List> toPdf(
    ScanDocument document, {
    String? watermark,
    int? imageQuality,
  }) async {
    final pdf = pw.Document();
    pw.Widget decorate(pw.Widget content) {
      if (watermark == null || watermark.trim().isEmpty) return content;
      return pw.Stack(children: [
        content,
        pw.Center(child: pw.Text(
          watermark,
          style: pw.TextStyle(fontSize: 32, color: PdfColors.grey500),
        )),
      ]);
    }

    Future<pw.MemoryImage> readImage(ScanPage page) async {
      final original = await File(page.path).readAsBytes();
      if (imageQuality == null) return pw.MemoryImage(original);
      final compact = await compute(_compactImage, {
        'bytes': original,
        'quality': imageQuality,
      });
      return pw.MemoryImage(compact);
    }

    if (document.compositeCardPages) {
      // Every card sheet already contains the front/back composite. Support
      // additional A4 card sheets without accidentally re-combining them.
      for (final page in document.pages) {
        final image = await readImage(page);
        pdf.addPage(pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(0),
          build: (_) => decorate(pw.Center(
            child: pw.Image(image, fit: pw.BoxFit.contain),
          )),
        ));
      }
    } else if (document.kind.twoSided) {
      final pictures = <pw.MemoryImage>[];
      for (final page in document.pages.take(2)) {
        pictures.add(await readImage(page));
      }
      pdf.addPage(pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (_) => decorate(pw.Column(
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
        )),
      ));
    } else {
      for (final page in document.pages) {
        final image = await readImage(page);
        pdf.addPage(pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(16),
          build: (_) => decorate(pw.Center(
            child: pw.Image(image, fit: pw.BoxFit.contain),
          )),
        ));
      }
    }
    return pdf.save();
  }

  static Future<File> savePdf(
    ScanDocument document, {
    String? watermark,
    int? imageQuality,
  }) async {
    final dir = await getTemporaryDirectory();
    final name = document.name.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    final suffix = watermark == null && imageQuality == null ? '' : '_edited';
    final file = File(p.join(dir.path, '${name}_${document.id}$suffix.pdf'));
    await file.writeAsBytes(await toPdf(document,
        watermark: watermark, imageQuality: imageQuality), flush: true);
    return file;
  }

  static Future<void> sharePdf(ScanDocument document) async {
    final file = await savePdf(document);
    await SharePlus.instance.share(ShareParams(
      files: [XFile(file.path)],
      subject: document.name,
    ));
  }

  static Future<void> shareCustomizedPdf(
    ScanDocument document, {
    String? watermark,
    int? imageQuality,
  }) async {
    final file = await savePdf(document,
        watermark: watermark, imageQuality: imageQuality);
    await SharePlus.instance.share(ShareParams(
      files: [XFile(file.path, mimeType: 'application/pdf')],
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

Uint8List _compactImage(Map<String, Object> args) {
  final source = img.decodeImage(args['bytes']! as Uint8List);
  if (source == null) throw const FormatException('Unsupported page image');
  final image = img.bakeOrientation(source);
  final longest = image.width > image.height ? image.width : image.height;
  final resized = longest > 1700
      ? img.copyResize(
          image,
          width: image.width >= image.height ? 1700 : null,
          height: image.height > image.width ? 1700 : null,
          interpolation: img.Interpolation.average,
        )
      : image;
  return Uint8List.fromList(
      img.encodeJpg(resized, quality: args['quality']! as int));
}
