import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:doclens/doclens.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

import 'image_processor.dart';

/// Native-independent, fully offline still-image detector. Gallery images
/// must remain croppable when a device lacks the bundled OpenCV runtime or
/// native contour scoring rejects a photograph on a contrasting background.
///
/// This deliberately segments a *connected outside surface*, not text rows.
/// It declines uncertain masks and always leaves the original available.
class OfflineDocumentContour {
  static Future<ImageDetection?> detectFile(String path,
      {bool preferIdCardBounds = false}) async {
    try {
      final bytes = await File(path).readAsBytes();
      return compute(_detectContourWorker, <String, Object>{
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
    }

    final patchW = math.max(4, (width * .08).round());
    final patchH = math.max(4, (height * .08).round());
    var lightCornerSum = 0;
    var lightCornerCount = 0;
    var neutralCorners = 0;
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
        }
      }
      final count = ((patchW + 1) ~/ 2) * ((patchH + 1) ~/ 2);
      if (colourful * 4 < count) neutralCorners++;
    }
    final backgroundLight = lightCornerSum / math.max(1, lightCornerCount);
    final mask = Uint8List(light.length);
    _ContourProposal? best;
    final modes = <int>[
      if (neutralCorners >= 3) 0, // coloured/gold card on neutral paper
      if (backgroundLight < 181) 1, // pale paper on a dark tabletop
      if (backgroundLight > 155) 2, // dark card on white paper
    ];
    for (final mode in modes) {
      var pixelsInMask = 0;
      final brightCutoff = math.max(117, backgroundLight + 34);
      final darkCutoff = math.min(152, backgroundLight - 43);
      for (var i = 0; i < mask.length; i++) {
        final included = switch (mode) {
          0 => chroma[i] == 1,
          1 => light[i] >= brightCutoff,
          _ => light[i] <= darkCutoff,
        };
        mask[i] = included ? 1 : 0;
        if (included) pixelsInMask++;
      }
      if (pixelsInMask < mask.length * .10 ||
          pixelsInMask > mask.length * .88) continue;
      final candidate = _bestComponent(mask, width, height,
          preferIdCardBounds: preferIdCardBounds);
      if (candidate != null &&
          (best == null || candidate.score > best.score)) {
        best = candidate;
      }
    }
    final quad = best?.quad;
    if (quad == null) return null;
    return ImageDetection(quad: quad,
        imageSize: Size(source.width.toDouble(), source.height.toDouble()));
  }
}

class _ContourProposal {
  const _ContourProposal(this.quad, this.score);
  final Quad quad;
  final double score;
}

_ContourProposal? _bestComponent(Uint8List mask, int width, int height,
    {required bool preferIdCardBounds}) {
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
    if (count < minPixels || borderCount > count * .04) continue;
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
    if (coverage < (preferIdCardBounds ? .13 : .17) || coverage > .90) continue;
    final pixelArea = coverage * width * height;
    final solidity = count / math.max(1.0, pixelArea);
    if (solidity < .47) continue;
    final pixelWidth = ((tr - tl).distance + (br - bl).distance) / 2;
    final pixelHeight = ((bl - tl).distance + (br - tr).distance) / 2;
    if (pixelWidth < 10 || pixelHeight < 10) continue;
    final aspect = math.max(pixelWidth, pixelHeight) /
        math.min(pixelWidth, pixelHeight);
    if (aspect < 1.08 || aspect > 2.40) continue;
    final center = corners.reduce((a, b) => a + b) / 4;
    if ((center.dx - .5).abs() > .30 ||
        (center.dy - .5).abs() > .30) continue;
    if (corners.any((p) => p.dx < .012 || p.dx > .988 ||
        p.dy < .012 || p.dy > .988)) continue;
    final score = math.min(1.0, solidity) * .49 +
        (1 - (center.dx - .5).abs() - (center.dy - .5).abs()) * .27 +
        math.min(1.0, coverage / .50) * .24;
    if (best == null || score > best.score) {
      best = _ContourProposal(Quad(topLeft: corners[0], topRight: corners[1],
          bottomRight: corners[2], bottomLeft: corners[3]), score);
    }
  }
  return best;
}

ImageDetection? _detectContourWorker(Map<String, Object> options) =>
    OfflineDocumentContour.detectBytes(options['bytes']! as Uint8List,
        preferIdCardBounds: options['card']! as bool);
