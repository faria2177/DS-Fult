import 'dart:io';

import 'package:doclens/doclens.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Bridge to libds_scannercore.so — DocScanner's own C++ scanner core
/// (third_party/doclens/android/src/main/cpp/ds_scanner_core.cpp).
///
/// The Dart implementations (PaperRegionDetector, scanDocument) remain the
/// reference and the fallback: every call here returns null when the native
/// library is missing, fails, or the platform is not Android.
abstract final class NativeScannerCore {
  static const MethodChannel _channel = MethodChannel('doclens/methods');

  /// Kill switch; tests flip it to exercise the bridge.
  static bool enabled = !kIsWeb && Platform.isAndroid;

  /// Scanner-style enhance of an upright, cropped page. Null when the page
  /// is not black-and-white (it then keeps the regular Enhance).
  static Future<Uint8List?> magicEnhance(Uint8List bytes,
      {bool png = false}) async {
    if (!enabled) return null;
    try {
      return await _channel.invokeMethod<Uint8List>('nativeMagicEnhance', {
        'imageBytes': bytes,
        'png': png,
        'onlyNeutral': true,
      });
    } catch (error) {
      debugPrint('Native magic enhance unavailable: $error');
      return null;
    }
  }

  /// Paper region of a photo file: (quad or null, upright size, fraction).
  static Future<(Quad?, Size, double)?> paperRegion(String path) async {
    if (!enabled) return null;
    try {
      final raw = await _channel.invokeMethod<Map<dynamic, dynamic>>(
          'nativePaperRegion', {'imagePath': path});
      if (raw == null) return null;
      final size = Size((raw['width'] as num).toDouble(),
          (raw['height'] as num).toDouble());
      final fraction = (raw['paperFraction'] as num).toDouble();
      final c = (raw['corners'] as List).map((v) => (v as num).toDouble())
          .toList();
      final quad = raw['found'] == true && c.length == 8
          ? Quad(
              topLeft: Offset(c[0], c[1]),
              topRight: Offset(c[2], c[3]),
              bottomRight: Offset(c[4], c[5]),
              bottomLeft: Offset(c[6], c[7]))
          : null;
      return (quad, size, fraction);
    } catch (error) {
      debugPrint('Native paper region unavailable: $error');
      return null;
    }
  }
}
