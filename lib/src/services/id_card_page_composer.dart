import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

/// Renders a front/back pair onto one white A4 sheet. The page is stored as a
/// single image so the document grid, image share, and PDF agree on page count.
class IdCardPageComposer {
  static const pageWidth = 1240;
  static const pageHeight = 1754;

  // Reference A4 portrait layout: the card width is about 48% of the page
  // and the two sides sit at 32% and 68% of its height. Keep the editor
  // preview and exported raster driven by these same measurements.
  static double cardWidthFraction({bool compact = false}) =>
      (compact ? 565 : 600) / pageWidth;
  static double cardHeightFraction({bool compact = false}) =>
      (compact ? 355 : 380) / pageHeight;
  static List<double> cardCenterFractions({bool compact = false}) =>
      compact ? const [680 / pageHeight, 1080 / pageHeight]
              : const [565 / pageHeight, 1190 / pageHeight];

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
    // Match the print scale of a real card on an A4 page (roughly 86/210 of
    // the paper width), with a little margin for cards of other proportions.
    final maxWidth = input.compact ? 565 : 600;
    final maxHeight = input.compact ? 355 : 380;
    final centersY = input.compact ? [680, 1080] : [565, 1190];

    for (var i = 0; i < sides.length; i++) {
      final image = img.decodeImage(sides[i]);
      if (image == null) {
        throw const FormatException('Could not read a card side.');
      }
      final upright = img.bakeOrientation(image);
      // A camera or gallery may return the same landscape ID/Bank card
      // rotated by 90 degrees. Normalize only the *copy* placed on A4:
      // never mutate or discard the original source/edited side.
      // Portrait-shaped side images are turned to landscape so a pair
      // cannot print as two tiny vertical strips (video 382719.mp4).
      final placed = upright.height > upright.width
          ? img.copyRotate(upright, angle: 90)
          : upright;
      final scale = math.min(maxWidth / placed.width,
          maxHeight / placed.height);
      final resized = img.copyResize(placed,
        width: math.max(1, (placed.width * scale).round()),
        height: math.max(1, (placed.height * scale).round()),
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
