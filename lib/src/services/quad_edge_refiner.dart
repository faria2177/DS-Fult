import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';

import 'package:doclens/doclens.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

/// Snaps a coarse document quadrilateral onto the real paper/background edge.
///
/// Mask based detectors (colour, brightness, background difference) usually
/// find the document a few percent *inside* its true outline: shiny or pale
/// edges, rounded corners and shadows fall out of the mask, so the crop clips
/// the document. This stage looks at the actual pixels along each side of the
/// coarse quad, finds the strongest background -> document transition on every
/// side, fits one robust straight line per side and intersects neighbouring
/// lines for the four corners (like the final corner step of commercial
/// scanners).
///
/// It is deliberately conservative: any side without enough evidence keeps its
/// original line, and a refined quad that moves too far, changes area too much
/// or stops being convex is discarded, returning the original detection.
class QuadEdgeRefiner {
  const QuadEdgeRefiner._();

  static Future<ImageDetection> refine(
      String imagePath, ImageDetection detection) async {
    final quad = detection.quad;
    if (quad == null) return detection;
    try {
      final bytes = await File(imagePath).readAsBytes();
      final flat = <double>[
        for (final point in quad.points) ...[point.dx, point.dy],
      ];
      final refined = await compute(_refineWorker, <String, Object>{
        'bytes': bytes,
        'quad': flat,
      });
      if (refined == null || refined.length != 8) return detection;
      return ImageDetection(
        quad: Quad(
          topLeft: Offset(refined[0], refined[1]),
          topRight: Offset(refined[2], refined[3]),
          bottomRight: Offset(refined[4], refined[5]),
          bottomLeft: Offset(refined[6], refined[7]),
        ),
        imageSize: detection.imageSize,
      );
    } catch (error) {
      if (kDebugMode) debugPrint('[AutoCrop] edge refinement skipped: $error');
      return detection;
    }
  }

