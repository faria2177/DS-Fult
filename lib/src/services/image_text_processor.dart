import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

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
