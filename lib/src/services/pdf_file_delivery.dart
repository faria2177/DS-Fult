import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// Delivers a generated PDF to Android's document provider or share targets.
/// Source scans and app-library metadata are never modified by either action.
class PdfFileDelivery {
  PdfFileDelivery._();

  static const MethodChannel _platform = MethodChannel('doclens/methods');

  static String filenameFor(String documentName) {
    final safe = documentName.trim()
        .replaceAll(RegExp(r'[/\\\r\n]'), '_')
        .replaceAll(RegExp(r'[<>:"|?*]'), '_');
    final stem = safe.toLowerCase().endsWith('.pdf')
        ? safe.substring(0, safe.length - 4) : safe;
    if (stem.trim().isEmpty) return 'DocScanner.pdf';
    return '${stem.length > 80 ? stem.substring(0, 80) : stem}.pdf';
  }

  static Future<File> _stage(Uint8List pdf) async {
    if (pdf.length < 5 || String.fromCharCodes(pdf.take(5)) != '%PDF-') {
      throw const FormatException('Could not generate a valid PDF');
    }
    final directory = await getTemporaryDirectory();
    final file = File(p.join(directory.path,
      'docscanner_output_${DateTime.now().microsecondsSinceEpoch}.pdf'));
    await file.writeAsBytes(pdf, flush: true);
    return file;
  }

  /// Returns false when the user cancels the Android Save As dialog.
  static Future<bool> saveToDevice(Uint8List pdf, String fileName) async {
    final staged = await _stage(pdf);
    try {
      return await _platform.invokeMethod<bool>('savePdfFile', {
        'sourcePath': staged.path,
        'fileName': fileName,
      }) ?? false;
    } finally {
      // Android has completed its private copy when the channel replies.
      if (await staged.exists()) await staged.delete();
    }
  }

  static Future<void> share(Uint8List pdf, String fileName) async {
    final staged = await _stage(pdf);
    await SharePlus.instance.share(ShareParams(
      files: [XFile(staged.path, mimeType: 'application/pdf', name: fileName)],
      subject: fileName,
    ));
    // Share targets may retain access to the staged URI after the chooser
    // closes; let Android evict this private cache file instead of deleting it.
  }
}
