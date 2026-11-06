import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models.dart';

/// On-device image utilities for the image-backed document library.
class ImageToolOperations {
  @visibleForTesting
  static Uint8List buildLongImageBytes(List<Uint8List> pages) =>
      _joinVertical(pages);

  static Future<void> shareLongImage(ScanDocument document) async {
    if (document.pages.isEmpty) {
      throw const FormatException('This document has no images.');
    }
    final pages = <Uint8List>[];
    for (final page in document.pages) {
      pages.add(await File(page.path).readAsBytes());
    }
    final bytes = await compute(_joinVertical, pages);
    final directory = await getTemporaryDirectory();
    final file = File(p.join(directory.path,
        'docscanner_long_${DateTime.now().microsecondsSinceEpoch}.jpg'));
    await file.writeAsBytes(bytes, flush: true);
    await SharePlus.instance.share(ShareParams(
      files: [XFile(file.path, mimeType: 'image/jpeg')],
      subject: '${document.name} - Long Image',
    ));
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

Uint8List _joinVertical(List<Uint8List> bytes) {
  final pages = <img.Image>[];
  var totalHeight = 0;
  const width = 1100;
  for (final data in bytes) {
    final decoded = img.decodeImage(data);
    if (decoded == null) throw const FormatException('Unsupported page image');
    final upright = img.bakeOrientation(decoded);
    final height = (upright.height * width / upright.width).round().clamp(1, 10000).toInt();
    totalHeight += height;
    // Avoid an OOM on long multi-page scans; the user can split the document.
    if (totalHeight > 15500 || totalHeight * width > 18 * 1000 * 1000) {
      throw const FormatException('Long image exceeds 15,500 pixels in height. '
          'Please split the document into smaller groups.');
    }
    pages.add(img.copyResize(upright, width: width,
        height: height, interpolation: img.Interpolation.average));
  }
  final combined = img.Image(width: width, height: totalHeight);
  img.fill(combined, color: img.ColorRgb8(255, 255, 255));
  var offset = 0;
  for (final page in pages) {
    img.compositeImage(combined, page, dstY: offset);
    offset += page.height;
  }
  return Uint8List.fromList(img.encodeJpg(combined, quality: 86));
}
