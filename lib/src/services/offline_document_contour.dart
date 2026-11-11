import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';

import 'package:doclens/doclens.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

import 'image_processor.dart';

/// A proposed outside boundary together with evidence from all four edges.
/// Geometry alone cannot distinguish a real ID from an inner printed box.
class OfflineContourResult {
  const OfflineContourResult(this.detection, this.borderEvidence,
      {this.colorOnNeutralBackground = false});

  final ImageDetection detection;
  /// 0..1: how consistently the inside differs from the surrounding surface.
  final double borderEvidence;
  /// True only when a substantial connected coloured surface was segmented
  /// against neutral exterior corners. Useful to distinguish a real card
  /// from a native page detector's broader notebook/tabletop contour.
  final bool colorOnNeutralBackground;
}

/// Native-independent, fully offline still-image detector. Gallery images
/// must remain croppable when a device lacks the bundled OpenCV runtime or
/// native contour scoring rejects a photograph on a contrasting background.
///
/// This deliberately segments a *connected outside surface*, not text rows.
/// It declines uncertain masks and always leaves the original available.
class OfflineDocumentContour {
  static Future<ImageDetection?> detectFile(String path,
      {bool preferIdCardBounds = false}) async {
    return (await detectDetailedFile(path,
        preferIdCardBounds: preferIdCardBounds))?.detection;
  }

  static Future<OfflineContourResult?> detectDetailedFile(String path,
      {bool preferIdCardBounds = false}) async {
    try {
      final bytes = await File(path).readAsBytes();
      return await compute(_detectDetailedContourWorker, <String, Object>{
        'bytes': bytes,
        'card': preferIdCardBounds,
      });
    } catch (error) {
      debugPrint('Offline contour unavailable: $error');
      return null;
    }
  }

  /// Kept pure and callable from tests. Detection uses a <=512-pixel working
  /// frame; full-resolution perspective correction happens elsewhere.
  static ImageDetection? detectBytes(Uint8List bytes,
      {bool preferIdCardBounds = false}) =>
      detectDetailedBytes(bytes,
          preferIdCardBounds: preferIdCardBounds)?.detection;

