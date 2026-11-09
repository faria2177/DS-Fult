import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

import '../models.dart';

/// On-device image utilities for the image-backed document library.
class ImageToolOperations {
  @visibleForTesting
  static Uint8List buildLongImageBytes(List<Uint8List> pages,
      {bool watermark = false}) =>
      _joinVertical((pages: pages, watermark: watermark));

  static Future<Uint8List> createLongImage(ScanDocument document,
      {bool watermark = false}) async {
    if (document.pages.isEmpty) {
      throw const FormatException('This document has no images.');
    }
    final pages = <Uint8List>[];
    for (final page in document.pages) {
      pages.add(await File(page.path).readAsBytes());
    }
    return compute(_joinVertical, (pages: pages, watermark: watermark));
  }

  static Future<void> shareLongImage(ScanDocument document) async {
    final bytes = await createLongImage(document);
    final directory = await getTemporaryDirectory();
    final file = File(p.join(directory.path,
        'docscanner_long_${DateTime.now().microsecondsSinceEpoch}.jpg'));
    await file.writeAsBytes(bytes, flush: true);
    await SharePlus.instance.share(ShareParams(
      files: [XFile(file.path, mimeType: 'image/jpeg')],
      subject: '${document.name} - Long Image',
    ));
  }

  /// Splits a tall stitched image into readable A4 PDF pages, instead of
  /// squeezing the entire receipt/scan into one unreadable A4 thumbnail.
  @visibleForTesting
  static Future<Uint8List> longImagePdfBytes(Uint8List jpeg) async {
    final decoded = img.decodeImage(jpeg);
    if (decoded == null) throw const FormatException('Invalid long image');
    final upright = img.bakeOrientation(decoded);
    if (upright.width <= 0 || upright.height <= 0) {
      throw const FormatException('Empty long image');
    }
    const margin = 16.0;
    final maxHeight = (upright.width *
        (PdfPageFormat.a4.height - 2 * margin) /
        (PdfPageFormat.a4.width - 2 * margin)).floor();
    final pdf = pw.Document();
    for (var offset = 0; offset < upright.height; offset += maxHeight) {
      final height = math.min(maxHeight, upright.height - offset);
      final segment = img.copyCrop(upright,
          x: 0, y: offset, width: upright.width, height: height);
      final image = pw.MemoryImage(
          Uint8List.fromList(img.encodeJpg(segment, quality: 90)));
      pdf.addPage(pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(margin),
        build: (_) => pw.Center(
          child: pw.Image(image, fit: pw.BoxFit.contain),
        ),
      ));
    }
    return pdf.save();
  }

  /// A real two-column collage (distinct from vertical long-image export).
  static Future<void> shareCollage(ScanDocument document) async {
    if (document.pages.isEmpty) {
      throw const FormatException('This document has no images.');
    }
    final pages = <Uint8List>[];
    for (final page in document.pages) {
      pages.add(await File(page.path).readAsBytes());
    }
    final bytes = await compute(buildCollageBytes, pages);
    final directory = await getTemporaryDirectory();
    final file = File(p.join(directory.path,
        'docscanner_collage_${DateTime.now().microsecondsSinceEpoch}.jpg'));
    await file.writeAsBytes(bytes, flush: true);
    await SharePlus.instance.share(ShareParams(
      files: [XFile(file.path, mimeType: 'image/jpeg')],
      subject: '${document.name} - Collage',
    ));
  }

  @visibleForTesting
  static Uint8List buildCollageBytes(List<Uint8List> images) {
    if (images.isEmpty) throw const FormatException('No images for collage');
    const cellWidth = 540;
    const cellHeight = 760;
    const gap = 12;
    final columns = images.length == 1 ? 1 : 2;
    final rows = (images.length + columns - 1) ~/ columns;
    final canvas = img.Image(
      width: columns * cellWidth + (columns + 1) * gap,
      height: rows * cellHeight + (rows + 1) * gap,
    );
    img.fill(canvas, color: img.ColorRgb8(244, 244, 244));
    for (var i = 0; i < images.length; i++) {
      final source = img.decodeImage(images[i]);
      if (source == null) throw const FormatException('Unsupported image');
      final upright = img.bakeOrientation(source);
      final factor = math.min(cellWidth / upright.width, cellHeight / upright.height);
      final resized = img.copyResize(upright,
        width: math.max(1, (upright.width * factor).round()),
        height: math.max(1, (upright.height * factor).round()),
      );
      final column = i % columns;
      final row = i ~/ columns;
      final x = gap + column * (cellWidth + gap) + (cellWidth - resized.width) ~/ 2;
      final y = gap + row * (cellHeight + gap) + (cellHeight - resized.height) ~/ 2;
      img.compositeImage(canvas, resized, dstX: x, dstY: y);
    }
    return Uint8List.fromList(img.encodeJpg(canvas, quality: 88));
  }

  static Future<void> shareResizedImage(String path, int maxDimension) async {
    final bytes = await File(path).readAsBytes();
    final resized = await compute(_resize, {
      'bytes': bytes,
      'maxDimension': maxDimension,
    });
    final directory = await getTemporaryDirectory();
    final file = File(p.join(directory.path,
        'docscanner_resized_${DateTime.now().microsecondsSinceEpoch}.jpg'));
    await file.writeAsBytes(resized, flush: true);
    await SharePlus.instance.share(ShareParams(
      files: [XFile(file.path, mimeType: 'image/jpeg')],
      subject: 'Resized image',
    ));
  }
}

