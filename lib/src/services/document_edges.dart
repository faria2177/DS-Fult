import 'dart:io';

import 'package:doclens/doclens.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'image_processor.dart';
import 'offline_document_contour.dart';

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
    // A text strip can touch the *left and right* photo boundaries, bypassing
    // the four-sided inset check below. That is what the 381861.mp4 NID crop
    // looks like: width fills the frame but face/header above it disappear.
    // A complete card or page must not turn into a horizontal/vertical band.
    final spanX = right - left;
    final spanY = bottom - top;
    if (area < .64 &&
        ((spanX > .79 && spanY < .62) ||
         (spanY > .79 && spanX < .62))) {
      return false;
    }
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
    if (!isCredibleStandaloneCard(outer) ||
        outerArea < innerQuad.area * 1.45) {
      return false;
    }
    if (!innerQuad.points.every(outerQuad.contains)) return false;

    return true;
  }

  /// Independent card-mode results must pass stricter geometry before they
  /// can crop a normal Scan import whose page detector returned *nothing*.
  /// A compact central text box is easy to mistake for a card, so require
  /// substantial coverage, an actual landscape-card ratio and a near-centred
  /// fully visible outline. A weak result keeps the unmodified original.
  static bool isCredibleStandaloneCard(ImageDetection detection) {
    final quad = detection.quad;
    final size = detection.imageSize;
    if (quad == null || size.width <= 0 || size.height <= 0 ||
        !CropQuad(quad.points).isValid) {
      return false;
    }
    final area = quad.area;
    // A complete coloured ID photographed on ruled notebook paper can cover
    // only ~20% of the image. The dedicated native card pass independently
    // checks chroma, outside corners and aspect ratio before returning it.
    // Still reject tiny printed name blocks and near-full background pages.
    if (area < .19 || area > .86) return false;
    if (quad.points.any((p) => !p.dx.isFinite || !p.dy.isFinite ||
        p.dx < .012 || p.dx > .988 || p.dy < .012 || p.dy > .988)) {
      return false;
    }
    final cx = quad.points.map((p) => p.dx).reduce((a, b) => a + b) / 4;
    final cy = quad.points.map((p) => p.dy).reduce((a, b) => a + b) / 4;
    if ((cx - .5).abs() > .22 || (cy - .5).abs() > .22) return false;

    final points = quad.scaleToSize(size).points;
    final width = ((points[1] - points[0]).distance +
        (points[2] - points[3]).distance) / 2;
    final height = ((points[3] - points[0]).distance +
        (points[2] - points[1]).distance) / 2;
    if (width <= 0 || height <= 0) return false;
    final ratio = width > height ? width / height : height / width;
    return ratio >= 1.48 && ratio <= 2.10;
  }

  /// A near-frame contour can be the notebook/tabletop surrounding a smaller
  /// card (381861.mp4). Replace such a broad background *only* with a fully
  /// enclosed and strongly card-shaped independent proposal. A normal A4
  /// inset several percent from the camera border remains authoritative.
  static bool isCredibleCardInsideBackground(
      ImageDetection background, ImageDetection card) {
    final whole = background.quad;
    final inner = card.quad;
    if (whole == null || inner == null || !isCredibleStandaloneCard(card)) {
      return false;
    }
    if ((background.imageSize.width - card.imageSize.width).abs() > 1 ||
        (background.imageSize.height - card.imageSize.height).abs() > 1) {
      return false;
    }
    if (whole.area < .76 || inner.area < .19 ||
        inner.area > whole.area * .78 ||
        !inner.points.every(whole.contains)) {
      return false;
    }
    return _nearFrameOnThreeSides(whole);
  }

  /// A ruled notebook/tabletop detected as the outer quadrilateral nearly
  /// fills the photo. Its four-sided frame evidence is very different from a
  /// properly framed paper page with a visible margin on every side.
  static bool _nearFrameOnThreeSides(Quad quad) {
    final xs = quad.points.map((p) => p.dx).toList();
    final ys = quad.points.map((p) => p.dy).toList();
    final frameSides = [
      xs.reduce((a, b) => a < b ? a : b) < .065,
      xs.reduce((a, b) => a > b ? a : b) > .935,
      ys.reduce((a, b) => a < b ? a : b) < .065,
      ys.reduce((a, b) => a > b ? a : b) > .935,
    ].where((touches) => touches).length;
    return frameSides >= 3;
  }

  /// Used by *both* automatic gallery import and Adjust corners → Auto
  /// Detect. Neither route may promote an interior table/name block to a
  /// complete document. Try the independent card outline even when the
  /// ordinary page detector returned null; otherwise leave the photo whole.
  static Future<ImageDetection?> detectSafeStillOutline(String imagePath,
      {bool preferIdCardBounds = false}) async {
    ImageDetection? normal;
    try {
      normal = await detect(imagePath,
          preferIdCardBounds: preferIdCardBounds);
    } catch (error) {
      debugPrint('Native page detector failed, trying offline fallback: $error');
    }
    final normalIsSafe = normal != null && isReliableGalleryCrop(normal,
        preferIdCardBounds: preferIdCardBounds);
    if (preferIdCardBounds && normalIsSafe) return normal;

    // Most well-framed A4 pages need just one pass. A compact/interior result
    // or a dominant camera-frame rectangle merits an independent card pass.
    final area = normal?.quad?.area ?? 0;
    // Even a 70%-frame 'page' can be the surrounding notebook. Run the card
    // pass when its outline crowds three frame sides; the native chroma mask
    // can then recover the much smaller gold/coloured ID inside it.
    final normalQuad = normal?.quad;
    if (!preferIdCardBounds && normalIsSafe && area > .62 && normalQuad != null &&
        !_nearFrameOnThreeSides(normalQuad)) {
      return normal;
    }

    ImageDetection? card;
    if (!preferIdCardBounds) {
      try {
        card = await detect(imagePath, preferIdCardBounds: true);
      } catch (error) {
        debugPrint('Native card detector failed: $error');
      }
    }
    if (card != null) {
      if (normal == null && isCredibleStandaloneCard(card)) return card;
      if (normal != null &&
          (isCredibleOuterCardAlternative(normal, card) ||
           isCredibleCardInsideBackground(normal, card))) {
        return card;
      }
    }

    // Independent on-device pixel segmentation. This is deliberately not a
    // neural image generator: it never invents a face, text or ID number.
    // It also operates when native OpenCV is missing or returns no quad.
    final offline = await OfflineDocumentContour.detectFile(imagePath,
        preferIdCardBounds: preferIdCardBounds);
    final outside = offline?.quad;
    if (offline != null && outside != null) {
      if (preferIdCardBounds && isCredibleStandaloneCard(offline)) {
        return offline;
      }
      if (!preferIdCardBounds) {
        final safePage = isReliableGalleryCrop(offline);
        final safeCard = isCredibleStandaloneCard(offline);
        if (normal == null && (safePage || safeCard)) return offline;
        if (normal != null &&
            (isCredibleOuterCardAlternative(normal, offline) ||
             isCredibleCardInsideBackground(normal, offline) ||
             (!normalIsSafe && safePage && normalQuad != null &&
              outside.area >= normalQuad.area * 1.3 &&
              normalQuad.points.every(outside.contains)))) {
          return offline;
        }
      }
    }
    return normalIsSafe ? normal : null;
  }

  /// Original photos remain unchanged, including when no document is found.
  /// Per-file failure falls back to the original so imports never disappear.
  static Future<AutoCropBatch> autoCropFiles(List<String> images,
      {bool preferIdCardBounds = false}) async {
    final output = <String>[];
    var cropped = 0;
    for (final image in images) {
      try {
        final detection = await detectSafeStillOutline(image,
            preferIdCardBounds: preferIdCardBounds);
        if (detection == null) {
          output.add(image);
          continue;
        }
        String croppedPath;
        try {
          croppedPath = await DoclensPlatform.instance.warpImage(
            rawImagePath: image,
            quad: detection.quadIn,
            jpegQuality: 95,
            // Keep colour effects separate from irreversible geometry.
            enhancement: ImageEnhancement.none,
          );
        } catch (error) {
          debugPrint('Native perspective warp failed, using Dart: $error');
          final croppedBytes = await ImageProcessor.process(
            await File(image).readAsBytes(),
            crop: CropQuad(detection.quad!.points),
          );
          final file = File(p.join(Directory.systemTemp.path,
              'ds_offline_crop_${DateTime.now().microsecondsSinceEpoch}.jpg'));
          await file.writeAsBytes(croppedBytes, flush: true);
          croppedPath = file.path;
        }
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