  static OfflineContourResult? detectDetailedBytes(Uint8List bytes,
      {bool preferIdCardBounds = false}) {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return null;
    final source = img.bakeOrientation(decoded);
    if (source.width < 64 || source.height < 64) return null;
    final scale = math.min(1.0,
        512.0 / math.max(source.width, source.height));
    final width = (source.width * scale).round();
    final height = (source.height * scale).round();
    if (width < 64 || height < 64) return null;
    final working = scale < 1 ? img.copyResize(source,
        width: width, height: height, interpolation: img.Interpolation.linear)
        : source;

    final pixels = working.getBytes(order: img.ChannelOrder.rgb);
    final light = Uint8List(width * height);
    final chroma = Uint8List(width * height);
    final neutral = Uint8List(width * height);
    var offset = 0;
    for (var i = 0; i < light.length; i++) {
      final r = pixels[offset++];
      final g = pixels[offset++];
      final b = pixels[offset++];
      light[i] = ((r * 77 + g * 150 + b * 29) >> 8);
      final high = math.max(r, math.max(g, b));
      final low = math.min(r, math.min(g, b));
      // A pale gold card has a warm R/B difference even when saturation is
      // below 32%. Thin blue notebook lines have the opposite polarity.
      chroma[i] = (high >= 95 && (high - low) * 100 >= high * 32) ||
              (r >= 130 && g >= 105 && r - b >= 34 && g - b >= 14)
          ? 1 : 0;
      neutral[i] = light[i] >= 130 && high - low <= 34 ? 1 : 0;
    }

    final patchW = math.max(4, (width * .08).round());
    final patchH = math.max(4, (height * .08).round());
    var lightCornerSum = 0;
    var lightCornerCount = 0;
    var neutralCorners = 0;
    final patchColors = List.generate(4, (_) => List<int>.filled(3, 0));
    final patchCounts = List<int>.filled(4, 0);
    for (var corner = 0; corner < 4; corner++) {
      final startX = corner.isOdd ? width - patchW : 0;
      final startY = corner >= 2 ? height - patchH : 0;
      var colourful = 0;
      for (var y = startY; y < startY + patchH; y += 2) {
        for (var x = startX; x < startX + patchW; x += 2) {
          final index = y * width + x;
          lightCornerSum += light[index];
          lightCornerCount++;
          colourful += chroma[index];
          for (var channel = 0; channel < 3; channel++) {
            patchColors[corner][channel] += pixels[index * 3 + channel];
          }
          patchCounts[corner]++;
        }
      }
      final count = ((patchW + 1) ~/ 2) * ((patchH + 1) ~/ 2);
      if (colourful * 4 < count) neutralCorners++;
    }
    final backgroundLight = lightCornerSum / math.max(1, lightCornerCount);
    final background = List<int>.generate(3, (channel) {
      final values = List<int>.generate(4, (corner) =>
          patchColors[corner][channel] ~/ math.max(1, patchCounts[corner]))
        ..sort();
      return (values[1] + values[2]) ~/ 2;
    });
    final variations = List<double>.generate(4, (corner) {
      var difference = 0;
      for (var channel = 0; channel < 3; channel++) {
        final average = patchColors[corner][channel] ~/
            math.max(1, patchCounts[corner]);
        difference += (average - background[channel]).abs();
      }
      return difference / 3;
    })..sort();
    // Only trust a background colour when three corner patches agree.
    final consistentBackground = variations[2] <= 40;
    final colourThreshold = math.max(22, 16 + variations[2] * 1.65);
    final backgroundChroma = background.reduce(math.max) -
        background.reduce(math.min);
    final mask = Uint8List(light.length);
    _ContourProposal? best;
    final modes = <int>[
      if (neutralCorners >= 3) 0, // coloured/gold card on neutral paper
      if (backgroundLight < 181) 1, // pale paper on a dark tabletop
      if (backgroundLight > 155) 2, // dark card on white paper
      if (consistentBackground) 3, // colour difference from surrounding desk
      if (backgroundChroma > 40) 4, // neutral paper on colourful background
    ];
    if (kDebugMode) {
      debugPrint('[AutoCrop] offline: ${width}x$height, modes=$modes, '
          'backgroundLight=${backgroundLight.toStringAsFixed(1)}');
    }
    for (final mode in modes) {
      var pixelsInMask = 0;
      final brightCutoff = math.max(117, backgroundLight + 34);
      final darkCutoff = math.min(152, backgroundLight - 43);
      for (var i = 0; i < mask.length; i++) {
        final included = switch (mode) {
          0 => chroma[i] == 1,
          1 => light[i] >= brightCutoff,
          2 => light[i] <= darkCutoff,
          3 => ((pixels[i * 3] - background[0]).abs() +
                  (pixels[i * 3 + 1] - background[1]).abs() +
                  (pixels[i * 3 + 2] - background[2]).abs()) /
              3 >= colourThreshold,
          _ => neutral[i] == 1,
        };
        mask[i] = included ? 1 : 0;
        if (included) pixelsInMask++;
      }
      if (pixelsInMask < mask.length * .10 ||
          pixelsInMask > mask.length * .88) {
        if (kDebugMode) {
          debugPrint('[AutoCrop] offline mode=$mode rejected: mask='
              '${(pixelsInMask / mask.length).toStringAsFixed(3)}');
        }
        continue;
      }
      final candidate = _bestComponent(mask, width, height,
          pixels: pixels, preferIdCardBounds: preferIdCardBounds);
      if (candidate != null) {
        // Colour-distance segmentation can include an entire grey plastic
        // sleeve *and* the white ID inside it. Prefer the cleaner direct
        // brightness/chroma surface when both provide complete boundaries.
        final priorityPenalty = mode == 3 ? .14 : (mode == 4 ? .035 : 0.0);
        final ranked = _ContourProposal(candidate.quad,
            candidate.score - priorityPenalty, candidate.borderEvidence,
            mode: mode);
        if (best == null || ranked.score > best.score) best = ranked;
      }
    }
    final quad = best?.quad;
    if (quad == null) {
      if (kDebugMode) debugPrint('[AutoCrop] offline: no credible contour');
      return null;
    }
    return OfflineContourResult(ImageDetection(quad: quad,
        imageSize: Size(source.width.toDouble(), source.height.toDouble())),
        best!.borderEvidence,
        colorOnNeutralBackground: best.mode == 0 && neutralCorners >= 3);
  }
}

