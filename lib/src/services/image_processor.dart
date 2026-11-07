import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

enum ScanFilter {
  original, auto, enhance, shadowFree, magicColor, grayscale, blackWhite,
  lighten, noWatermark, noHandwriting, eco, invert,
}

extension ScanFilterName on ScanFilter {
  String get label => switch (this) {
        ScanFilter.original => 'Original',
        ScanFilter.auto => 'Auto',
        ScanFilter.enhance => 'Enhance',
        ScanFilter.shadowFree => 'Shadow Free',
        ScanFilter.magicColor => 'Magic Color',
        ScanFilter.grayscale => 'Grayscale',
        ScanFilter.blackWhite => 'B&W',
        ScanFilter.lighten => 'Lighten',
        ScanFilter.noWatermark => 'No Watermark (experimental)',
        ScanFilter.noHandwriting => 'No Handwriting (experimental)',
        ScanFilter.eco => 'Eco',
        ScanFilter.invert => 'Invert',
      };
}

/// Order is top-left, top-right, bottom-right, bottom-left.
class CropQuad {
  CropQuad(this.corners) : assert(corners.length == 4);

  final List<Offset> corners;

  /// Prevent collapsed, crossed or self-intersecting handles from producing
  /// inverted or severely distorted perspective crops. Coordinates are
  /// normalized and ordered TL, TR, BR, BL.
  bool get isValid {
    if (corners.length != 4) return false;
    for (final point in corners) {
      if (!point.dx.isFinite || !point.dy.isFinite ||
          point.dx < 0 || point.dx > 1 ||
          point.dy < 0 || point.dy > 1) {
        return false;
      }
    }
    var areaTwice = 0.0;
    double? sign;
    for (var i = 0; i < 4; i++) {
      final a = corners[i];
      final b = corners[(i + 1) % 4];
      final c = corners[(i + 2) % 4];
      if ((a - b).distance < .025) return false;
      areaTwice += a.dx * b.dy - b.dx * a.dy;
      final ab = b - a;
      final bc = c - b;
      final cross = ab.dx * bc.dy - ab.dy * bc.dx;
      if (cross.abs() < 1e-5) return false;
      final nextSign = cross.sign;
      if (sign != null && nextSign != sign) return false;
      sign = nextSign;
    }
    return areaTwice.abs() / 2 >= .015;
  }

  factory CropQuad.inset() => CropQuad(const [
        Offset(.05, .05),
        Offset(.95, .05),
        Offset(.95, .95),
        Offset(.05, .95),
      ]);

  List<List<double>> toData() =>
      corners.map((point) => [point.dx, point.dy]).toList(growable: false);
}

class ImageProcessor {
  /// Original files stay untouched; transforms always return a new JPEG.
  static Future<Uint8List> process(
    Uint8List source, {
    CropQuad? crop,
    ScanFilter filter = ScanFilter.original,
    int rotateDegrees = 0,
  }) async {
    if (crop == null && filter == ScanFilter.original && rotateDegrees == 0) {
      return source;
    }
    return compute(_processInIsolate, {
      'bytes': source,
      'crop': crop?.toData(),
      'filter': filter.name,
      'rotate': rotateDegrees,
    });
  }
}

Uint8List _processInIsolate(Map<String, dynamic> options) {
  final decoded = img.decodeImage(options['bytes'] as Uint8List);
  if (decoded == null) throw const FormatException('Unsupported image');
  var image = img.bakeOrientation(decoded);
  final crop = options['crop'] as List<List<double>>?;
  if (crop != null) {
    final quad = CropQuad(crop.map((p) => Offset(p[0], p[1])).toList());
    if (!quad.isValid) {
      throw const FormatException('Invalid document corners. Adjust all four corners.');
    }
    image = _perspectiveCrop(image, crop);
  }
  final rotation = options['rotate'] as int;
  if (rotation % 360 != 0) {
    image = img.copyRotate(image, angle: rotation.toDouble());
  }
  final filter = ScanFilter.values.byName(options['filter'] as String);
  if (filter != ScanFilter.original) image = _filterImage(image, filter);
  return Uint8List.fromList(img.encodeJpg(image, quality: 94));
}

