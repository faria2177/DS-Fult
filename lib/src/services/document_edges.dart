import 'package:doclens/doclens.dart';
import 'package:flutter/foundation.dart';

import 'image_processor.dart';

/// The same on-device document contour detector is used by camera capture,
/// gallery auto-crop and the manual corner editor.
class DocumentEdges {
  static const scannerConfig = ScannerConfig(
    detectionPolarity: DetectionPolarity.auto,
    detectionThresholdOffset: 17,
    detectionThrottleHz: 12,
    enableQuadSmoothing: true,
    // Use a longer rolling history so the green four-sided outline tracks
    // steady document edges without jumping between individual frames.
    quadSmoothingWindow: 9,
    enablePerspectiveWarp: true,
    enableSharpnessGate: true,
    sharpnessFloor: 8.5,
    enableAutoCaptureConfirmation: true,
    autoCaptureCornerThreshold: .014,
    autoCaptureStabilityDuration: Duration(milliseconds: 1100),
    autoCaptureConfirmationDelay: Duration(milliseconds: 400),
    enableLowLightDetection: true,
    enableStabilityStatus: true,
    enableTapToFocus: true,
    captureResolution: Resolution.max,
  );

  /// A null result means that the native detector did not find a reliable
  /// convex four-corner boundary. Never invent a crop in that situation.
  static Future<ImageDetection?> detect(String imagePath) async {
    final detection = await DoclensPlatform.instance.detectInImage(
      imagePath: imagePath,
      config: scannerConfig,
    );
    final quad = detection?.quad;
    if (quad == null || !CropQuad(quad.points).isValid) return null;
    return detection;
  }

  /// Original photos remain unchanged, including when no document is found.
  /// Per-file failure falls back to the original so imports never disappear.
  static Future<AutoCropBatch> autoCropFiles(List<String> images) async {
    final output = <String>[];
    var cropped = 0;
    for (final image in images) {
      try {
        final detection = await detect(image);
        if (detection == null) {
          output.add(image);
          continue;
        }
        final croppedPath = await DoclensPlatform.instance.warpImage(
          rawImagePath: image,
          quad: detection.quadIn,
          jpegQuality: 95,
          enhancement: ImageEnhancement.enhanced,
        );
        output.add(croppedPath);
        cropped++;
      } catch (error) {
        debugPrint('Auto-crop skipped for $image: $error');
        output.add(image);
      }
    }
    return AutoCropBatch(output, cropped);
  }
}

class AutoCropBatch {
  const AutoCropBatch(this.paths, this.croppedCount);

  final List<String> paths;
  final int croppedCount;

  int get needsReview => paths.length - croppedCount;
}
