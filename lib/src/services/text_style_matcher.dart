import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show Rect;

import 'package:image/image.dart' as img;

/// How a text line sits on the page, so an edited line keeps its place.
enum LineAlignment { left, center, right }

/// What [analyzeAndEraseLine] learned about one printed line.
class LineAnalysis {
  const LineAnalysis({
    required this.cleared,
    required this.region,
    required this.mask,
    required this.inkBox,
    required this.ink,
    required this.blurSigma,
    required this.imageWidth,
    required this.imageHeight,
  });

  /// The page with only this line's ink removed (PNG).
  final Uint8List cleared;

  /// Analysed pixel region (left, top, width, height).
  final ({int x, int y, int w, int h}) region;

  /// 1 = glyph pixel, row-major over [region].
  final Uint8List mask;

  /// Tight box around the glyphs, in page pixels.
  final Rect inkBox;

  /// Glyph colour (r, g, b): the darkest part of the strokes, not the
  /// lighter anti-aliased edges.
  final List<int> ink;

  /// How soft the printed/scanned edges are, in pixels.
  final double blurSigma;
  final int imageWidth;
  final int imageHeight;

  Map<String, Object> toMap() => {
    'cleared': cleared,
    'region': [region.x, region.y, region.w, region.h],
    'mask': mask,
    'inkBox': [inkBox.left, inkBox.top, inkBox.right, inkBox.bottom],
    'ink': ink,
    'blur': blurSigma,
    'size': [imageWidth, imageHeight],
  };

  static LineAnalysis fromMap(Map<String, Object> map) {
    final r = map['region']! as List<int>;
    final b = map['inkBox']! as List<double>;
    final s = map['size']! as List<int>;
    return LineAnalysis(
      cleared: map['cleared']! as Uint8List,
      region: (x: r[0], y: r[1], w: r[2], h: r[3]),
      mask: map['mask']! as Uint8List,
      inkBox: Rect.fromLTRB(b[0], b[1], b[2], b[3]),
      ink: map['ink']! as List<int>,
      blurSigma: map['blur']! as double,
      imageWidth: s[0],
      imageHeight: s[1],
    );
  }
}

double _luma(num r, num g, num b) => .299 * r + .587 * g + .114 * b;

