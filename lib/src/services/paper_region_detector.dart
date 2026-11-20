import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';

import 'package:doclens/doclens.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

/// The visible part of a sheet of paper that fills most of a photo and runs
/// off one or more edges of the frame.
///
/// Users photograph full pages from close up (386450/386455/386456): the
/// sheet covers 60–90% of the photo, runs off the right and bottom edges,
/// and only a strip of cloth shows on the other sides. Every rectangle
/// detector looks for four paper corners inside the photo, finds a table
/// or nothing, and the import stayed uncropped and unenhanced. CamScanner
/// crops such photos along the visible paper edges and the frame.
///
/// This finds the largest bright, colourless region (paper), reduces its
/// outline to four corners — corners may lie on the frame edge — and
/// accepts it only when the region is clearly brighter than what surrounds
/// it and fills its outline.
class PaperRegionDetector {
  static const int _workingSide = 420;

  static Future<PaperRegion?> detectFile(String path) async {
    try {
      final bytes = await File(path).readAsBytes();
      return await compute(detectBytes, bytes);
    } catch (error) {
      debugPrint('Paper region detector unavailable: $error');
      return null;
    }
  }

  /// Pure and synchronous so tests can call it directly.
  static PaperRegion? detectBytes(Uint8List bytes) {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return null;
    final source = img.bakeOrientation(decoded);
    if (source.width < 64 || source.height < 64) return null;
    final scale = math.min(1.0,
        _workingSide / math.max(source.width, source.height));
    final w = math.max(1, (source.width * scale).round());
    final h = math.max(1, (source.height * scale).round());
    final small = scale < 1
        ? img.copyResize(source, width: w, height: h,
            interpolation: img.Interpolation.average)
        : source;
    final size = Size(source.width.toDouble(), source.height.toDouble());

    final luma = Float32List(w * h);
    final chroma = Float32List(w * h);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final p = small.getPixel(x, y);
        final r = p.r.toDouble();
        final g = p.g.toDouble();
        final b = p.b.toDouble();
        luma[y * w + x] = .299 * r + .587 * g + .114 * b;
        chroma[y * w + x] = math.max(r, math.max(g, b)) -
            math.min(r, math.min(g, b));
      }
    }

    final threshold = _otsu(luma);
    if (threshold < 70) return null;
    final paper = Uint8List(w * h);
    for (var i = 0; i < w * h; i++) {
      if (luma[i] >= threshold && chroma[i] < 58) paper[i] = 1;
    }
    // Printed text and table lines are holes in the paper mask; fill them so
    // the opening below cannot eat a text-heavy page.
    _fillHoles(paper, w, h);
    // Thin light things touching the sheet (a wall rail, a cable, another
    // sheet's edge) would join it into one odd shape (386313: a grey rail
    // ran across the photo behind the page). An opening cuts those links:
    // shrink, keep the largest part, grow it back inside the paper mask.
    final radius = math.max(3, (math.max(w, h) * .016).round());
    final eroded = _minFilter(paper, w, h, radius);
    final component = _largestComponent(eroded, w, h);
    if (component == null) return null;
    final grown = _maxFilter(component.$1, w, h, radius);
    final mask = Uint8List(w * h);
    var count = 0;
    for (var i = 0; i < w * h; i++) {
      if (grown[i] == 1 && paper[i] == 1) {
        mask[i] = 1;
        count++;
      }
    }
    final fraction = count / (w * h);
    final paperFraction = fraction;
    if (fraction < .25) return PaperRegion(null, size, paperFraction);

    // Paper must stand out from the rest of the photo.
    var inSum = 0.0;
    var outSum = 0.0;
    for (var i = 0; i < w * h; i++) {
      if (mask[i] == 1) {
        inSum += luma[i];
      } else {
        outSum += luma[i];
      }
    }
    final outside = w * h - count;
    if (outside < w * h * .04) return PaperRegion(null, size, paperFraction);
    if (inSum / count - outSum / outside < 38) {
      return PaperRegion(null, size, paperFraction);
    }

    // Row extents → convex hull → four corners.
    final points = <Offset>[];
    for (var y = 0; y < h; y++) {
      var minX = -1;
      var maxX = -1;
      for (var x = 0; x < w; x++) {
        if (mask[y * w + x] == 1) {
          if (minX < 0) minX = x;
          maxX = x;
        }
      }
      if (minX >= 0) {
        points.add(Offset(minX.toDouble(), y.toDouble()));
        points.add(Offset(maxX + 1.0, y.toDouble()));
        points.add(Offset(minX.toDouble(), y + 1.0));
        points.add(Offset(maxX + 1.0, y + 1.0));
      }
    }
    final hull = _convexHull(points);
    if (hull.length < 4) return PaperRegion(null, size, paperFraction);
    final corners = _reduceToFour(hull);
    final quadArea = _area(corners);
    final hullArea = _area(hull);
    if (quadArea <= 0 || quadArea < hullArea * .93) {
      return PaperRegion(null, size, paperFraction);
    }
    if (count / quadArea < .82) return PaperRegion(null, size, paperFraction);

    final normalized = [
      for (final c in corners)
        Offset((c.dx / w).clamp(0.0, 1.0), (c.dy / h).clamp(0.0, 1.0)),
    ];
    // Whole photo is paper: nothing to crop.
    const tol = .025;
    final atFrameCorner = normalized.where((p) =>
        (p.dx < tol || p.dx > 1 - tol) && (p.dy < tol || p.dy > 1 - tol));
    if (atFrameCorner.length == 4) return PaperRegion(null, size, paperFraction);

    final quad = _ordered(normalized);
    if (quad == null) return PaperRegion(null, size, paperFraction);
    return PaperRegion(ImageDetection(quad: quad, imageSize: size), size,
        paperFraction);
  }

  /// Marks every "off" pixel that cannot reach the frame border as "on".
  static void _fillHoles(Uint8List m, int w, int h) {
    final outside = Uint8List(w * h);
    final stack = <int>[];
    void seed(int i) {
      if (m[i] == 0 && outside[i] == 0) {
        outside[i] = 1;
        stack.add(i);
      }
    }

    for (var x = 0; x < w; x++) {
      seed(x);
      seed((h - 1) * w + x);
    }
    for (var y = 0; y < h; y++) {
      seed(y * w);
      seed(y * w + w - 1);
    }
    while (stack.isNotEmpty) {
      final i = stack.removeLast();
      final x = i % w;
      if (x > 0) seed(i - 1);
      if (x < w - 1) seed(i + 1);
      if (i >= w) seed(i - w);
      if (i < (h - 1) * w) seed(i + w);
    }
    for (var i = 0; i < w * h; i++) {
      if (outside[i] == 0) m[i] = 1;
    }
  }

  /// Square min/max filters, separable (rows then columns).
  static Uint8List _minFilter(Uint8List m, int w, int h, int r) =>
      _squareFilter(m, w, h, r, keepIfAll: true);
  static Uint8List _maxFilter(Uint8List m, int w, int h, int r) =>
      _squareFilter(m, w, h, r, keepIfAll: false);

  static Uint8List _squareFilter(Uint8List m, int w, int h, int r,
      {required bool keepIfAll}) {
    Uint8List pass(Uint8List src, bool horizontal) {
      final out = Uint8List(w * h);
      final lines = horizontal ? h : w;
      final length = horizontal ? w : h;
      for (var line = 0; line < lines; line++) {
        // Running count of "on" pixels in the window.
        int at(int k) => horizontal ? src[line * w + k] : src[k * w + line];
        var on = 0;
        for (var k = 0; k <= math.min(r, length - 1); k++) {
          on += at(k);
        }
        for (var k = 0; k < length; k++) {
          final lo = math.max(0, k - r);
          final hi = math.min(length - 1, k + r);
          final size = hi - lo + 1;
          final value = keepIfAll ? (on == size ? 1 : 0) : (on > 0 ? 1 : 0);
          if (horizontal) {
            out[line * w + k] = value;
          } else {
            out[k * w + line] = value;
          }
          if (k + r + 1 < length) on += at(k + r + 1);
          if (k - r >= 0) on -= at(k - r);
        }
      }
      return out;
    }

    return pass(pass(m, true), false);
  }

  static double _otsu(Float32List values) {
    final hist = List<int>.filled(256, 0);
    for (final v in values) {
      hist[v.round().clamp(0, 255)]++;
    }
    final total = values.length;
    var sum = 0.0;
    for (var i = 0; i < 256; i++) {
      sum += i * hist[i];
    }
    var sumB = 0.0;
    var wB = 0;
    var best = 0.0;
    var threshold = 0;
    for (var t = 0; t < 256; t++) {
      wB += hist[t];
      if (wB == 0) continue;
      final wF = total - wB;
      if (wF == 0) break;
      sumB += t * hist[t];
      final mB = sumB / wB;
      final mF = (sum - sumB) / wF;
      final between = wB * wF * (mB - mF) * (mB - mF);
      if (between > best) {
        best = between;
        threshold = t;
      }
    }
    return threshold.toDouble();
  }

  static (Uint8List, int)? _largestComponent(Uint8List on, int w, int h) {
    final label = Int32List(w * h);
    var next = 0;
    var bestLabel = 0;
    var bestCount = 0;
    final stack = <int>[];
    for (var start = 0; start < w * h; start++) {
      if (on[start] == 0 || label[start] != 0) continue;
      next++;
      var count = 0;
      stack.add(start);
      label[start] = next;
      while (stack.isNotEmpty) {
        final i = stack.removeLast();
        count++;
        final x = i % w;
        final y = i ~/ w;
        void visit(int j) {
          if (on[j] == 1 && label[j] == 0) {
            label[j] = next;
            stack.add(j);
          }
        }

        if (x > 0) visit(i - 1);
        if (x < w - 1) visit(i + 1);
        if (y > 0) visit(i - w);
        if (y < h - 1) visit(i + w);
      }
      if (count > bestCount) {
        bestCount = count;
        bestLabel = next;
      }
    }
    if (bestCount == 0) return null;
    final mask = Uint8List(w * h);
    for (var i = 0; i < w * h; i++) {
      if (label[i] == bestLabel) mask[i] = 1;
    }
    return (mask, bestCount);
  }

  static List<Offset> _convexHull(List<Offset> points) {
    final pts = List<Offset>.of(points)
      ..sort((a, b) => a.dx != b.dx ? a.dx.compareTo(b.dx)
          : a.dy.compareTo(b.dy));
    double cross(Offset o, Offset a, Offset b) =>
        (a.dx - o.dx) * (b.dy - o.dy) - (a.dy - o.dy) * (b.dx - o.dx);
    final lower = <Offset>[];
    for (final p in pts) {
      while (lower.length >= 2 &&
          cross(lower[lower.length - 2], lower.last, p) <= 0) {
        lower.removeLast();
      }
      lower.add(p);
    }
    final upper = <Offset>[];
    for (final p in pts.reversed) {
      while (upper.length >= 2 &&
          cross(upper[upper.length - 2], upper.last, p) <= 0) {
        upper.removeLast();
      }
      upper.add(p);
    }
    return [...lower.sublist(0, lower.length - 1),
      ...upper.sublist(0, upper.length - 1)];
  }

  /// Drop the hull vertex whose removal loses the least area, until four
  /// remain (Visvalingam). Keeps the frame corners of a sheet that runs off
  /// the photo, unlike a min-area rectangle.
  static List<Offset> _reduceToFour(List<Offset> hull) {
    final pts = List<Offset>.of(hull);
    double tri(Offset a, Offset b, Offset c) =>
        ((b.dx - a.dx) * (c.dy - a.dy) - (b.dy - a.dy) * (c.dx - a.dx))
            .abs() / 2;
    while (pts.length > 4) {
      var bestIndex = 0;
      var bestLoss = double.infinity;
      for (var i = 0; i < pts.length; i++) {
        final loss = tri(pts[(i - 1 + pts.length) % pts.length], pts[i],
            pts[(i + 1) % pts.length]);
        if (loss < bestLoss) {
          bestLoss = loss;
          bestIndex = i;
        }
      }
      pts.removeAt(bestIndex);
    }
    return pts;
  }

  static double _area(List<Offset> p) {
    var s = 0.0;
    for (var i = 0; i < p.length; i++) {
      final a = p[i];
      final b = p[(i + 1) % p.length];
      s += a.dx * b.dy - b.dx * a.dy;
    }
    return s.abs() / 2;
  }

  static Quad? _ordered(List<Offset> pts) {
    if (pts.length != 4) return null;
    final sums = [for (final p in pts) p.dx + p.dy];
    final diffs = [for (final p in pts) p.dx - p.dy];
    int argMin(List<double> v) =>
        List.generate(v.length, (i) => i).reduce((a, b) => v[a] <= v[b] ? a : b);
    int argMax(List<double> v) =>
        List.generate(v.length, (i) => i).reduce((a, b) => v[a] >= v[b] ? a : b);
    final tl = argMin(sums);
    final br = argMax(sums);
    final tr = argMax(diffs);
    final bl = argMin(diffs);
    if ({tl, br, tr, bl}.length != 4) return null;
    return Quad(topLeft: pts[tl], topRight: pts[tr], bottomRight: pts[br],
        bottomLeft: pts[bl]);
  }
}

class PaperRegion {
  const PaperRegion(this.detection, this.imageSize, this.paperFraction);

  /// Visible paper outline, or null when it is not a clear sheet.
  final ImageDetection? detection;
  final Size imageSize;

  /// Share of the photo covered by the largest paper-like region.
  final double paperFraction;
}
