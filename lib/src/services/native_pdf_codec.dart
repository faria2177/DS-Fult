import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
// PdfDict / PdfNum are needed for the CCITT decode parameters and are not
// re-exported by package:pdf; they have been stable across 3.x.
// ignore: implementation_imports
import 'package:pdf/src/pdf/format/dict.dart';
// ignore: implementation_imports
import 'package:pdf/src/pdf/format/num.dart';

/// A black-and-white page encoded as CCITT Group 4 by libds_pdfcodec.so.
class BilevelPage {
  const BilevelPage(this.width, this.height, this.data);
  final int width, height;
  final Uint8List data;
}

/// Bridge to libds_pdfcodec.so (DocScanner's own G4 encoder) and Android's
/// built-in JPEG codec. Every call returns null when unavailable, so the
/// Dart export path stays the fallback.
abstract final class NativePdfCodec {
  static const MethodChannel _channel = MethodChannel('doclens/methods');

  /// Kill switch; tests flip it to exercise the bridge.
  static bool enabled = !kIsWeb && Platform.isAndroid;

  /// The page as 1-bit G4 when at least [minShare] of its pixels are clearly
  /// black or white and it has (almost) no colour; otherwise null.
  static Future<BilevelPage?> bilevelPage(String path,
      {double minShare = .97}) async {
    if (!enabled) return null;
    try {
      final raw = await _channel.invokeMapMethod<String, Object?>(
          'pdfBilevelPage', {
        'imagePath': path,
        'minShare': minShare,
        'maxColour': .002,
      });
      if (raw == null) return null;
      final width = raw['width'], height = raw['height'], data = raw['data'];
      if (width is! int || height is! int || data is! Uint8List ||
          data.isEmpty) {
        return null;
      }
      return BilevelPage(width, height, data);
    } catch (error) {
      debugPrint('Native PDF codec unavailable: $error');
      return null;
    }
  }

  /// JPEG with long side ≤ [maxSide] at [quality], via Android's codec.
  static Future<Uint8List?> compactJpeg(String path,
      {required int maxSide, required int quality}) async {
    if (!enabled) return null;
    try {
      return await _channel.invokeMethod<Uint8List>('nativeCompactJpeg', {
        'imagePath': path,
        'maxSide': maxSide,
        'quality': quality,
      });
    } catch (error) {
      debugPrint('Native JPEG compaction unavailable: $error');
      return null;
    }
  }

  /// PDF image XObject for [page]: 1 bit per pixel, /CCITTFaxDecode, K −1.
  static PdfImage pdfImage(PdfDocument document, BilevelPage page) {
    final data = page.data;
    final image = PdfImage.jpegStream(document,
        width: page.width,
        height: page.height,
        length: data.length,
        write: (out) => out.putBytes(data));
    image.params['/Filter'] = const PdfName('/CCITTFaxDecode');
    image.params['/DecodeParms'] = PdfDict.values({
      '/K': const PdfNum(-1),
      '/Columns': PdfNum(page.width),
      '/Rows': PdfNum(page.height),
    });
    image.params['/BitsPerComponent'] = const PdfNum(1);
    image.params['/ColorSpace'] = const PdfName('/DeviceGray');
    image.params.values.remove('/Intent');
    return image;
  }
}
