import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

enum PhotoSizePreset {
  mm35x45('35 × 45 mm', 35, 45),
  inch2x2('2 × 2 inch', 50.8, 50.8),
  mm30x40('30 × 40 mm', 30, 40),
  mm40x60('40 × 60 mm', 40, 60),
  mm50x50('50 × 50 mm', 50, 50);

  const PhotoSizePreset(this.label, this.widthMm, this.heightMm);
  final String label;
  final double widthMm;
  final double heightMm;

  int widthPixels({int dpi = 300}) => (widthMm * dpi / 25.4).round();
  int heightPixels({int dpi = 300}) => (heightMm * dpi / 25.4).round();
}

enum PhotoBackdrop {
  original('Original', null),
  transparent('Transparent', null),
  white('White', 0xFFFFFFFF),
  lightBlue('Blue', 0xFF4D9AD8),
  red('Red', 0xFFDF444A);

  const PhotoBackdrop(this.label, this.argb);
  final String label;
  final int? argb;
}

/// Offline photo tools. Processing is intentionally pixel-based, not
/// generative person segmentation. For BG removal a reasonably uniform,
/// edge-connected studio background is required.
class PhotoStudioOperations {
  PhotoStudioOperations._();

  static List<int> dimensions(Uint8List bytes) {
    final image = _decode(bytes);
    return [image.width, image.height];
  }