  /// Pure and callable from tests. [normalized] holds eight values:
  /// TL, TR, BR, BL as x,y in 0..1. Returns the refined eight values, or null
  /// when the refinement is not trustworthy.
  static List<double>? refineBytes(Uint8List bytes, List<double> normalized) {
    if (normalized.length != 8) return null;
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return null;
    final source = img.bakeOrientation(decoded);
    final scale = math.min(1.0, 800.0 / math.max(source.width, source.height));
    final width = (source.width * scale).round();
    final height = (source.height * scale).round();
    if (width < 64 || height < 64) return null;
    final working = scale < 1
        ? img.copyResize(source,
            width: width,
            height: height,
            interpolation: img.Interpolation.linear)
        : source;

    final raw = working.getBytes(order: img.ChannelOrder.rgb);
    if (raw.length < width * height * 3) return null;
    final pixels = _blur(raw, width, height);
    final sampler = _Sampler(pixels, width, height);

    final corners = <_P>[
      for (var i = 0; i < 4; i++)
        _P(normalized[i * 2] * width, normalized[i * 2 + 1] * height),
    ];
    final centre = _P(
      (corners[0].x + corners[1].x + corners[2].x + corners[3].x) / 4,
      (corners[0].y + corners[1].y + corners[2].y + corners[3].y) / 4,
    );
    final sideA = corners[0].distanceTo(corners[1]);
    final sideB = corners[0].distanceTo(corners[3]);
    final shortSide = math.min(sideA, sideB);
    if (shortSide < 24) return null;
    // How far either side of the coarse edge to look. Wide enough to recover
    // a pale edge, narrow enough not to jump to a printed border or notebook
    // rule.
    final reach = math.max(6.0, math.min(shortSide * .085, 45.0));

    final lines = <_Line>[];
    for (var side = 0; side < 4; side++) {
      final a = corners[side];
      final b = corners[(side + 1) % 4];
      final dx = b.x - a.x;
      final dy = b.y - a.y;
      final length = math.sqrt(dx * dx + dy * dy);
      if (length < 1) return null;
      final ux = dx / length;
      final uy = dy / length;
      var nx = uy;
      var ny = -ux;
      final midX = (a.x + b.x) / 2 - centre.x;
      final midY = (a.y + b.y) / 2 - centre.y;
      if (nx * midX + ny * midY < 0) {
        nx = -nx;
        ny = -ny;
      }

      // Background colour just beyond the search band.
      final outside = <List<double>>[];
      for (var i = 0; i < 15; i++) {
        final t = .15 + .70 * i / 14;
        outside.add(sampler.at(a.x + dx * t + nx * (reach + 5),
            a.y + dy * t + ny * (reach + 5)));
      }
      final background = <double>[
        for (var c = 0; c < 3; c++) _median([for (final s in outside) s[c]]),
      ];

      final found = <_P>[];
      const window = 5;
      final steps = (reach * 2).floor() + 1;
      for (var i = 0; i < 27; i++) {
        final t = .08 + .84 * i / 26;
        final px = a.x + dx * t;
        final py = a.y + dy * t;
        // distance[k]: colour distance from the background at offset
        // (k - reach) along the outward normal. Inward is the lower index.
        final distance = List<double>.filled(steps, 0);
        for (var k = 0; k < steps; k++) {
          final offset = k - reach;
          final s = sampler.at(px + nx * offset, py + ny * offset);
          final d0 = s[0] - background[0];
          final d1 = s[1] - background[1];
          final d2 = s[2] - background[2];
          distance[k] = math.sqrt(d0 * d0 + d1 * d1 + d2 * d2);
        }
        var bestIndex = -1;
        var bestScore = 14.0; // minimum step contrast
        for (var k = window; k < steps - window; k++) {
          var inner = 0.0;
          var outer = 0.0;
          for (var j = 1; j <= window; j++) {
            inner += distance[k - j];
            outer += distance[k + j];
          }
          final score = (inner - outer) / window;
          if (score > bestScore) {
            bestScore = score;
            bestIndex = k;
          }
        }
        if (bestIndex >= 0) {
          final offset = bestIndex - reach;
          found.add(_P(px + nx * offset, py + ny * offset));
        }
      }

      final fitted = found.length >= 8 ? _robustLine(found) : null;
      lines.add(fitted ?? _Line(a.x, a.y, ux, uy));
    }

    final result = <_P>[];
    for (var k = 0; k < 4; k++) {
      final previous = lines[(k + 3) % 4];
      final current = lines[k];
      final det = previous.dx * -current.dy - previous.dy * -current.dx;
      if (det.abs() < 1e-6) return null;
      final rx = current.px - previous.px;
      final ry = current.py - previous.py;
      // Solve previous.p + previous.d * t = current.p + current.d * s.
      final t = (rx * -current.dy - ry * -current.dx) / det;
      result.add(_P(previous.px + previous.dx * t, previous.py + previous.dy * t));
    }

    for (var i = 0; i < 4; i++) {
      if (result[i].distanceTo(corners[i]) > reach * 2.2) return null;
    }
    final before = _area(corners);
    final after = _area(result);
    if (before <= 0 || after < before * .75 || after > before * 1.35) {
      return null;
    }
    if (!_isConvex(result)) return null;

    return <double>[
      for (final point in result) ...[
        (point.x / width).clamp(0.0, 1.0).toDouble(),
        (point.y / height).clamp(0.0, 1.0).toDouble(),
      ],
    ];
  }

  static _Line? _robustLine(List<_P> input) {
    var points = List<_P>.of(input);
    for (var pass = 0; pass < 4; pass++) {
      final fit = _leastSquares(points);
      final nx = -fit.dy;
      final ny = fit.dx;
      final residuals = [
        for (final p in points) (p.x - fit.px) * nx + (p.y - fit.py) * ny,
      ];
      final centre = _median(residuals);
      final mad = _median([for (final r in residuals) (r - centre).abs()]) + .5;
      final kept = <_P>[
        for (var i = 0; i < points.length; i++)
          if ((residuals[i] - centre).abs() <= mad * 2.5) points[i],
      ];
      if (kept.length < 6) break;
      if (kept.length == points.length) break;
      points = kept;
    }
    return points.length >= 6 ? _leastSquares(points) : null;
  }

  static _Line _leastSquares(List<_P> points) {
    var mx = 0.0;
    var my = 0.0;
    for (final p in points) {
      mx += p.x;
      my += p.y;
    }
    mx /= points.length;
    my /= points.length;
    var sxx = 0.0;
    var syy = 0.0;
    var sxy = 0.0;
    for (final p in points) {
      final x = p.x - mx;
      final y = p.y - my;
      sxx += x * x;
      syy += y * y;
      sxy += x * y;
    }
    final theta = .5 * math.atan2(2 * sxy, sxx - syy);
    return _Line(mx, my, math.cos(theta), math.sin(theta));
  }

