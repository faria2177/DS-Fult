import 'dart:io';
import 'dart:ui';

import 'package:doclens/doclens.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'background_contrast_contour.dart';

/// Raw answer of the segmentation model for one photo.
class SalientMask {
  const SalientMask({required this.width, required this.height,
      required this.probability, required this.rgb,
      required this.imageWidth, required this.imageHeight});

  final int width, height;
  /// Foreground probability per pixel, 0..255.
  final Uint8List probability;
  /// Matching thumbnail, 3 bytes (R, G, B) per pixel.
  final Uint8List rgb;
  final int imageWidth, imageHeight;
}

/// Finds the document in an imported photo with a bundled open-source
/// neural network (U²-Net small, Apache-2.0; see assets/models/README.md)
/// and fits its four corners. Runs fully on-device.
///
/// Returns null whenever the model is unavailable or not confident, so the
/// caller's rectangle detectors remain the fallback.
class SalientDocumentDetector {
  static const _asset = 'assets/models/u2netp.onnx';
  static const _channel = MethodChannel('doclens/methods');
  static Future<String?>? _modelPath;

  /// Replaces the platform model in tests.
  @visibleForTesting
  static Future<SalientMask?> Function(String imagePath)? maskProviderForTesting;

  static Future<ImageDetection?> detectFile(String imagePath) async {
    try {
      final provider = maskProviderForTesting;
      final mask = provider != null
          ? await provider(imagePath)
          : await _platformMask(imagePath);
      if (mask == null) return null;
      final quad = BackgroundContrastContour.quadFromSalientMask(
        probability: mask.probability,
        rgb: mask.rgb,
        width: mask.width,
        height: mask.height,
        imageWidth: mask.imageWidth.toDouble(),
        imageHeight: mask.imageHeight.toDouble(),
      );
      if (quad == null) return null;
      return ImageDetection(
        quad: quad,
        imageSize: Size(
            mask.imageWidth.toDouble(), mask.imageHeight.toDouble()),
      );
    } catch (error) {
      debugPrint('Segmentation model unavailable: $error');
      return null;
    }
  }

  static Future<SalientMask?> _platformMask(String imagePath) async {
    final modelPath = await (_modelPath ??= _installModel());
    if (modelPath == null) {
      // Allow another attempt later (e.g. storage was briefly unavailable).
      _modelPath = null;
      return null;
    }
    final raw = await _channel.invokeMapMethod<String, Object?>(
        'salientMask', {'imagePath': imagePath, 'modelPath': modelPath});
    if (raw == null) return null;
    final width = raw['width'], height = raw['height'];
    final probability = raw['probability'], rgb = raw['rgb'];
    final imageWidth = raw['imageWidth'], imageHeight = raw['imageHeight'];
    if (width is! int || height is! int || probability is! Uint8List ||
        rgb is! Uint8List || imageWidth is! int || imageHeight is! int ||
        imageWidth <= 0 || imageHeight <= 0) {
      return null;
    }
    return SalientMask(width: width, height: height,
        probability: probability, rgb: rgb,
        imageWidth: imageWidth, imageHeight: imageHeight);
  }

  /// OpenCV reads the network from a real file, so the bundled asset is
  /// copied once into app storage.
  static Future<String?> _installModel() async {
    try {
      final data = await rootBundle.load(_asset);
      final folder = await getApplicationSupportDirectory();
      final file = File(p.join(folder.path, 'models', 'u2netp.onnx'));
      if (!await file.exists() || await file.length() != data.lengthInBytes) {
        await file.parent.create(recursive: true);
        await file.writeAsBytes(
            data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
            flush: true);
      }
      return file.path;
    } catch (error) {
      debugPrint('Could not prepare segmentation model: $error');
      return null;
    }
  }
}