/// Isolate entry: `{'bytes': Uint8List, 'area': [l, t, r, b] normalized}`.
///
/// Only the glyph pixels (and their anti-aliased rim) are replaced; every
/// other pixel of the paper keeps its original texture. Replaced pixels get
/// the background interpolated per column from just above and below the
/// line, plus noise with the paper's own grain, so no flat patch remains.
/// Table borders crossing the box survive because they are dark both above
/// and below the line.
Map<String, Object> analyzeAndEraseLine(Map<String, Object> options) {
  final source = img.decodeImage(options['bytes']! as Uint8List);
  if (source == null) throw const FormatException('Unsupported image');
  final image = img.bakeOrientation(source);
  final c = options['area']! as List<double>;
  final lineH = math.max(1.0, (c[3] - c[1]) * image.height);
  final pad = math.max(2, (lineH * .18).round());
  final x0 = ((c[0] * image.width).floor() - pad).clamp(0, image.width - 1);
  final y0 = ((c[1] * image.height).floor() - pad).clamp(0, image.height - 1);
  final x1 = ((c[2] * image.width).ceil() + pad).clamp(x0 + 1, image.width);
  final y1 = ((c[3] * image.height).ceil() + pad).clamp(y0 + 1, image.height);
  final w = x1 - x0;
  final h = y1 - y0;

  // Background per column: median of a few rows just above and below.
  final band = math.max(2, pad ~/ 2);
  List<double> columnBackground(int x, int yStart, int yEnd) {
    final values = <List<double>>[];
    for (var y = yStart; y < yEnd; y++) {
      if (y < 0 || y >= image.height) continue;
      final p = image.getPixel(x, y);
      values.add([p.r.toDouble(), p.g.toDouble(), p.b.toDouble()]);
    }
    if (values.isEmpty) return const [235, 235, 235];
    values.sort((a, b) => _luma(a[0], a[1], a[2])
        .compareTo(_luma(b[0], b[1], b[2])));
    return values[values.length * 2 ~/ 3];
  }

  final above = [for (var x = x0; x < x1; x++)
    columnBackground(x, y0 - band, y0 + 1)];
  final below = [for (var x = x0; x < x1; x++)
    columnBackground(x, y1 - 1, y1 + band)];
  List<double> background(int x, int y) {
    final t = h <= 1 ? 0.0 : (y - y0) / (h - 1);
    final a = above[x - x0];
    final b = below[x - x0];
    return [a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t,
      a[2] + (b[2] - a[2]) * t];
  }

  // Ink = clearly darker than the local background.
  final mask = Uint8List(w * h);
  final soft = Uint8List(w * h);
  final paper = <double>[];
  var darkest = 255.0;
  var bgSum = 0.0;
  for (var y = y0; y < y1; y++) {
    for (var x = x0; x < x1; x++) {
      final p = image.getPixel(x, y);
      final l = _luma(p.r, p.g, p.b);
      final bg = background(x, y);
      final bl = _luma(bg[0], bg[1], bg[2]);
      bgSum += bl;
      darkest = math.min(darkest, l);
      final i = (y - y0) * w + (x - x0);
      if (l < bl - 45) {
        mask[i] = 1;
      } else if (l < bl - 14) {
        soft[i] = 1;
      } else {
        paper.add(l - bl);
      }
    }
  }

  // Long straight rules (table borders, underlines) are not glyphs.
  for (var y = 0; y < h; y++) {
    var run = 0;
    for (var x = 0; x < w; x++) {
      run += mask[y * w + x];
    }
    if (run > w * .85) {
      for (var x = 0; x < w; x++) {
        mask[y * w + x] = 0;
        soft[y * w + x] = 0;
      }
    }
  }
  for (var x = 0; x < w; x++) {
    var run = 0;
    for (var y = 0; y < h; y++) {
      run += mask[y * w + x];
    }
    if (run > h * .85) {
      for (var y = 0; y < h; y++) {
        mask[y * w + x] = 0;
        soft[y * w + x] = 0;
      }
    }
  }

  // Glyph colour from the darkest 35% of stroke pixels; tight ink box.
  final strokes = <List<int>>[];
  var minX = w;
  var minY = h;
  var maxX = -1;
  var maxY = -1;
  var softCount = 0;
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final i = y * w + x;
      if (mask[i] == 1) {
        final p = image.getPixel(x0 + x, y0 + y);
        strokes.add([p.r.toInt(), p.g.toInt(), p.b.toInt()]);
        minX = math.min(minX, x);
        maxX = math.max(maxX, x);
        minY = math.min(minY, y);
        maxY = math.max(maxY, y);
      } else if (soft[i] == 1) {
        softCount++;
      }
    }
  }
  var ink = const [34, 34, 34];
  if (strokes.isNotEmpty) {
    strokes.sort((a, b) => _luma(a[0], a[1], a[2])
        .compareTo(_luma(b[0], b[1], b[2])));
    final take = math.max(1, (strokes.length * .35).round());
    var r = 0;
    var g = 0;
    var b = 0;
    for (var k = 0; k < take; k++) {
      r += strokes[k][0];
      g += strokes[k][1];
      b += strokes[k][2];
    }
    ink = [r ~/ take, g ~/ take, b ~/ take];
  }
  final blur = strokes.isEmpty ? .5
      : (.25 + 1.1 * softCount / strokes.length).clamp(.3, 1.6).toDouble();
  final inkBox = maxX < 0
      ? Rect.fromLTRB(c[0] * image.width, c[1] * image.height,
          c[2] * image.width, c[3] * image.height)
      : Rect.fromLTRB((x0 + minX).toDouble(), (y0 + minY).toDouble(),
          (x0 + maxX + 1).toDouble(), (y0 + maxY + 1).toDouble());

  // Paper grain (standard deviation of the non-ink pixels).
  var grain = 0.0;
  if (paper.length > 4) {
    final mean = paper.reduce((a, b) => a + b) / paper.length;
    var v = 0.0;
    for (final d in paper) {
      v += (d - mean) * (d - mean);
    }
    grain = math.sqrt(v / paper.length).clamp(0, 12).toDouble();
  }

  // Replace glyph pixels plus a 1–2 px rim (anti-aliasing) with paper.
  final rim = lineH > 40 ? 2 : 1;
  final random = math.Random(w * 31 + h);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      var hit = false;
      for (var dy = -rim; dy <= rim && !hit; dy++) {
        for (var dx = -rim; dx <= rim && !hit; dx++) {
          final yy = y + dy;
          final xx = x + dx;
          if (yy < 0 || yy >= h || xx < 0 || xx >= w) continue;
          hit = mask[yy * w + xx] == 1;
        }
      }
      if (!hit && soft[y * w + x] == 0) continue;
      final bg = background(x0 + x, y0 + y);
      final n = grain == 0 ? 0.0
          : (random.nextDouble() + random.nextDouble() - 1) * grain * 1.2;
      image.setPixelRgb(x0 + x, y0 + y,
          (bg[0] + n).round().clamp(0, 255),
          (bg[1] + n).round().clamp(0, 255),
          (bg[2] + n).round().clamp(0, 255));
    }
  }

  return LineAnalysis(
    cleared: Uint8List.fromList(img.encodePng(image)),
    region: (x: x0, y: y0, w: w, h: h),
    mask: mask,
    inkBox: inkBox,
    ink: ink,
    blurSigma: blur,
    imageWidth: image.width,
    imageHeight: image.height,
  ).toMap();
}