  static double _median(List<double> values) {
    final sorted = List<double>.of(values)..sort();
    final middle = sorted.length ~/ 2;
    return sorted.length.isOdd
        ? sorted[middle]
        : (sorted[middle - 1] + sorted[middle]) / 2;
  }

  static double _area(List<_P> p) {
    var twice = 0.0;
    for (var i = 0; i < 4; i++) {
      final a = p[i];
      final b = p[(i + 1) % 4];
      twice += a.x * b.y - b.x * a.y;
    }
    return twice.abs() / 2;
  }

  static bool _isConvex(List<_P> p) {
    var sign = 0;
    for (var i = 0; i < 4; i++) {
      final a = p[i];
      final b = p[(i + 1) % 4];
      final c = p[(i + 2) % 4];
      final cross = (b.x - a.x) * (c.y - b.y) - (b.y - a.y) * (c.x - b.x);
      if (cross.abs() < 1e-6) return false;
      final current = cross > 0 ? 1 : -1;
      if (sign == 0) sign = current;
      if (current != sign) return false;
    }
    return true;
  }

  /// Two 3x3 box passes (~gaussian) so paper grain and JPEG noise do not
  /// create false edge steps. Returns RGB as floats.
  static Float32List _blur(Uint8List rgb, int width, int height) {
    var source = Float32List(width * height * 3);
    for (var i = 0; i < source.length; i++) {
      source[i] = rgb[i].toDouble();
    }
    for (var pass = 0; pass < 2; pass++) {
      final horizontal = Float32List(source.length);
      for (var y = 0; y < height; y++) {
        for (var x = 0; x < width; x++) {
          final left = math.max(0, x - 1);
          final right = math.min(width - 1, x + 1);
          for (var c = 0; c < 3; c++) {
            horizontal[(y * width + x) * 3 + c] = (source[(y * width + left) * 3 + c] +
                    source[(y * width + x) * 3 + c] +
                    source[(y * width + right) * 3 + c]) /
                3;
          }
        }
      }
      final vertical = Float32List(source.length);
      for (var y = 0; y < height; y++) {
        final up = math.max(0, y - 1);
        final down = math.min(height - 1, y + 1);
        for (var x = 0; x < width; x++) {
          for (var c = 0; c < 3; c++) {
            vertical[(y * width + x) * 3 + c] = (horizontal[(up * width + x) * 3 + c] +
                    horizontal[(y * width + x) * 3 + c] +
                    horizontal[(down * width + x) * 3 + c]) /
                3;
          }
        }
      }
      source = vertical;
    }
    return source;
  }
}

class _P {
  const _P(this.x, this.y);
  final double x;
  final double y;
  double distanceTo(_P other) {
    final dx = x - other.x;
    final dy = y - other.y;
    return math.sqrt(dx * dx + dy * dy);
  }
}

/// A point and a unit direction.
class _Line {
  const _Line(this.px, this.py, this.dx, this.dy);
  final double px;
  final double py;
  final double dx;
  final double dy;
}

class _Sampler {
  _Sampler(this.pixels, this.width, this.height);
  final Float32List pixels;
  final int width;
  final int height;

  List<double> at(double x, double y) {
    final cx = x.clamp(0.0, width - 1.001).toDouble();
    final cy = y.clamp(0.0, height - 1.001).toDouble();
    final x0 = cx.floor();
    final y0 = cy.floor();
    final fx = cx - x0;
    final fy = cy - y0;
    final i00 = (y0 * width + x0) * 3;
    final i10 = i00 + 3;
    final i01 = i00 + width * 3;
    final i11 = i01 + 3;
    return <double>[
      for (var c = 0; c < 3; c++)
        pixels[i00 + c] * (1 - fx) * (1 - fy) +
            pixels[i10 + c] * fx * (1 - fy) +
            pixels[i01 + c] * (1 - fx) * fy +
            pixels[i11 + c] * fx * fy,
    ];
  }
}

List<double>? _refineWorker(Map<String, Object> options) =>
    QuadEdgeRefiner.refineBytes(
        options['bytes']! as Uint8List,
        (options['quad']! as List).cast<double>());