class _ContourProposal {
  const _ContourProposal(this.quad, this.score, this.borderEvidence,
      {this.mode = -1});
  final Quad quad;
  final double score;
  final double borderEvidence;
  final int mode;
}

_ContourProposal? _bestComponent(Uint8List mask, int width, int height,
    {required Uint8List pixels, required bool preferIdCardBounds}) {
  final seen = Uint8List(mask.length);
  final stack = Int32List(mask.length);
  _ContourProposal? best;
  final minPixels = (mask.length * .09).round();
  for (var start = 0; start < mask.length; start++) {
    if (mask[start] == 0 || seen[start] != 0) continue;
    var top = 0;
    stack[top++] = start;
    seen[start] = 1;
    var count = 0;
    var borderCount = 0;
    var minSum = double.infinity;
    var maxSum = -double.infinity;
    var minDiff = double.infinity;
    var maxDiff = -double.infinity;
    var tl = Offset.zero;
    var tr = Offset.zero;
    var br = Offset.zero;
    var bl = Offset.zero;
    void add(int next) {
      if (mask[next] != 0 && seen[next] == 0) {
        seen[next] = 1;
        stack[top++] = next;
      }
    }
    while (top > 0) {
      final index = stack[--top];
      count++;
      final x = index % width;
      final y = index ~/ width;
      if (x < 2 || x >= width - 2 || y < 2 || y >= height - 2) {
        borderCount++;
      }
      final sum = (x + y).toDouble();
      final diff = (x - y).toDouble();
      final point = Offset(x.toDouble(), y.toDouble());
      if (sum < minSum) { minSum = sum; tl = point; }
      if (sum > maxSum) { maxSum = sum; br = point; }
      if (diff < minDiff) { minDiff = diff; bl = point; }
      if (diff > maxDiff) { maxDiff = diff; tr = point; }
      if (x > 0) add(index - 1);
      if (x + 1 < width) add(index + 1);
      if (y > 0) add(index - width);
      if (y + 1 < height) add(index + width);
    }
    if (count < minPixels) continue;
    final corners = [tl, tr, br, bl].map((p) => Offset(
        p.dx / width, p.dy / height)).toList();
    final safe = CropQuad(corners);
    if (!safe.isValid) continue;
    // Exact shoelace area (a bounding box would wrongly accept a text strip).
    var twiceArea = 0.0;
    for (var i = 0; i < 4; i++) {
      final a = corners[i];
      final b = corners[(i + 1) % 4];
      twiceArea += a.dx * b.dy - b.dx * a.dy;
    }
    final coverage = twiceArea.abs() / 2;
    if (coverage < (preferIdCardBounds ? .13 : .17) || coverage > .90) {
      if (kDebugMode) {
        debugPrint('[AutoCrop] offline component rejected: coverage '
            '${coverage.toStringAsFixed(3)}');
      }
      continue;
    }
    final pixelArea = coverage * width * height;
    final solidity = count / math.max(1.0, pixelArea);
    if (solidity < .47) {
      if (kDebugMode) {
        debugPrint('[AutoCrop] offline component rejected: solidity '
            '${solidity.toStringAsFixed(3)} < .47');
      }
      continue;
    }
    final pixelWidth = ((tr - tl).distance + (br - bl).distance) / 2;
    final pixelHeight = ((bl - tl).distance + (br - tr).distance) / 2;
    if (pixelWidth < 10 || pixelHeight < 10) continue;
    final aspect = math.max(pixelWidth, pixelHeight) /
        math.min(pixelWidth, pixelHeight);
    if (aspect < 1.08 || aspect > 2.40) {
      if (kDebugMode) {
        debugPrint('[AutoCrop] offline component rejected: aspect '
            '${aspect.toStringAsFixed(3)}');
      }
      continue;
    }
    // A card can nearly touch the source image frame. Permit that only when
    // its complete rectangular geometry and four-edge contrast support it;
    // the original .04 border and .012 margin remain for non-card surfaces.
    final cardLike = aspect >= 1.48 && aspect <= 1.75;
    final borderLimit = cardLike ? .12 : .04;
    final margin = cardLike ? .003 : .012;
    if (borderCount > count * borderLimit) {
      if (kDebugMode) {
        debugPrint('[AutoCrop] offline component rejected: border fraction '
            '${(borderCount / count).toStringAsFixed(3)} > $borderLimit');
      }
      continue;
    }
    final center = corners.reduce((a, b) => a + b) / 4;
    if ((center.dx - .5).abs() > .30 ||
        (center.dy - .5).abs() > .30) {
      if (kDebugMode) debugPrint('[AutoCrop] offline component rejected: centre=$center');
      continue;
    }
    final nearFrame = corners.any((p) => p.dx < margin || p.dx > 1 - margin ||
        p.dy < margin || p.dy > 1 - margin);
    if (nearFrame) {
      if (kDebugMode) debugPrint('[AutoCrop] offline component rejected: frame margin $margin');
      continue;
    }
    final edgeEvidence = _boundaryContrast(pixels, width, height,
        <Offset>[tl, tr, br, bl]);
    // The relaxed margins must never admit a notebook edge or an inner text
    // strip just because it has the outline of a standard-sized ID card.
    if (cardLike && (borderCount > count * .04 ||
        corners.any((p) => p.dx < .012 || p.dx > .988 ||
            p.dy < .012 || p.dy > .988)) && edgeEvidence < .55) {
      if (kDebugMode) {
        debugPrint('[AutoCrop] offline card rejected: weak four-edge '
            'evidence ${edgeEvidence.toStringAsFixed(3)} < .55');
      }
      continue;
    }
    final score = math.min(1.0, solidity) * .35 +
        (1 - (center.dx - .5).abs() - (center.dy - .5).abs()) * .20 +
        math.min(1.0, coverage / .50) * .19 + edgeEvidence * .26 +
        (aspect >= 1.48 && aspect <= 2.12 ? .10 : 0);
    if (best == null || score > best.score) {
      best = _ContourProposal(Quad(topLeft: corners[0], topRight: corners[1],
          bottomRight: corners[2], bottomLeft: corners[3]), score,
          edgeEvidence);
    }
  }
  return best;
}

