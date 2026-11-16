import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'photo_studio_operations.dart';

/// Native ML Kit Subject Segmentation (Android 7.0+).
///
/// Image pixels never leave the device. On first use Google Play services
/// might need network access to obtain the segmentation model; later image
/// processing uses the downloaded model locally. Color-based removal stays
/// an explicit alternative, not an invisible failure fallback.
abstract final class AiBackgroundRemoval {
  static const MethodChannel _channel = MethodChannel('doclens/methods');

  static Future<Uint8List> remove(
    Uint8List input, {
    int? backgroundArgb,
  }) async {
    // Orientation, image dimensions and memory are normalized in an isolate.
    final normalized = await compute(
      PhotoStudioOperations.prepareAiImage, input,
    );
    final response = await _channel.invokeMethod<Uint8List>(
      'removeSubjectBackground',
      <String, Object?>{
        'imageBytes': normalized,
        'backgroundArgb': backgroundArgb,
      },
    );
    if (response == null || response.isEmpty) {
      throw PlatformException(
        code: 'no_foreground',
        message: 'AI did not return a foreground image. '
            'Retry or use Color-based removal.',
      );
    }
    return response;
  }
}
