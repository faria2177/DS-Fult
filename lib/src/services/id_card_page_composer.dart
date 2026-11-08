import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

/// Renders a front/back pair onto one white A4 sheet. The page is stored as a
/// single image so the document grid, image share, and PDF agree on page count.
class IdCardPageComposer {
  static const pageWidth = 1240;
  static const pageHeight = 1754;

  static Future<Uint8List> compose(List<Uint8List> sides,
      {bool compact = false}) =>
      compute(composeSync, (sides: sides, compact: compact));

  @visibleForTesting
  static Uint8List composeSync(({List<Uint8List> sides, bool compact}) input) {
    final sides = input.sides;
    if (sides.length != 2) {
      throw ArgumentError('A two-sided card requires Front and Back images.');
    }
    final paper = img.Image(width: pageWidth, height: pageHeight);
    img.fill(paper, color: img.ColorRgb8(255, 255, 255));
    final maxWidth = input.compact ? 865 : 1050;
    final maxHeight = input.compact ? 355 : 435;
    final centersY = input.compact ? [680, 1080] : [565, 1190];

    for (var i = 0; i < sides.length; i++) {
      final image = img.decodeImage(sides[i]);
      if (image == null) {
        throw const FormatException('Could not read a card side.');
      }
      final upright = img.bakeOrientation(image);
      final scale = math.min(maxWidth / upright.width,
          maxHeight / upright.height);
      final resized = img.copyResize(upright,
        width: math.max(1, (upright.width * scale).round()),
        height: math.max(1, (upright.height * scale).round()),
      );
      img.compositeImage(paper, resized,
        dstX: (pageWidth - resized.width) ~/ 2,
        dstY: centersY[i] - resized.height ~/ 2,
      );
    }
    return Uint8List.fromList(img.encodeJpg(paper, quality: 94));
  }

  /// Stamps text on the exported image itself, so Image/PDF shares match.
  static Future<Uint8List> withWatermark(Uint8List source, String label) =>
      compute(_stamp, (source: source, label: label));

  static Uint8List _stamp(({Uint8List source, String label}) input) {
    final decoded = img.decodeImage(input.source);
    if (decoded == null) throw const FormatException('Unsupported page image');
    final upright = img.bakeOrientation(decoded);
    final label = input.label.trim();
    if (label.isEmpty) return input.source;
    img.drawString(upright, label, font: img.arial24,
      x: math.max(12, (upright.width - label.length * 14) ~/ 2),
      y: upright.height - 110,
      color: img.ColorRgb8(140, 140, 140));
    return Uint8List.fromList(img.encodeJpg(upright, quality: 94));
  }
}
