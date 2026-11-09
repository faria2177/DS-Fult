import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models.dart';

/// Converts selected image-backed PDF document pages at full page resolution,
/// preserving source captures and the page ordering chosen in the editor.
class PdfImageExport {
  PdfImageExport._();

  @visibleForTesting
  static Uint8List transcode(Uint8List bytes,
      {required bool png, int jpegQuality = 92}) {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) {
      throw const FormatException('Page image is damaged or unsupported.');
    }
    final upright = img.bakeOrientation(decoded);
    return Uint8List.fromList(png
        ? img.encodePng(upright)
        : img.encodeJpg(upright, quality: jpegQuality.clamp(50, 100)));
  }

  static Future<List<File>> exportPages(ScanDocument document,
      List<int> indices, {bool png = false}) async {
    if (indices.isEmpty || indices.toSet().length != indices.length) {
      throw const FormatException('Select one or more different pages.');
    }
    final directory = await getTemporaryDirectory();
    final batch = 'docscanner_pages_${DateTime.now().microsecondsSinceEpoch}';
    final output = <File>[];
    for (final index in indices) {
      if (index < 0 || index >= document.pages.length) {
        throw RangeError.index(index, document.pages);
      }
      final original = await File(document.pages[index].path).readAsBytes();
      final data = await compute(_transcodeForIsolate,
          (bytes: original, png: png));
      final ext = png ? 'png' : 'jpg';
      final file = File(p.join(directory.path,
          '${batch}_page_${(index + 1).toString().padLeft(3, '0')}.$ext'));
      await file.writeAsBytes(data, flush: true);
      output.add(file);
    }
    return output;
  }
}

Uint8List _transcodeForIsolate(({Uint8List bytes, bool png}) input) =>
    PdfImageExport.transcode(input.bytes, png: input.png);
