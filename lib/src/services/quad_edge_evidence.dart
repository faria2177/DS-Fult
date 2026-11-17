import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:doclens/doclens.dart';

/// Result of checking an outline against the photo's real edges.
class EdgeEvidence {
  const EdgeEvidence(this.quad, this.weakestSide);

  /// The outline after each side was snapped to the nearest clear edge.
  final Quad quad;

  /// Share (0..1) of the weakest free side that sits on a visible colour
  /// change. Sides lying on the photo border are not counted.
  final double weakestSide;

  /// Every free side follows a real edge in the photo.
  bool get confirmed => weakestSide >= QuadEdgeEvidence.confirmedSupport;
}

/// Checks and fine-tunes a document outline using the photo itself.
///
/// A segmentation model sees "one object", which can merge a page with the
/// papers lying under it. A real page side, however, is a straight line with
/// a colour change across it. Each side is moved (by at most ~6% of the
/// photo) onto the line with the clearest such change, and the weakest
/// side's support tells the caller whether to trust the outline.
class QuadEdgeEvidence {
  static const confirmedSupport = .45;
  static const _searchFraction = .06;
  static const _minimumToMove = .60;
  static const _colourStep = 30;

  /// [rgb] is a [width]x[height] RGB image (3 bytes per pixel).
  static EdgeEvidence? check(Quad quad, Uint8List rgb, int width, int height) {
    if (width < 16 || height < 16 || rgb.length != width * height * 3) {
      return null;
    }
    final w = width.toDouble(), h = height.toDouble();
    final points = [for (final p in quad.points) Offset(p.dx * w, p.dy * h)];
    final centre = points.reduce((a, b) => a + b) / 4;
    final reach = math.max(4, (_searchFraction * math.min(width, height)).round());
    final lines = <List<Offset>>[];
    var weakest = 1.0;
    for (var i = 0; i < 4; i++) {
      var a = points[i];
      var b = points[(i + 1) % 4];
      final along = b - a;
      final length = along.distance;
      if (length < 8) return null;
      final unit = along / length;
      var inward = Offset(-unit.dy, unit.dx);
      final middle = (a + b) / 2;
      if ((centre - middle).dx * inward.dx + (centre - middle).dy * inward.dy < 0) {
        inward = -inward;
      }
      if (_onPhotoBorder(a, b, w, h)) {
        lines.add([a, b]);
        continue;
      }
      final base = _support(rgb, width, height, a, b, inward, 24).share;
      var best = base;
      var bestA = 0, bestB = 0;
      for (var shiftA = -reach; shiftA <= reach; shiftA += 2) {
        for (var shiftB = -reach; shiftB <= reach; shiftB += 2) {
          final score = _support(rgb, width, height, a + inward * shiftA.toDouble(),
              b + inward * shiftB.toDouble(), inward, 24);
          if (score.samples < 12) continue;
          // Better, or as good and further out: a page's true edge is its
          // outermost straight line, never a printed rule inside it.
          if (score.share > best + .03 ||
              ((score.share - best).abs() <= .03 &&
                  shiftA + shiftB < bestA + bestB)) {
            best = score.share;
            bestA = shiftA;
            bestB = shiftB;
          }
        }
      }
      if (best >= _minimumToMove && best >= base + .15) {
        a = a + inward * bestA.toDouble();
        b = b + inward * bestB.toDouble();
      }
      weakest = math.min(weakest,
          _support(rgb, width, height, a, b, inward, 48).share);
      lines.add([a, b]);
    }
    final corners = <Offset>[];
    for (var i = 0; i < 4; i++) {
      final corner = _intersect(lines[(i + 3) % 4], lines[i]);
      if (corner == null) return null;
      corners.add(Offset((corner.dx / w).clamp(0.0, 1.0),
          (corner.dy / h).clamp(0.0, 1.0)));
    }
    return EdgeEvidence(
      Quad(topLeft: corners[0], topRight: corners[1],
          bottomRight: corners[2], bottomLeft: corners[3]),
      weakest,
    );
  }

  static bool _onPhotoBorder(Offset a, Offset b, double w, double h) {
    final margin = .02 * math.max(w, h);
    return (a.dx < margin && b.dx < margin) ||
        (a.dx > w - margin && b.dx > w - margin) ||
        (a.dy < margin && b.dy < margin) ||
        (a.dy > h - margin && b.dy > h - margin);
  }

  /// Share of points along a..b where the colour 2–6 px inside clearly
  /// differs from the colour 2–6 px outside.
  static ({double share, int samples}) _support(Uint8List rgb, int width,
      int height, Offset a, Offset b, Offset inward, int count) {
    var hits = 0, samples = 0;
    for (var i = 0; i < count; i++) {
      final t = .08 + .84 * i / (count - 1);
      final px = a.dx + (b.dx - a.dx) * t, py = a.dy + (b.dy - a.dy) * t;
      var ir = 0, ig = 0, ib = 0, inCount = 0;
      var or = 0, og = 0, ob = 0, outCount = 0;
      for (var k = 2; k <= 6; k++) {
        final xi = (px + inward.dx * k).toInt(), yi = (py + inward.dy * k).toInt();
        if (xi >= 0 && yi >= 0 && xi < width && yi < height) {
          final o = (yi * width + xi) * 3;
          ir += rgb[o];
          ig += rgb[o + 1];
          ib += rgb[o + 2];
          inCount++;
        }
        final xo = (px - inward.dx * k).toInt(), yo = (py - inward.dy * k).toInt();
        if (xo >= 0 && yo >= 0 && xo < width && yo < height) {
          final o = (yo * width + xo) * 3;
          or += rgb[o];
          og += rgb[o + 1];
          ob += rgb[o + 2];
          outCount++;
        }
      }
      if (inCount == 0 || outCount == 0) continue;
      samples++;
      final step = (ir / inCount - or / outCount).abs() +
          (ig / inCount - og / outCount).abs() +
          (ib / inCount - ob / outCount).abs();
      if (step > _colourStep) hits++;
    }
    return (share: samples == 0 ? 0.0 : hits / samples, samples: samples);
  }

  static Offset? _intersect(List<Offset> first, List<Offset> second) {
    final p = first[0], r = first[1] - first[0];
    final q = second[0], s = second[1] - second[0];
    final denominator = r.dx * s.dy - r.dy * s.dx;
    if (denominator.abs() < 1e-9) return null;
    final t = ((q - p).dx * s.dy - (q - p).dy * s.dx) / denominator;
    return p + r * t;
  }
}
