import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

import 'text_style_matcher.dart';

/// Offline, OCR-assisted visual text replacement.
/// Existing glyphs are removed with a local border-colour estimate before the
/// user-supplied replacement is drawn in Flutter (supports Bengali glyphs).
/// This is not a generative inpainting model and can leave artifacts on photos.
class ImageTextProcessor {
  /// Offline brush removal for a manually marked stroke. Samples neighbouring
  /// pixels and fills only the selected stroke, never the entire bounding box.
  /// Unlike proprietary cloud inpainting, textured surfaces may show seams.
  static Future<Uint8List> eraseBrush(
    Uint8List original, {
    required List<Offset> normalizedPoints,
    required double normalizedRadius,
  }) {
    if (normalizedPoints.isEmpty) return Future.value(original);
    return compute(_eraseBrushInIsolate, {
      'bytes': original,
      'points': [for (final point in normalizedPoints) point.dx,
        for (final point in normalizedPoints) point.dy],
      'radius': normalizedRadius,
    });
  }

  static Future<Uint8List> replace(
    Uint8List original, {
    required Rect normalizedArea,
    required String replacement,
  }) async {
    final cleared = await compute(_eraseInIsolate, {
      'bytes': original,
      'area': [normalizedArea.left, normalizedArea.top,
        normalizedArea.right, normalizedArea.bottom],
    });
    if (replacement.trim().isEmpty) return cleared;

    final codec = await ui.instantiateImageCodec(cleared);
    final frame = await codec.getNextFrame();
    final image = frame.image;
    final width = image.width;
    final height = image.height;
    final rect = Rect.fromLTRB(
      normalizedArea.left * width,
      normalizedArea.top * height,
      normalizedArea.right * width,
      normalizedArea.bottom * height,
    );
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawImage(image, Offset.zero, Paint());

    var fontSize = math.max(9.0, rect.height * .78);
    late TextPainter painter;
    while (true) {
      painter = TextPainter(
        text: TextSpan(
          text: replacement,
          style: TextStyle(
            fontSize: fontSize,
            color: Colors.black87,
            fontWeight: FontWeight.w500,
            height: 1.04,
          ),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 2,
      )..layout(maxWidth: math.max(10.0, rect.width));
      if ((!painter.didExceedMaxLines && painter.height <= rect.height * 1.12) ||
          fontSize <= 9) {
        break;
      }
      fontSize *= .87;
    }
    painter.paint(canvas, Offset(rect.left, rect.top));
    final outputImage = await recorder.endRecording().toImage(width, height);
    final data = await outputImage.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    outputImage.dispose();
    codec.dispose();
    if (data == null) throw StateError('Could not render image text');
    return data.buffer.asUint8List();
  }

  /// Font families tried when matching printed text. On Android these are
  /// system aliases: Roboto, Noto Serif, condensed Roboto and a monospace
  /// face (typewriter-style forms).
  static const _families = <String?>[
    null, 'serif', 'sans-serif-condensed', 'monospace',
  ];
  static const _weights = <FontWeight>[FontWeight.w400, FontWeight.w700];

  /// Replace one recognized text line so that the edit cannot be told
  /// apart from the print around it:
  /// * only the glyph pixels are removed, the paper keeps its own grain;
  /// * the font family, weight, height and letter width are chosen by
  ///   drawing the *original* words in several fonts and keeping the one
  ///   whose shape matches the printed glyphs best;
  /// * the new words sit on the original baseline, in the darkest stroke
  ///   colour of the old words, softened like the scan;
  /// * left, centred or right alignment follows the neighbouring lines.
  static Future<Uint8List> replaceLine(
    Uint8List original, {
    required Rect normalizedArea,
    required String replacement,
    String? originalText,
    List<Rect> neighbors = const [],
  }) async {
    final analysis = LineAnalysis.fromMap(await compute(analyzeAndEraseLine, {
      'bytes': original,
      'area': [normalizedArea.left, normalizedArea.top,
        normalizedArea.right, normalizedArea.bottom],
    }));
    if (replacement.trim().isEmpty) return analysis.cleared;

    final box = analysis.inkBox;
    final sourceText = (originalText ?? '').trim();
    var best = _StyleChoice(family: null, weight: FontWeight.w400,
        sizeScale: box.height * 1.05 / 64, widthScale: 1, score: -1,
        descent: box.height * .2);
    if (sourceText.isNotEmpty && box.width > 2 && box.height > 2) {
      final r = analysis.region;
      final localBox = Rect.fromLTRB(box.left - r.x, box.top - r.y,
          box.right - r.x, box.bottom - r.y);
      for (final family in _families) {
        for (final weight in _weights) {
          final raster = await _rasterize(sourceText, family, weight, 64);
          if (raster == null) continue;
          final sy = box.height / raster.inkBox.height;
          final sx = box.width / raster.inkBox.width;
          final stretch = (math.log(sx / sy)).abs();
          if (stretch > .45) continue;
          final score = maskSimilarity(
            a: analysis.mask, aStride: r.w, aBox: localBox,
            b: raster.mask, bStride: raster.width, bBox: raster.inkBox,
          ) - stretch * .35;
          if (score > best.score) {
            best = _StyleChoice(family: family, weight: weight,
              sizeScale: sy, widthScale: sx / sy, score: score,
              descent: (raster.inkBox.bottom - raster.baseline) * sy);
          }
        }
      }
    }

    // Measure the replacement drawn in the chosen style.
    var fontSize = 64 * best.sizeScale;
    var widthScale = best.widthScale;
    final measured = await _rasterize(replacement, best.family, best.weight,
        fontSize);
    if (measured == null) return analysis.cleared;

    final pageWidth = analysis.imageWidth.toDouble();
    final normalizedBox = Rect.fromLTRB(box.left / pageWidth,
        box.top / analysis.imageHeight, box.right / pageWidth,
        box.bottom / analysis.imageHeight);
    final alignment = guessAlignment(normalizedBox, neighbors);
    final margin = pageWidth * .03;
    final maxWidth = switch (alignment) {
      LineAlignment.left => pageWidth - box.left - margin,
      LineAlignment.right => box.right - margin,
      LineAlignment.center => 2 * (math.min(box.center.dx,
          pageWidth - box.center.dx) - margin),
    };
    var inkWidth = measured.inkBox.width * widthScale;
    if (inkWidth > maxWidth && inkWidth > 0) {
      // Too long for the page: narrow the letters a little first, then
      // shrink, as a typesetter would.
      final narrow = math.max(.88, maxWidth / inkWidth);
      widthScale *= narrow;
      inkWidth *= narrow;
      if (inkWidth > maxWidth) {
        final shrink = maxWidth / inkWidth;
        fontSize *= shrink;
        inkWidth = maxWidth;
      }
    }
    final scale = fontSize / measured.fontSize;
    final inkLeft = switch (alignment) {
      LineAlignment.left => box.left,
      LineAlignment.right => box.right - inkWidth,
      LineAlignment.center => box.center.dx - inkWidth / 2,
    };
    // Original baseline: bottom of the ink minus the descent of the words.
    final baseline = box.bottom - best.descent;

    final codec = await ui.instantiateImageCodec(analysis.cleared);
    final frame = await codec.getNextFrame();
    final image = frame.image;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawImage(image, Offset.zero, Paint());
    final painter = TextPainter(
      text: TextSpan(text: replacement, style: TextStyle(
        fontFamily: best.family,
        fontWeight: best.weight,
        fontSize: fontSize,
        height: 1.0,
        foreground: Paint()
          ..color = Color.fromARGB(255, analysis.ink[0], analysis.ink[1],
              analysis.ink[2])
          ..maskFilter = MaskFilter.blur(BlurStyle.normal,
              analysis.blurSigma * .6),
      )),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    final glyphLeft = measured.inkBox.left * scale;
    final glyphBaseline = measured.baseline * scale;
    canvas.save();
    canvas.translate(inkLeft - glyphLeft * widthScale, baseline - glyphBaseline);
    canvas.scale(widthScale, 1);
    // The raster was drawn with a 2 px inset; mirror it here.
    painter.paint(canvas, Offset(_inset * scale, _inset * scale));
    canvas.restore();
    final output = await recorder.endRecording()
        .toImage(image.width, image.height);
    final data = await output.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    output.dispose();
    codec.dispose();
    if (data == null) throw StateError('Could not render image text');
    return data.buffer.asUint8List();
  }

  static const double _inset = 2;

  /// Draw [text] off-screen and return its glyph mask and metrics.
  static Future<_Raster?> _rasterize(String text, String? family,
      FontWeight weight, double fontSize) async {
    final painter = TextPainter(
      text: TextSpan(text: text, style: TextStyle(fontFamily: family,
          fontWeight: weight, fontSize: fontSize, height: 1.0,
          color: const Color(0xFF000000))),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    final width = (painter.width + _inset * 2).ceil();
    final height = (painter.height + _inset * 2).ceil();
    if (width <= 0 || height <= 0 || width * height > 12000000) return null;
    final recorder = ui.PictureRecorder();
    painter.paint(Canvas(recorder), const Offset(_inset, _inset));
    final picture = recorder.endRecording();
    final image = await picture.toImage(width, height);
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    image.dispose();
    picture.dispose();
    if (data == null) return null;
    final bytes = data.buffer.asUint8List();
    final mask = Uint8List(width * height);
    var minX = width;
    var minY = height;
    var maxX = -1;
    var maxY = -1;
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        if (bytes[(y * width + x) * 4 + 3] > 110) {
          mask[y * width + x] = 1;
          if (x < minX) minX = x;
          if (x > maxX) maxX = x;
          if (y < minY) minY = y;
          if (y > maxY) maxY = y;
        }
      }
    }
    if (maxX < 0) return null;
    return _Raster(
      mask: mask, width: width, fontSize: fontSize,
      inkBox: Rect.fromLTRB(minX.toDouble(), minY.toDouble(),
          maxX + 1.0, maxY + 1.0),
      baseline: _inset + painter.computeDistanceToActualBaseline(
          TextBaseline.alphabetic),
    );
  }

  /// Where a replacement line may be drawn. A line whose centre is close to
  /// the page centre is treated as centred text.
  @visibleForTesting
  static ({bool centered, double maxWidth}) lineLayout({
    required Rect rect, required double imageWidth}) {
    final margin = imageWidth * .03;
    final centered =
        (rect.center.dx - imageWidth / 2).abs() < imageWidth * .06;
    final maxWidth = centered
        ? 2 * (math.min(rect.center.dx, imageWidth - rect.center.dx) - margin)
        : imageWidth - rect.left - margin;
    return (centered: centered, maxWidth: math.max(rect.width, maxWidth));
  }
}

Uint8List _eraseInIsolate(Map<String, Object> options) {
  final source = img.decodeImage(options['bytes']! as Uint8List);
  if (source == null) throw const FormatException('Unsupported image');
  final image = img.bakeOrientation(source);
  final coords = options['area']! as List<double>;
  final x0 = (coords[0] * image.width).floor().clamp(0, image.width - 1);
  final y0 = (coords[1] * image.height).floor().clamp(0, image.height - 1);
  final x1 = (coords[2] * image.width).ceil().clamp(x0 + 1, image.width);
  final y1 = (coords[3] * image.height).ceil().clamp(y0 + 1, image.height);

  final xSamples = <int>[x0, (x0 + x1) ~/ 2, x1 - 1];
  final topY = math.max(0, y0 - math.max(3, (y1 - y0) ~/ 3)).toInt();
  final bottomY = math.min(image.height - 1,
      y1 + math.max(3, (y1 - y0) ~/ 3)).toInt();
  List<double> sample(int y) {
    var r = 0.0;
    var g = 0.0;
    var b = 0.0;
    for (final x in xSamples) {
      final color = image.getPixel(x, y);
      r += color.r;
      g += color.g;
      b += color.b;
    }
    return [r / xSamples.length, g / xSamples.length, b / xSamples.length];
  }

  final top = sample(topY);
  final bottom = sample(bottomY);
  for (var y = y0; y < y1; y++) {
    final t = (y - y0) / math.max(1, y1 - y0 - 1);
    final r = (top[0] * (1 - t) + bottom[0] * t).round();
    final g = (top[1] * (1 - t) + bottom[1] * t).round();
    final b = (top[2] * (1 - t) + bottom[2] * t).round();
    for (var x = x0; x < x1; x++) {
      image.setPixelRgb(x, y, r, g, b);
    }
  }
  return Uint8List.fromList(img.encodePng(image));
}

Uint8List _eraseBrushInIsolate(Map<String, Object> options) {
  final source = img.decodeImage(options['bytes']! as Uint8List);
  if (source == null) throw const FormatException('Unsupported image');
  final original = img.bakeOrientation(source);
  final result = img.Image.from(original);
  final coords = options['points']! as List<double>;
  final count = coords.length ~/ 2;
  final shortSide = math.min(result.width, result.height);
  final radius = ((options['radius']! as double) * shortSide)
      .round().clamp(2, math.max(2, shortSide ~/ 10)).toInt();

  // The input points are paired as all X values followed by all Y values.
  final centres = <math.Point<double>>[
    for (var i = 0; i < count; i++)
      math.Point(coords[i] * result.width, coords[i + count] * result.height),
  ];
  final sampled = <math.Point<double>>[];
  for (var i = 0; i < centres.length; i++) {
    final current = centres[i];
    if (i == 0) { sampled.add(current); continue; }
    final previous = centres[i - 1];
    final distance = math.sqrt(math.pow(current.x - previous.x, 2) +
        math.pow(current.y - previous.y, 2));
    final steps = math.max(1, (distance / math.max(2, radius * .6)).ceil());
    for (var k = 1; k <= steps; k++) {
      final t = k / steps;
      sampled.add(math.Point(previous.x + (current.x - previous.x) * t,
          previous.y + (current.y - previous.y) * t));
    }
  }

  for (final center in sampled) {
    final cx = center.x.round().clamp(0, result.width - 1).toInt();
    final cy = center.y.round().clamp(0, result.height - 1).toInt();
    final border = radius * 1.65;
    var red = 0.0;
    var green = 0.0;
    var blue = 0.0;
    var samples = 0;
    for (var k = 0; k < 12; k++) {
      final a = 2 * math.pi * k / 12;
      final sx = (cx + math.cos(a) * border)
          .round().clamp(0, result.width - 1).toInt();
      final sy = (cy + math.sin(a) * border)
          .round().clamp(0, result.height - 1).toInt();
      final pixel = original.getPixel(sx, sy);
      red += pixel.r;
      green += pixel.g;
      blue += pixel.b;
      samples++;
    }
    final r = (red / samples).round();
    final g = (green / samples).round();
    final b = (blue / samples).round();
    for (var y = math.max(0, cy - radius); y <= math.min(result.height - 1, cy + radius); y++) {
      for (var x = math.max(0, cx - radius); x <= math.min(result.width - 1, cx + radius); x++) {
        final dx = x - cx;
        final dy = y - cy;
        if (dx * dx + dy * dy <= radius * radius) {
          result.setPixelRgb(x, y, r, g, b);
        }
      }
    }
  }
  return Uint8List.fromList(img.encodePng(result));
}

class _Raster {
  const _Raster({required this.mask, required this.width,
    required this.inkBox, required this.baseline, required this.fontSize});
  final Uint8List mask;
  final int width;
  final Rect inkBox;
  final double baseline;
  final double fontSize;
}

class _StyleChoice {
  const _StyleChoice({required this.family, required this.weight,
    required this.sizeScale, required this.widthScale, required this.score,
    required this.descent});
  final String? family;
  final FontWeight weight;
  final double sizeScale;
  final double widthScale;
  final double score;
  final double descent;
}