/// Similarity (0..1) of two glyph masks after stretching both boxes onto
/// the same grid. Used to pick the font whose rendering of the original
/// words looks most like the printed words.
double maskSimilarity({
  required Uint8List a, required int aStride, required Rect aBox,
  required Uint8List b, required int bStride, required Rect bBox,
}) {
  if (aBox.isEmpty || bBox.isEmpty) return 0;
  const gh = 20;
  final gw = (gh * aBox.width / aBox.height).round().clamp(6, 320);
  List<double> grid(Uint8List m, int stride, Rect box) {
    final out = List<double>.filled(gw * gh, 0);
    final cellW = box.width / gw;
    final cellH = box.height / gh;
    final rows = m.length ~/ stride;
    for (var gy = 0; gy < gh; gy++) {
      for (var gx = 0; gx < gw; gx++) {
        final sx0 = (box.left + gx * cellW).floor();
        final sx1 = math.max(sx0 + 1, (box.left + (gx + 1) * cellW).ceil());
        final sy0 = (box.top + gy * cellH).floor();
        final sy1 = math.max(sy0 + 1, (box.top + (gy + 1) * cellH).ceil());
        var on = 0;
        var all = 0;
        for (var y = sy0; y < sy1; y++) {
          if (y < 0 || y >= rows) continue;
          for (var x = sx0; x < sx1; x++) {
            if (x < 0 || x >= stride) continue;
            on += m[y * stride + x];
            all++;
          }
        }
        out[gy * gw + gx] = all == 0 ? 0 : on / all;
      }
    }
    return out;
  }

  final ga = grid(a, aStride, aBox);
  final gb = grid(b, bStride, bBox);
  var diff = 0.0;
  var weight = 0.0;
  for (var i = 0; i < ga.length; i++) {
    diff += (ga[i] - gb[i]).abs();
    weight += math.max(ga[i], gb[i]);
  }
  return weight == 0 ? 0 : (1 - diff / weight).clamp(0, 1).toDouble();
}

/// Left, centred or right-aligned, judged against the other lines of the
/// page (normalized boxes) and the page centre.
LineAlignment guessAlignment(Rect line, List<Rect> others) {
  const tolerance = .018;
  final lefts = others.where((o) => (o.left - line.left).abs() < tolerance);
  final rights = others.where((o) => (o.right - line.right).abs() < tolerance);
  final centred = (line.center.dx - .5).abs() < .04;
  if (rights.length > lefts.length && line.left > .35) {
    return LineAlignment.right;
  }
  if (lefts.isNotEmpty && !centred) return LineAlignment.left;
  if (centred) return LineAlignment.center;
  if (line.left > .55) return LineAlignment.right;
  return LineAlignment.left;
}