img.Image _filterImage(img.Image input, ScanFilter filter) {
  final image = img.Image.from(input);
  final histogram = List<int>.filled(256, 0);
  for (var y = 0; y < image.height; y += 4) {
    for (var x = 0; x < image.width; x += 4) {
      final pixel = image.getPixel(x, y);
      final light = _luma(pixel.r.toDouble(), pixel.g.toDouble(), pixel.b.toDouble());
      histogram[light.round().clamp(0, 255).toInt()]++;
    }
  }
  final bright = _percentile(histogram, 0.90);
  final gain = (245.0 / math.max(bright, 95)).clamp(1.0, 1.65);
  final backgroundLift = (244.0 - bright * gain).clamp(0.0, 65.0);
  final otsu = _otsu(histogram);
  // Estimate illumination over regions instead of assuming the whole page is
  // lit uniformly. This avoids dark corners when a phone shadows the paper.
  final background = _illuminationGrid(image);

  for (var y = 0; y < image.height; y++) {
    for (var x = 0; x < image.width; x++) {
      final pixel = image.getPixel(x, y);
      final r = pixel.r.toDouble();
      final g = pixel.g.toDouble();
      final b = pixel.b.toDouble();
      final lum = _luma(r, g, b);
      final localPaper = background.at(x, y).clamp(85.0, 255.0);
      final flattenGain = (248.0 / localPaper).clamp(.90, 2.20);
      switch (filter) {
        case ScanFilter.original:
          break;
        case ScanFilter.auto:
        case ScanFilter.enhance:
          final blend = filter == ScanFilter.auto ? .48 : .68;
          final relativePaper = (lum / math.max(1, localPaper)).clamp(0.0, 1.0);
          final lift = backgroundLift * relativePaper * relativePaper * .08;
          // Do not turn a dark coloured surface behind a blank ID card into
          // bright paper. Reserve strong illumination flattening for the
          // explicit No Shadow preset.
          final safeFlatten = flattenGain.clamp(.90, 1.35);
          final scale = 1 + (safeFlatten - 1) * blend;
          image.setPixelRgb(
            x,
            y,
            _byte(r * scale + lift),
            _byte(g * scale + lift),
            _byte(b * scale + lift),
          );
        case ScanFilter.shadowFree:
          image.setPixelRgb(
            x, y,
            _byte(r * flattenGain),
            _byte(g * flattenGain),
            _byte(b * flattenGain),
          );
        case ScanFilter.magicColor:
          final boostedLum = (lum * gain).clamp(0.0, 255.0);
          const saturation = 1.13;
          image.setPixelRgb(
            x, y,
            _byte(boostedLum + (r - lum) * saturation),
            _byte(boostedLum + (g - lum) * saturation),
            _byte(boostedLum + (b - lum) * saturation),
          );
        case ScanFilter.grayscale:
          final gray = _byte(lum * gain);
          image.setPixelRgb(x, y, gray, gray, gray);
        case ScanFilter.blackWhite:
          final threshold = math.max(otsu * .75, localPaper - 24);
          final value = lum >= threshold ? 255 : 0;
          image.setPixelRgb(x, y, value, value, value);
        case ScanFilter.lighten:
          // Preserve dark strokes instead of stretching the highlights to pure white.
          image.setPixelRgb(x, y, _byte(r * .94 + 20),
            _byte(g * .94 + 20), _byte(b * .94 + 20));
        case ScanFilter.noWatermark:
          // Best-effort faint-background cleaning. This is NOT a generic AI
          // logo/text remover; dark ink and prominent watermarks remain.
          final tint = math.max(r, math.max(g, b)) - math.min(r, math.min(g, b));
          final closeToPaper = (localPaper - lum).abs() < 22 && tint < 35;
          final cleaned = closeToPaper ? _byte(localPaper) : null;
          image.setPixelRgb(x, y,
            cleaned ?? _byte(r), cleaned ?? _byte(g), cleaned ?? _byte(b));
        case ScanFilter.noHandwriting:
          // Removes saturated coloured pen strokes on a light page. A fully
          // accurate handwriting/print distinction requires a segmentation model.
          final tint = math.max(r, math.max(g, b)) - math.min(r, math.min(g, b));
          final colouredInk = tint > 58 && lum < 195 && localPaper > 155;
          final paper = _byte(localPaper);
          image.setPixelRgb(x, y,
            colouredInk ? paper : _byte(r),
            colouredInk ? paper : _byte(g),
            colouredInk ? paper : _byte(b));
        case ScanFilter.eco:
          // Toner-saving monochrome: keep only strong strokes, leave a clean
          // white background and use dark grey rather than full black.
          final ink = lum < math.min(otsu, localPaper - 40);
          final value = ink ? 45 : 255;
          image.setPixelRgb(x, y, value, value, value);
        case ScanFilter.invert:
          image.setPixelRgb(x, y, _byte(255 - r),
            _byte(255 - g), _byte(255 - b));
      }
    }
  }
  return image;
}