  static img.Image _decode(Uint8List bytes) {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) {
      throw const FormatException('Unsupported or damaged image');
    }
    return img.bakeOrientation(decoded);
  }

  @visibleForTesting
  static Uint8List resizeBytes(
    Uint8List bytes, {
    required int width,
    required int height,
    int quality = 90,
    bool png = false,
  }) {
    if (width < 32 || height < 32 ||
        width > 8192 || height > 8192 || width * height > 32000000) {
      throw const FormatException('Choose 32–8192 px and at most 32 MP.');
    }
    final source = _decode(bytes);
    final resized = img.copyResize(source,
      width: width, height: height, interpolation: img.Interpolation.cubic);
    return Uint8List.fromList(png
        ? img.encodePng(resized)
        : img.encodeJpg(resized, quality: quality.clamp(40, 100)));
  }

  @visibleForTesting
  static Uint8List removeBackgroundBytes(
    Uint8List bytes, {
    int tolerance = 45,
    int feather = 1,
    int? replacementArgb,
  }) {
    var source = _decode(bytes);
    final longest = math.max(source.width, source.height);
    if (longest > 1800) {
      source = img.copyResize(source,
        width: source.width >= source.height ? 1800 : null,
        height: source.height > source.width ? 1800 : null,
        interpolation: img.Interpolation.average);
    }
    final width = source.width;
    final height = source.height;
    final corners = [
      source.getPixel(0, 0),
      source.getPixel(width - 1, 0),
      source.getPixel(0, height - 1),
      source.getPixel(width - 1, height - 1),
    ];
    int difference(img.Pixel a, img.Pixel b) {
      final dr = a.r.toInt() - b.r.toInt();
      final dg = a.g.toInt() - b.g.toInt();
      final db = a.b.toInt() - b.b.toInt();
      return dr * dr + dg * dg + db * db;
    }

    // A robust corner medoid avoids choosing a subject colour when one
    // corner is partially blocked by hair or clothing.
    var chosen = corners.first;
    var lowest = 1 << 62;
    for (final candidate in corners) {
      final score = corners.fold<int>(0,
          (sum, other) => sum + difference(candidate, other));
      if (score < lowest) {
        lowest = score;
        chosen = candidate;
      }
    }

    final threshold = tolerance.clamp(8, 120);
    final maxDifference = threshold * threshold * 3;
    final length = width * height;
    final removed = Uint8List(length);
    final queue = Int32List(length);
    var tail = 0;
    var head = 0;

    void addIfBackground(int x, int y) {
      final index = y * width + x;
      if (removed[index] != 0) return;
      if (difference(source.getPixel(x, y), chosen) > maxDifference) return;
      removed[index] = 1;
      queue[tail++] = index;
    }

    for (var x = 0; x < width; x++) {
      addIfBackground(x, 0);
      addIfBackground(x, height - 1);
    }
    for (var y = 0; y < height; y++) {
      addIfBackground(0, y);
      addIfBackground(width - 1, y);
    }
    while (head < tail) {
      final index = queue[head++];
      final x = index % width;
      final y = index ~/ width;
      if (x > 0) addIfBackground(x - 1, y);
      if (x + 1 < width) addIfBackground(x + 1, y);
      if (y > 0) addIfBackground(x, y - 1);
      if (y + 1 < height) addIfBackground(x, y + 1);
    }

    final output = img.Image(width: width, height: height, numChannels: 4);
    final background = replacementArgb;
    final rr = background == null ? 0 : (background >> 16) & 0xFF;
    final rg = background == null ? 0 : (background >> 8) & 0xFF;
    final rb = background == null ? 0 : background & 0xFF;
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final index = y * width + x;
        if (removed[index] != 0) {
          output.setPixelRgba(x, y, rr, rg, rb, background == null ? 0 : 255);
          continue;
        }
        final pixel = source.getPixel(x, y);
        var alpha = pixel.a.toInt();
        if (background == null && feather > 0) {
          var adjacent = false;
          for (var dy = -1; dy <= 1 && !adjacent; dy++) {
            for (var dx = -1; dx <= 1; dx++) {
              final nx = x + dx;
              final ny = y + dy;
              if (nx >= 0 && nx < width && ny >= 0 && ny < height &&
                  removed[ny * width + nx] != 0) {
                adjacent = true;
                break;
              }
            }
          }
          if (adjacent) alpha = (alpha * .78).round();
        }
        output.setPixelRgba(x, y,
          pixel.r.toInt(), pixel.g.toInt(), pixel.b.toInt(), alpha);
      }
    }
    return Uint8List.fromList(img.encodePng(output));
  }

  @visibleForTesting
  static Uint8List passportBytes(
    Uint8List bytes, {
    required PhotoSizePreset size,
    double zoom = 1,
    double horizontalShift = 0,
    double verticalShift = 0,
    PhotoBackdrop backdrop = PhotoBackdrop.original,
    int tolerance = 45,
  }) {
    if (backdrop == PhotoBackdrop.transparent) {
      throw const FormatException('Passport images require a solid background.');
    }
    final processed = backdrop == PhotoBackdrop.original
        ? bytes
        : removeBackgroundBytes(bytes,
            tolerance: tolerance, replacementArgb: backdrop.argb);
    final source = _decode(processed);
    final targetWidth = size.widthPixels();
    final targetHeight = size.heightPixels();
    final ratio = targetWidth / targetHeight;
    var cropWidth = math.min(source.width.toDouble(), source.height * ratio);
    var cropHeight = cropWidth / ratio;
    final factor = zoom.clamp(1.0, 3.0);
    cropWidth /= factor;
    cropHeight /= factor;
    final cx = source.width / 2 +
        horizontalShift.clamp(-1.0, 1.0) * (source.width - cropWidth) / 2;
    final cy = source.height / 2 +
        verticalShift.clamp(-1.0, 1.0) * (source.height - cropHeight) / 2;
    final w = math.max(1, cropWidth.round());
    final h = math.max(1, cropHeight.round());
    final x = (cx - w / 2).round().clamp(0, source.width - w).toInt();
    final y = (cy - h / 2).round().clamp(0, source.height - h).toInt();
    final cropped = img.copyCrop(source, x: x, y: y, width: w, height: h);
    final resized = img.copyResize(cropped,
      width: targetWidth, height: targetHeight,
      interpolation: img.Interpolation.cubic);
    return Uint8List.fromList(img.encodeJpg(resized, quality: 95));
  }

  static int sheetCapacity(PhotoSizePreset size) {
    const margin = 32;
    const spacing = 20;
    final across = ((1200 - 2 * margin + spacing) /
        (size.widthPixels() + spacing)).floor();
    final down = ((1800 - 2 * margin + spacing) /
        (size.heightPixels() + spacing)).floor();
    return math.max(1, across * down);
  }

  @visibleForTesting
  static Uint8List passportSheetBytes(
    Uint8List singleImage, {
    required int copies,
  }) {
    final photo = _decode(singleImage);
    const margin = 32;
    const spacing = 20;
    final columns = ((1200 - 2 * margin + spacing) /
        (photo.width + spacing)).floor();
    final rows = ((1800 - 2 * margin + spacing) /
        (photo.height + spacing)).floor();
    if (columns < 1 || rows < 1 || copies < 1 || copies > columns * rows) {
      throw const FormatException('Too many photos for a 4×6 inch sheet.');
    }
    final page = img.Image(width: 1200, height: 1800);
    img.fill(page, color: img.ColorRgb8(255, 255, 255));
    for (var i = 0; i < copies; i++) {
      final column = i % columns;
      final row = i ~/ columns;
      final left = margin + column * (photo.width + spacing);
      final top = margin + row * (photo.height + spacing);
      img.compositeImage(page, photo, dstX: left, dstY: top);
    }
    return Uint8List.fromList(img.encodeJpg(page, quality: 95));
  }

  /// Use with Flutter's [compute] so decode, flood-fill and encoding never
  /// block the camera/editor UI isolate.
  static Uint8List process(Map<String, Object?> args) {
    final bytes = args['bytes']! as Uint8List;
    return switch (args['mode']) {
      'remove' => removeBackgroundBytes(bytes,
          tolerance: args['tolerance']! as int,
          replacementArgb: args['background'] as int?),
      'resize' => resizeBytes(bytes,
          width: args['width']! as int,
          height: args['height']! as int,
          quality: args['quality']! as int,
          png: args['png']! as bool),
      'passport' => passportBytes(bytes,
          size: PhotoSizePreset.values[args['size']! as int],
          zoom: args['zoom']! as double,
          horizontalShift: args['horizontalShift']! as double,
          verticalShift: args['verticalShift']! as double,
          backdrop: PhotoBackdrop.values[args['backdrop']! as int],
          tolerance: args['tolerance']! as int),
      _ => throw const FormatException('Unknown image tool'),
    };
  }

  static Uint8List makeSheet(Map<String, Object?> args) =>
      passportSheetBytes(args['bytes']! as Uint8List,
          copies: args['copies']! as int);
}