/// Contrast sampled *across* the four actual outer edges. Printed text is
/// high-contrast internally but seldom forms four uninterrupted outer sides.
double _boundaryContrast(Uint8List pixels, int width, int height,
    List<Offset> corners) {
  var sum = 0.0;
  var strongSides = 0;
  for (var side = 0; side < 4; side++) {
    final a = corners[side];
    final b = corners[(side + 1) % 4];
    final dx = b.dx - a.dx;
    final dy = b.dy - a.dy;
    final length = math.sqrt(dx * dx + dy * dy);
    if (length < 12) continue;
    final nx = dy / length;
    final ny = -dx / length;
    var sideTotal = 0.0;
    var sampleCount = 0;
    for (var sample = 1; sample <= 7; sample++) {
      final fraction = sample / 8;
      final x = a.dx + dx * fraction;
      final y = a.dy + dy * fraction;
      final insideX = (x - nx * 5).round();
      final insideY = (y - ny * 5).round();
      final outsideX = (x + nx * 5).round();
      final outsideY = (y + ny * 5).round();
      if (insideX < 0 || insideX >= width || insideY < 0 ||
          insideY >= height || outsideX < 0 || outsideX >= width ||
          outsideY < 0 || outsideY >= height) {
        continue;
      }
      final inner = (insideY * width + insideX) * 3;
      final outer = (outsideY * width + outsideX) * 3;
      var distance = 0;
      for (var channel = 0; channel < 3; channel++) {
        distance += (pixels[inner + channel] -
            pixels[outer + channel]).abs();
      }
      sideTotal += ((distance / 3 - 8) / 28).clamp(0.0, 1.0);
      sampleCount++;
    }
    final sideEvidence = sideTotal / math.max(1, sampleCount);
    sum += sideEvidence;
    if (sideEvidence >= .53) strongSides++;
  }
  return (sum / 4 * .65 + strongSides / 4 * .35)
      .clamp(0.0, 1.0).toDouble();
}

OfflineContourResult? _detectDetailedContourWorker(
        Map<String, Object> options) =>
    OfflineDocumentContour.detectDetailedBytes(options['bytes']! as Uint8List,
        preferIdCardBounds: options['card']! as bool);
