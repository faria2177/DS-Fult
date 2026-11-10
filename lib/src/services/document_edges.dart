import 'package:doclens/doclens.dart';
import 'package:flutter/foundation.dart';

import 'image_processor.dart';

/// The same on-device document contour detector is used by camera capture,
/// gallery auto-crop and the manual corner editor.
class DocumentEdges {
  static const scannerConfig = ScannerConfig(
    // Never fire the camera automatically. Edge detection and auto-crop still
    // run; the user chooses when to take the picture.
    enableAutoCapture: false,
    enableAutoCaptureConfirmation: false,
    detectionPolarity: DetectionPolarity.auto,
    // A smaller offset helps in dim scenes and on lightly coloured ID cards.
    detectionThresholdOffset: 12,
    detectionThrottleHz: 12,
    enableQuadSmoothing: true,
    // Identity-aware tracking rejects stray rectangles before smoothing;
    // seven frames keep edges steady without the lag of a nine-frame median.
    quadSmoothingWindow: 7,
    enablePerspectiveWarp: true,
    enableSharpnessGate: true,
    sharpnessFloor: 8.5,
    autoCaptureCornerThreshold: .014,
    autoCaptureStabilityDuration: Duration(milliseconds: 1100),
    autoCaptureConfirmationDelay: Duration(milliseconds: 400),
    enableLowLightDetection: true,
    enableStabilityStatus: true,
    enableTapToFocus: true,
    captureResolution: Resolution.max,
  );

  /// Keep the normal A4 detector unchanged. Card capture must favour the
  /// smaller, centred card over an application form underneath it.
  static const idCardScannerConfig = ScannerConfig(
    enableAutoCapture: false,
    enableAutoCaptureConfirmation: false,
    detectionPolarity: DetectionPolarity.auto,
    detectionThresholdOffset: 12,
    detectionThrottleHz: 12,
    enableQuadSmoothing: true,
    quadSmoothingWindow: 7,
    enablePerspectiveWarp: true,
    enableSharpnessGate: true,
    sharpnessFloor: 8.5,
    enableLowLightDetection: true,
    enableStabilityStatus: true,
    enableTapToFocus: true,
    captureResolution: Resolution.max,
    preferIdCardBounds: true,
  );

  /// A null result means that the native detector did not find a reliable
  /// convex four-corner boundary. Never invent a crop in that situation.
  static Future<ImageDetection?> detect(String imagePath,
      {bool preferIdCardBounds = false}) async {
    final detection = await DoclensPlatform.instance.detectInImage(
      imagePath: imagePath,
      config: preferIdCardBounds ? idCardScannerConfig : scannerConfig,
    );
    final quad = detection?.quad;
    if (quad == null || !CropQuad(quad.points).isValid) return null;
    return detection;
  }