class _IlluminationGrid {
  _IlluminationGrid(this.values, this.columns, this.rows, this.cell);
  final List<double> values;
  final int columns;
  final int rows;
  final int cell;

  double at(int x, int y) {
    final gx = (x / cell - .5).clamp(0.0, (columns - 1).toDouble());
    final gy = (y / cell - .5).clamp(0.0, (rows - 1).toDouble());
    final x0 = gx.floor();
    final y0 = gy.floor();
    final x1 = math.min(columns - 1, x0 + 1);
    final y1 = math.min(rows - 1, y0 + 1);
    final fx = gx - x0;
    final fy = gy - y0;
    final top = values[y0 * columns + x0] * (1 - fx) +
        values[y0 * columns + x1] * fx;
    final bottom = values[y1 * columns + x0] * (1 - fx) +
        values[y1 * columns + x1] * fx;
    return top * (1 - fy) + bottom * fy;
  }
}

_IlluminationGrid _illuminationGrid(img.Image image) {
  final cell = math.max(24, math.min(image.width, image.height) ~/ 16);
  final columns = (image.width / cell).ceil();
  final rows = (image.height / cell).ceil();
  final sums = List<double>.filled(columns * rows, 0);
  final counts = List<int>.filled(columns * rows, 0);
  for (var y = 0; y < image.height; y += 3) {
    for (var x = 0; x < image.width; x += 3) {
      final pixel = image.getPixel(x, y);
      final index = (y ~/ cell) * columns + x ~/ cell;
      sums[index] += _luma(pixel.r.toDouble(), pixel.g.toDouble(), pixel.b.toDouble());
      counts[index]++;
    }
  }
  final means = List<double>.generate(sums.length,
      (i) => counts[i] == 0 ? 240 : sums[i] / counts[i]);
  final smoothed = List<double>.filled(sums.length, 0);
  for (var y = 0; y < rows; y++) {
    for (var x = 0; x < columns; x++) {
      var sum = 0.0;
      var weight = 0.0;
      for (var dy = -2; dy <= 2; dy++) {
        for (var dx = -2; dx <= 2; dx++) {
          final yy = y + dy;
          final xx = x + dx;
          if (xx < 0 || yy < 0 || xx >= columns || yy >= rows) continue;
          final w = 1.0 / (1 + dx * dx + dy * dy);
          sum += means[yy * columns + xx] * w;
          weight += w;
        }
      }
      smoothed[y * columns + x] = sum / weight;
    }
  }
  return _IlluminationGrid(smoothed, columns, rows, cell);
}

int _byte(num value) => value.round().clamp(0, 255).toInt();

double _luma(double r, double g, double b) => r * .299 + g * .587 + b * .114;

int _percentile(List<int> histogram, double fraction) {
  final total = histogram.fold<int>(0, (a, b) => a + b);
  final target = total * fraction;
  var count = 0;
  for (var value = 0; value < 256; value++) {
    count += histogram[value];
    if (count >= target) return value;
  }
  return 255;
}

int _otsu(List<int> histogram) {
  final total = histogram.fold<int>(0, (a, b) => a + b);
  if (total == 0) return 127;
  var sum = 0.0;
  for (var i = 0; i < 256; i++) {
    sum += i * histogram[i];
  }
  var backCount = 0;
  var backSum = 0.0;
  var best = -1.0;
  var threshold = 127;
  for (var i = 0; i < 256; i++) {
    backCount += histogram[i];
    if (backCount == 0) continue;
    final frontCount = total - backCount;
    if (frontCount == 0) break;
    backSum += i * histogram[i];
    final d = backSum / backCount - (sum - backSum) / frontCount;
    final variance = backCount * frontCount * d * d;
    if (variance > best) {
      best = variance;
      threshold = i;
    }
  }
  return threshold;
}

