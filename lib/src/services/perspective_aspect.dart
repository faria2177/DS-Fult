import 'dart:math' as math;
import 'dart:ui';

/// Recovers a document's real width:height from its four corners in a
/// photo, so the straightened page keeps its true shape (A4 stays A4, an
/// ID card stays 85.6 x 54) even when the photo was taken at an angle.
///
/// Method: Z. Zhang and L.-W. He, "Whiteboard scanning and image
/// enhancement", Digital Signal Processing 17(2), 2007. The corners are
/// lifted to 3-D with a pinhole camera centred on the photo; the two sides'
/// true lengths then follow from the projective geometry. Averaging side
/// lengths in the photo (the previous method) squeezes the far end of a
/// tilted page by up to ~20%.
///
/// The focal length cannot be read from the corners reliably (it is
/// undefined when only one pair of sides converges and noise-sensitive
/// otherwise), so a typical phone main camera is assumed: 26 mm-equivalent,
/// about 0.75 x the photo's long side. Simulated tilted pages taken with
/// focal lengths from 0.65 x to 0.88 x keep a mean ratio error of 0.4-1.4%.
class PerspectiveAspect {
  /// Typical phone main camera, as a multiple of the photo's long side.
  static const focalScale = .75;

  /// A4/A-series, US Letter and ID-1 (bank and ID cards), width:height.
  static const standardRatios = <double>[1.41421, 1.29412, 1.58577];
  static const snapTolerance = .02;

  /// The correction never changes the naive shape by more than this factor,
  /// which keeps an odd outline (cropped screenshot, wrong camera guess)
  /// from producing a distorted page.
  static const maxChange = 1.25;

  /// Real width:height of the quadrilateral [corners] (top-left, top-right,
  /// bottom-right, bottom-left, in pixels of an image of [imageSize]), or
  /// null when the geometry is degenerate.
  static double? widthToHeight(List<Offset> corners, Size imageSize) {
    if (corners.length != 4 || imageSize.isEmpty) return null;
    final u0 = imageSize.width / 2, v0 = imageSize.height / 2;
    List<double> lift(Offset p) => [p.dx - u0, p.dy - v0, 1];
    final m1 = lift(corners[0]); // top-left
    final m2 = lift(corners[1]); // top-right: along the width
    final m4 = lift(corners[2]); // bottom-right: opposite corner
    final m3 = lift(corners[3]); // bottom-left: along the height
    final d2 = _dot(_cross(m2, m4), m3);
    final d3 = _dot(_cross(m3, m4), m2);
    if (d2.abs() < 1e-9 || d3.abs() < 1e-9) return null;
    final k2 = _dot(_cross(m1, m4), m3) / d2;
    final k3 = _dot(_cross(m1, m4), m2) / d3;
    if (!k2.isFinite || !k3.isFinite || k2 <= 0 || k3 <= 0) return null;
    final n2 = [for (var i = 0; i < 3; i++) k2 * m2[i] - m1[i]];
    final n3 = [for (var i = 0; i < 3; i++) k3 * m3[i] - m1[i]];
    final f = focalScale * math.max(imageSize.width, imageSize.height);
    final f2 = f * f;
    final width2 = (n2[0] * n2[0] + n2[1] * n2[1]) / f2 + n2[2] * n2[2];
    final height2 = (n3[0] * n3[0] + n3[1] * n3[1]) / f2 + n3[2] * n3[2];
    if (width2 <= 0 || height2 <= 0) return null;
    final ratio = math.sqrt(width2 / height2);
    return ratio.isFinite && ratio > 0 ? ratio : null;
  }

  /// Output size for straightening [corners]. [naiveWidth] x [naiveHeight]
  /// is the size the caller would otherwise use; the result keeps its area
  /// (so resolution is unchanged) and takes the corrected proportions.
  static Size outputSize(List<Offset> corners, Size imageSize,
      double naiveWidth, double naiveHeight) {
    if (naiveWidth <= 0 || naiveHeight <= 0) {
      return Size(naiveWidth, naiveHeight);
    }
    final naive = naiveWidth / naiveHeight;
    final estimated = widthToHeight(corners, imageSize);
    if (estimated == null) return Size(naiveWidth, naiveHeight);
    var ratio = estimated.clamp(naive / maxChange, naive * maxChange).toDouble();
    ratio = snapToStandard(ratio);
    final area = naiveWidth * naiveHeight;
    return Size(math.sqrt(area * ratio), math.sqrt(area / ratio));
  }

  /// Snaps to a common paper or card shape (either orientation) within
  /// [snapTolerance], removing the last few percent of estimation error.
  static double snapToStandard(double ratio) {
    for (final standard in standardRatios) {
      for (final candidate in [standard, 1 / standard]) {
        if ((ratio / candidate - 1).abs() <= snapTolerance) return candidate;
      }
    }
    return ratio;
  }

  static List<double> _cross(List<double> a, List<double> b) => [
    a[1] * b[2] - a[2] * b[1],
    a[2] * b[0] - a[0] * b[2],
    a[0] * b[1] - a[1] * b[0],
  ];

  static double _dot(List<double> a, List<double> b) =>
      a[0] * b[0] + a[1] * b[1] + a[2] * b[2];
}
