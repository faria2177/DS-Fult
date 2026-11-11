import 'dart:io';
import 'dart:math' as math;

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
    if (quad == null || !CropQuad(quad.points).isValid) {
      _log(imagePath, 'native ${preferIdCardBounds ? 'card' : 'page'} pass: no valid quadrilateral');
      return null;
    }
    return detection;
  }

  static void _log(String imagePath, String reason) {
    if (kDebugMode) {
      debugPrint('[AutoCrop] ${p.basename(imagePath)}: $reason');
    }
  }

  static bool _reject(String gate, String reason) {
    if (kDebugMode) debugPrint('[AutoCrop] $gate rejected: $reason');
    return false;
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
      return _reject('gallery', 'missing quad or image dimensions');
    }
    final points = quad.points;
    if (points.any((point) => !point.dx.isFinite || !point.dy.isFinite ||
        point.dx < 0 || point.dx > 1 || point.dy < 0 || point.dy > 1)) {
      return _reject('gallery', 'out-of-bounds or non-finite corners');
    }
    if (preferIdCardBounds) return true;

    final area = quad.area;
    // Below this, a strong-looking rectangle is often a printed *part* of a
    // document. A conservative original beats an unrecoverable partial scan.
    if (area < .30) return _reject('gallery', 'coverage ${area.toStringAsFixed(3)} < .30');

    final pixelPoints = quad.scaleToSize(imageSize).points;
    final horizontal = ((pixelPoints[1] - pixelPoints[0]).distance +
            (pixelPoints[2] - pixelPoints[3]).distance) /
        2;
    final vertical = ((pixelPoints[3] - pixelPoints[0]).distance +
            (pixelPoints[2] - pixelPoints[1]).distance) /
        2;
    final shortSide = horizontal < vertical ? horizontal : vertical;
    final longSide = horizontal > vertical ? horizontal : vertical;
    if (shortSide <= 0 || longSide / shortSide > 1.95) {
      return _reject('gallery', 'aspect ${shortSide <= 0 ? 'invalid' : (longSide / shortSide).toStringAsFixed(2)} > 1.95');
    }

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
      return _reject('gallery', 'incomplete page strip: spanX=${spanX.toStringAsFixed(2)}, spanY=${spanY.toStringAsFixed(2)}');
    }
    // A compact box surrounded by unselected image on *all four sides* is
    // likely the interior of a page/card, not its outside paper boundary.
    if (area < .56 && left > .045 && right < .955 &&
        top > .065 && bottom < .935) {
      return _reject('gallery', 'inner printed box, coverage=${area.toStringAsFixed(3)}');
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
      return _reject('card', 'invalid quad or image dimensions');
    }
    final area = quad.area;
    // A complete coloured ID photographed on ruled notebook paper can cover
    // only ~20% of the image. The dedicated native card pass independently
    // checks chroma, outside corners and aspect ratio before returning it.
    // Still reject tiny printed name blocks and near-full background pages.
    if (area < .19 || area > .86) {
      return _reject('card', 'coverage ${area.toStringAsFixed(3)} outside .19–.86');
    }
    if (quad.points.any((p) => !p.dx.isFinite || !p.dy.isFinite ||
        p.dx < .004 || p.dx > .996 || p.dy < .004 || p.dy > .996)) {
      return _reject('card', 'corner too close to image frame');
    }
    final cx = quad.points.map((p) => p.dx).reduce((a, b) => a + b) / 4;
    final cy = quad.points.map((p) => p.dy).reduce((a, b) => a + b) / 4;
    if ((cx - .5).abs() > .22 || (cy - .5).abs() > .22) {
      return _reject('card', 'off-centre candidate ($cx, $cy)');
    }

    final points = quad.scaleToSize(size).points;
    final width = ((points[1] - points[0]).distance +
        (points[2] - points[3]).distance) / 2;
    final height = ((points[3] - points[0]).distance +
        (points[2] - points[1]).distance) / 2;
    if (width <= 0 || height <= 0) return _reject('card', 'invalid side length');
    final ratio = width > height ? width / height : height / width;
    if (ratio < 1.48 || ratio > 2.10) {
      return _reject('card', 'aspect ${ratio.toStringAsFixed(2)} outside 1.48–2.10');
    }
    return true;
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

  /// A dark plastic sleeve or clipboard can be a closed, inset quadrilateral
  /// itself, so the near-frame test alone is insufficient. Only a second,
  /// smaller complete ID with strong *four-side colour evidence* can replace
  /// that broad native result. This deliberately does not apply to an
  /// arbitrary inner printed rectangle.
  static bool isCredibleCardInsideHolder(ImageDetection holder,
      ImageDetection card, {required double borderEvidence}) {
    final outer = holder.quad;
    final inner = card.quad;
    if (outer == null || inner == null || borderEvidence < .67 ||
        !isCredibleStandaloneCard(card)) {
      return false;
    }
    if ((holder.imageSize.width - card.imageSize.width).abs() > 1 ||
        (holder.imageSize.height - card.imageSize.height).abs() > 1 ||
        outer.area < .49 || inner.area > outer.area * .72 ||
        !inner.points.every(outer.contains)) {
      return false;
    }
    // An ordinary portrait A4 sheet may contain a large inset chart. A
    // landscape holder surrounding a landscape ID is a different scene.
    final outerPoints = outer.scaleToSize(holder.imageSize).points;
    final outerWidth = ((outerPoints[1] - outerPoints[0]).distance +
        (outerPoints[2] - outerPoints[3]).distance) / 2;
    final outerHeight = ((outerPoints[3] - outerPoints[0]).distance +
        (outerPoints[2] - outerPoints[1]).distance) / 2;
    if (outerWidth < outerHeight * 1.08) return false;
    // The candidate must have visible exterior clearance on all sides;
    // matching the holder itself is not a reason to warp the same image twice.
    final ox = outer.points.map((p) => p.dx).toList();
    final oy = outer.points.map((p) => p.dy).toList();
    final ix = inner.points.map((p) => p.dx).toList();
    final iy = inner.points.map((p) => p.dy).toList();
    double low(List<double> values) => values.reduce(math.min);
    double high(List<double> values) => values.reduce(math.max);
    return low(ix) - low(ox) >= .022 && high(ox) - high(ix) >= .022 &&
        low(iy) - low(oy) >= .022 && high(oy) - high(iy) >= .022;
  }

  /// A camera may report the surrounding notebook as a valid, fairly inset
  /// page. It is *not* necessarily near three image sides, so that old guard
  /// misses a large gold/coloured ID on ruled paper. An independently
  /// segmented, sizeable coloured card with evidence from its real outside
  /// border can replace that proposal without admitting tiny inner labels.
  /// This does not affect the usual A4 scan or a plain white paper page.
  static bool isCredibleColoredCardOverPage(
      ImageDetection page, OfflineContourResult proposed) {
    final outer = page.quad;
    final card = proposed.detection;
    final inner = card.quad;
    if (outer == null || inner == null ||
        !proposed.colorOnNeutralBackground ||
        proposed.borderEvidence < .56 ||
        !isCredibleStandaloneCard(card)) {
      return false;
    }
    if ((page.imageSize.width - card.imageSize.width).abs() > 1 ||
        (page.imageSize.height - card.imageSize.height).abs() > 1 ||
        outer.area < .62 || inner.area < .28 ||
        inner.area < outer.area * .51 ||
        inner.area > outer.area * .84 ||
        !inner.points.every(outer.contains)) {
      return false;
    }
    return true;
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
      _log(imagePath, 'native page detector failed: $error');
    }
    final normalIsSafe = normal != null &&
        isReliableGalleryCrop(normal,
            preferIdCardBounds: preferIdCardBounds) &&
        (!preferIdCardBounds || isCredibleStandaloneCard(normal));

    // Most well-framed A4 pages need just one pass. A compact/interior result
    // or a dominant camera-frame rectangle merits an independent card pass.
    final area = normal?.quad?.area ?? 0;
    // Even a 70%-frame 'page' can be the surrounding notebook. Run the card
    // pass when its outline crowds three frame sides; the native chroma mask
    // can then recover the much smaller gold/coloured ID inside it.
    final normalQuad = normal?.quad;
    final nativeLooksLikeWholePage = !preferIdCardBounds && normalIsSafe &&
        area > .62 && normalQuad != null &&
        !_nearFrameOnThreeSides(normalQuad);

    ImageDetection? card;
    if (!preferIdCardBounds && !nativeLooksLikeWholePage) {
      try {
        card = await detect(imagePath, preferIdCardBounds: true);
      } catch (error) {
        _log(imagePath, 'native card detector failed: $error');
      }
    }
    if (card != null) {
      if (normal == null && isCredibleStandaloneCard(card)) {
        _log(imagePath, 'accepted native card with no page quad');
        return card;
      }
      if (normal != null &&
          (isCredibleOuterCardAlternative(normal, card) ||
           isCredibleCardInsideBackground(normal, card))) {
        _log(imagePath, 'accepted native outer card alternative');
        return card;
      }
    }

    // Independent on-device pixel segmentation. This is deliberately not a
    // neural image generator: it never invents a face, text or ID number.
    // It also operates when native OpenCV is missing or returns no quad.
    final independent = await OfflineDocumentContour.detectDetailedFile(imagePath,
        preferIdCardBounds: preferIdCardBounds);
    final offline = independent?.detection;
    final outside = offline?.quad;
    if (offline != null && outside != null) {
      if (preferIdCardBounds) {
        final credible = isCredibleStandaloneCard(offline);
        if (credible && (!normalIsSafe ||
            isCredibleOuterCardAlternative(normal, offline) ||
            isCredibleCardInsideHolder(normal, offline,
                borderEvidence: independent!.borderEvidence))) {
          _log(imagePath, 'accepted independent card outline');
          return offline;
        }
      }
      if (!preferIdCardBounds) {
        final safePage = isReliableGalleryCrop(offline);
        final safeCard = isCredibleStandaloneCard(offline);
        if (normal == null && (safePage || safeCard)) {
          _log(imagePath, 'accepted independent ${safeCard ? 'card' : 'page'} outline');
          return offline;
        }
        if (normal != null &&
            (isCredibleOuterCardAlternative(normal, offline) ||
             isCredibleCardInsideBackground(normal, offline) ||
             (safeCard && isCredibleColoredCardOverPage(
                 normal, independent!)) ||
             (safeCard && isCredibleCardInsideHolder(normal, offline,
                 borderEvidence: independent!.borderEvidence)) ||
             (!normalIsSafe && safePage && normalQuad != null &&
              outside.area >= normalQuad.area * 1.3 &&
              normalQuad.points.every(outside.contains)))) {
          _log(imagePath, 'accepted independent outer boundary');
          return offline;
        }
      }
    }
    if (!normalIsSafe) {
      final pageArea = normal?.quad?.area;
      final cardArea = card?.quad?.area;
      final offlineArea = offline?.quad?.area;
      _log(imagePath, 'no reliable outside boundary '
          '(page=${pageArea?.toStringAsFixed(3) ?? 'none'}, '
          'card=${cardArea?.toStringAsFixed(3) ?? 'none'}, '
          'offline=${offlineArea?.toStringAsFixed(3) ?? 'none'})');
    }
    return normalIsSafe ? normal : null;
  }

  /// Original photos remain unchanged, including when no document is found.
  /// Per-file failure falls back to the original so imports never disappear.
  static Future<AutoCropBatch> autoCropFiles(List<String> images,
      {bool preferIdCardBounds = false}) async {
    final output = <String>[];
    final failed = <int>[];
    var cropped = 0;
    for (var index = 0; index < images.length; index++) {
      final image = images[index];
      try {
        final detection = await detectSafeStillOutline(image,
            preferIdCardBounds: preferIdCardBounds);
        if (detection == null) {
          output.add(image);
          failed.add(index);
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
          _log(image, 'native warp failed, trying Dart: $error');
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
        _log(image, 'auto-crop skipped: $error');
        output.add(image);
        failed.add(index);
      }
    }
    return AutoCropBatch(output, cropped, failedIndexes: failed);
  }
}

class AutoCropBatch {
  const AutoCropBatch(this.paths, this.croppedCount,
      {this.failedIndexes = const <int>[]});

  final List<String> paths;
  final int croppedCount;
  /// Indexes into [paths] that retained their uncropped source image.
  final List<int> failedIndexes;

  int get needsReview => paths.length - croppedCount;
}