Uint8List _resize(Map<String, Object> options) {
  final source = img.decodeImage(options['bytes']! as Uint8List);
  if (source == null) throw const FormatException('Unsupported image format');
  final image = img.bakeOrientation(source);
  final longest = math.max(image.width, image.height);
  final bound = (options['maxDimension']! as int).clamp(320, 4096).toInt();
  final resized = longest <= bound ? image : img.copyResize(
    image,
    width: image.width >= image.height ? bound : null,
    height: image.height > image.width ? bound : null,
    interpolation: img.Interpolation.average,
  );
  return Uint8List.fromList(img.encodeJpg(resized, quality: 88));
}

Uint8List _joinVertical(({List<Uint8List> pages, bool watermark}) options) {
  if (options.pages.isEmpty) {
    throw const FormatException('Select at least one page.');
  }
  final pages = <img.Image>[];
  var totalHeight = 0;
  const width = 1100;
  final footer = options.watermark ? 56 : 0;
  for (final data in options.pages) {
    final decoded = img.decodeImage(data);
    if (decoded == null) throw const FormatException('Unsupported page image');
    final upright = img.bakeOrientation(decoded);
    // Never clamp a single page's height: that distorts its aspect ratio and
    // can turn a very tall receipt into an unreadable, compressed image.
    final height = math.max(1, (upright.height * width / upright.width).round());
    totalHeight += height;
    // Avoid an OOM on long multi-page scans; the user can split the document.
    if (totalHeight + footer > 15500 ||
        (totalHeight + footer) * width > 18 * 1000 * 1000) {
      throw const FormatException('Long image exceeds 15,500 pixels in height. '
          'Please split the document into smaller groups.');
    }
    pages.add(img.copyResize(upright, width: width,
        height: height, interpolation: img.Interpolation.average));
  }
  final combined = img.Image(width: width, height: totalHeight + footer);
  img.fill(combined, color: img.ColorRgb8(255, 255, 255));
  var offset = 0;
  for (final page in pages) {
    img.compositeImage(combined, page, dstY: offset);
    offset += page.height;
  }
  if (options.watermark) {
    const label = 'DocScanner';
    img.drawString(combined, label, font: img.arial24,
      x: (width - label.length * 14) ~/ 2,
      y: totalHeight + 12,
      color: img.ColorRgb8(120, 120, 120));
  }
  return Uint8List.fromList(img.encodeJpg(combined, quality: 86));
}