  /// A gallery photo has no live-camera page outline to cross-check against.
  /// Never irreversibly warp it to a small inner text/table rectangle. Such a
  /// false positive is particularly destructive for identity cards imported
  /// through the normal Scan tab: the name block survives but the photo,
  /// header and card number disappear. Uncertain imports retain their full
  /// original photo and can still be cropped manually.
  ///
  /// The dedicated ID-card detector already has its own card-size policy;
  /// do not apply A4 page geometry to that explicit workflow.
  static bool isReliableGalleryCrop(ImageDetection detection,
      {bool preferIdCardBounds = false}) {
    final quad = detection.quad;
    final imageSize = detection.imageSize;
    if (quad == null || imageSize.width <= 0 || imageSize.height <= 0) {
      return false;
    }
    final points = quad.points;
    if (points.any((point) => !point.dx.isFinite || !point.dy.isFinite ||
        point.dx < 0 || point.dx > 1 || point.dy < 0 || point.dy > 1)) {
      return false;
    }
    if (preferIdCardBounds) return true;

    final area = quad.area;
    // Below this, a strong-looking rectangle is often a printed *part* of a
    // document. A conservative original beats an unrecoverable partial scan.
    if (area < .30) return false;

    final pixelPoints = quad.scaleToSize(imageSize).points;
    final horizontal = ((pixelPoints[1] - pixelPoints[0]).distance +
            (pixelPoints[2] - pixelPoints[3]).distance) /
        2;
    final vertical = ((pixelPoints[3] - pixelPoints[0]).distance +
            (pixelPoints[2] - pixelPoints[1]).distance) /
        2;
    final shortSide = horizontal < vertical ? horizontal : vertical;
    final longSide = horizontal > vertical ? horizontal : vertical;
    if (shortSide <= 0 || longSide / shortSide > 1.95) return false;

    final left = points.map((p) => p.dx).reduce((a, b) => a < b ? a : b);
    final right = points.map((p) => p.dx).reduce((a, b) => a > b ? a : b);
    final top = points.map((p) => p.dy).reduce((a, b) => a < b ? a : b);
    final bottom = points.map((p) => p.dy).reduce((a, b) => a > b ? a : b);
    // A compact box surrounded by unselected image on *all four sides* is
    // likely the interior of a page/card, not its outside paper boundary.
    if (area < .56 && left > .045 && right < .955 &&
        top > .065 && bottom < .935) {
      return false;
    }
    return true;
  }

  /// The regular Scan detector can lock onto the printed name box of an ID
  /// photo. When this happens, an independent card-mode pass may recover the
  /// *outer* card. Accept that alternative only if it actually surrounds the
  /// original candidate, is substantially larger and has card-like geometry.
  /// Otherwise keep the uncropped gallery photo for manual review.
  static bool isCredibleOuterCardAlternative(
      ImageDetection inner, ImageDetection outer) {
    final innerQuad = inner.quad;
    final outerQuad = outer.quad;
    if (innerQuad == null || outerQuad == null) return false;
    if ((inner.imageSize.width - outer.imageSize.width).abs() > 1 ||
        (inner.imageSize.height - outer.imageSize.height).abs() > 1) {
      return false;
    }
    final outerArea = outerQuad.area;
    if (outerArea < .30 || outerArea > .94 ||
        outerArea < innerQuad.area * 1.45) {
      return false;
    }
    if (outerQuad.points.any((p) => !p.dx.isFinite || !p.dy.isFinite ||
        p.dx < 0 || p.dx > 1 || p.dy < 0 || p.dy > 1)) {
      return false;
    }
    if (!innerQuad.points.every(outerQuad.contains)) return false;

    final points = outerQuad.scaleToSize(outer.imageSize).points;
    final width = ((points[1] - points[0]).distance +
        (points[2] - points[3]).distance) / 2;
    final height = ((points[3] - points[0]).distance +
        (points[2] - points[1]).distance) / 2;
    if (width <= 0 || height <= 0) return false;
    final ratio = width > height ? width / height : height / width;
    return ratio >= 1.30 && ratio <= 2.10;
  }

  /// Original photos remain unchanged, including when no document is found.
  /// Per-file failure falls back to the original so imports never disappear.
  static Future<AutoCropBatch> autoCropFiles(List<String> images,
      {bool preferIdCardBounds = false}) async {
    final output = <String>[];
    var cropped = 0;
    for (final image in images) {
      try {
        var detection = await detect(image,
            preferIdCardBounds: preferIdCardBounds);
        var safeToWarp = detection != null && isReliableGalleryCrop(detection,
            preferIdCardBounds: preferIdCardBounds);
        if (!safeToWarp && !preferIdCardBounds && detection != null) {
          // Only an uncertain normal-Scan result pays for a second detector
          // pass. Do not silently accept an unrelated background rectangle.
          final card = await detect(image, preferIdCardBounds: true);
          if (card != null && isCredibleOuterCardAlternative(detection, card)) {
            detection = card;
            safeToWarp = true;
          }
        }
        if (detection == null || !safeToWarp) {
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
