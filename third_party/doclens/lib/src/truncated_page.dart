import 'dart:math' as math;
import 'dart:ui';

import 'quad.dart';

/// True when [inner] looks like [outer] cut short by a line printed on the
/// page itself: a ruled line, a table border or a margin line.
///
/// On lined notebook paper the live detector sometimes swaps the real page
/// border for a ruled line a third of the way up. The result is a smaller
/// box that lies inside the page and still runs along at least one of the
/// page's real borders. A separate small document lying on a bigger one
/// (an ID card on a sheet) shares no border with it and is *not* matched.
bool isTruncatedPage(Quad inner, Quad outer, {
  double tolerance = .04,
  double maxAreaRatio = .85,
}) {
  if (outer.area <= 0 || inner.area >= outer.area * maxAreaRatio) {
    return false;
  }
  final margin = tolerance * 1.5;
  if (!inner.points.every((p) => _insideOrNear(outer, p, margin))) {
    return false;
  }
  final a = inner.points;
  final b = outer.points;
  for (var i = 0; i < 4; i++) {
    final j = (i + 1) % 4;
    if (_lineDistance(a[i], b[i], b[j]) <= tolerance &&
        _lineDistance(a[j], b[i], b[j]) <= tolerance) {
      return true;
    }
  }
  return false;
}

bool _insideOrNear(Quad outer, Offset p, double margin) {
  if (outer.contains(p)) return true;
  final q = outer.points;
  var nearest = double.infinity;
  for (var i = 0; i < 4; i++) {
    nearest = math.min(nearest, _segmentDistance(p, q[i], q[(i + 1) % 4]));
  }
  return nearest <= margin;
}

/// Distance from [p] to the infinite line through [a] and [b].
double _lineDistance(Offset p, Offset a, Offset b) {
  final ab = b - a;
  final length = ab.distance;
  if (length == 0) return (p - a).distance;
  final ap = p - a;
  return (ab.dx * ap.dy - ab.dy * ap.dx).abs() / length;
}

double _segmentDistance(Offset p, Offset a, Offset b) {
  final ab = b - a;
  final len2 = ab.distanceSquared;
  final t = len2 == 0 ? 0.0
      : ((p - a).dx * ab.dx + (p - a).dy * ab.dy) / len2;
  return (a + ab * t.clamp(0.0, 1.0).toDouble() - p).distance;
}