img.Image _perspectiveCrop(img.Image source, List<List<double>> normalized) {
  final points = normalized
      .map((p) => Offset(
            p[0].clamp(0.0, 1.0) * (source.width - 1),
            p[1].clamp(0.0, 1.0) * (source.height - 1),
          ))
      .toList(growable: false);
  double distance(Offset a, Offset b) => (a - b).distance;
  int width = ((distance(points[0], points[1]) +
              distance(points[3], points[2])) /
          2)
      .round()
      .clamp(80, 4096).toInt();
  int height = ((distance(points[0], points[3]) +
              distance(points[1], points[2])) /
          2)
      .round()
      .clamp(80, 4096).toInt();
  final scale = math.min(1.0, 4096.0 / math.max(width, height));
  width = (width * scale).round().clamp(80, 4096).toInt();
  height = (height * scale).round().clamp(80, 4096).toInt();

  final corners = [
    Offset.zero,
    Offset((width - 1).toDouble(), 0),
    Offset((width - 1).toDouble(), (height - 1).toDouble()),
    Offset(0, (height - 1).toDouble()),
  ];
  final h = _homography(corners, points);
  final result = img.Image(width: width, height: height);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final denom = h[6] * x + h[7] * y + 1;
      if (denom.abs() < 1e-6) continue;
      final sx = ((h[0] * x + h[1] * y + h[2]) / denom)
          .clamp(0.0, (source.width - 1).toDouble());
      final sy = ((h[3] * x + h[4] * y + h[5]) / denom)
          .clamp(0.0, (source.height - 1).toDouble());
      final x0 = sx.floor();
      final y0 = sy.floor();
      final x1 = math.min(x0 + 1, source.width - 1);
      final y1 = math.min(y0 + 1, source.height - 1);
      final dx = sx - x0;
      final dy = sy - y0;
      final a = source.getPixel(x0, y0);
      final b = source.getPixel(x1, y0);
      final c = source.getPixel(x0, y1);
      final d = source.getPixel(x1, y1);
      double mix(num p, num q, num r, num s) =>
          (p * (1 - dx) + q * dx) * (1 - dy) +
          (r * (1 - dx) + s * dx) * dy;
      result.setPixelRgb(
        x, y,
        _byte(mix(a.r, b.r, c.r, d.r)),
        _byte(mix(a.g, b.g, c.g, d.g)),
        _byte(mix(a.b, b.b, c.b, d.b)),
      );
    }
  }
  return result;
}

/// Solve a 3x3 projective transform (destination pixels -> source pixels).
List<double> _homography(List<Offset> target, List<Offset> source) {
  final matrix = List.generate(8, (_) => List<double>.filled(9, 0));
  for (var i = 0; i < 4; i++) {
    final x = target[i].dx;
    final y = target[i].dy;
    final u = source[i].dx;
    final v = source[i].dy;
    matrix[2 * i].setRange(0, 9, [x, y, 1, 0, 0, 0, -x * u, -y * u, u]);
    matrix[2 * i + 1]
        .setRange(0, 9, [0, 0, 0, x, y, 1, -x * v, -y * v, v]);
  }
  for (var col = 0; col < 8; col++) {
    var pivot = col;
    for (var row = col + 1; row < 8; row++) {
      if (matrix[row][col].abs() > matrix[pivot][col].abs()) pivot = row;
    }
    if (matrix[pivot][col].abs() < 1e-9) {
      throw const FormatException('Invalid crop quadrilateral');
    }
    final temp = matrix[col];
    matrix[col] = matrix[pivot];
    matrix[pivot] = temp;
    final divisor = matrix[col][col];
    for (var j = col; j < 9; j++) {
      matrix[col][j] /= divisor;
    }
    for (var row = 0; row < 8; row++) {
      if (row == col) continue;
      final factor = matrix[row][col];
      for (var j = col; j < 9; j++) {
        matrix[row][j] -= factor * matrix[col][j];
      }
    }
  }
  return List.generate(8, (i) => matrix[i][8]);
}
