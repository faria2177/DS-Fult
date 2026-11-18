import 'dart:collection';
import 'dart:math' as math;
import 'dart:ui';

import 'quad.dart';
import 'truncated_page.dart';

/// Sliding-window median filter with document-identity hysteresis.
///
/// Candidate observations of the same document are median-filtered and then
/// adaptively blended into a single displayed quadrilateral. In a stationary
/// scene a short robust average and the median must both disagree with the
/// displayed outline before it moves. This rejects single-frame corner noise
/// without locking out a genuinely moving page. Deliberate camera motion
/// follows with a larger adaptive blending factor. A detector can
/// briefly prefer a background rectangle when light changes: feeding that
/// outlier directly into the display would cause a jumping green box.
/// Large changes must therefore persist for [switchConfirmationFrames]
/// consistent frames before the new quad replaces the tracked document.
///
/// A short run of nulls retains the last outline; [missesBeforeReset] misses
/// clear it. If the scene continuously disagrees with the tracked quad, the
/// old outline is hidden after [maxUnmatchedFrames] so it cannot remain
/// frozen over a different object indefinitely.
class QuadSmoother {
  QuadSmoother({
    this.windowSize = 5,
    this.missesBeforeReset = 3,
    this.switchConfirmationFrames = 4,
    this.maxUnmatchedFrames = 6,
    this.switchDistanceThreshold = 0.12,
    this.truncatedPageConfirmationFactor = 6,
  })  : assert(windowSize > 0 && windowSize.isOdd,
            'windowSize should be odd for a true median'),
        assert(missesBeforeReset > 0),
        assert(switchConfirmationFrames > 0),
        assert(maxUnmatchedFrames >= switchConfirmationFrames),
        assert(switchDistanceThreshold > 0);

  final int windowSize;
  final int missesBeforeReset;
  final int switchConfirmationFrames;
  final int maxUnmatchedFrames;

  /// Maximum normalized corner displacement treated as the same document in
  /// a single frame. Quad coordinates are in the `[0, 1]` camera preview.
  final double switchDistanceThreshold;

  /// How many times longer a truncated-page challenger (see
  /// [isTruncatedPage]) must persist than an ordinary new page.
  final int truncatedPageConfirmationFactor;

  final Queue<Quad> _buffer = Queue<Quad>();
  final Queue<Quad> _challenger = Queue<Quad>();
  Quad? _tracked;
  int _consecutiveMisses = 0;
  int _unmatchedFrames = 0;
  bool _outlineSuppressed = false;

  void reset() {
    _buffer.clear();
    _challenger.clear();
    _tracked = null;
    _consecutiveMisses = 0;
    _unmatchedFrames = 0;
    _outlineSuppressed = false;
  }

  /// Add [quad] (or null for a missed frame) and return the smoothed quad.
  /// Returns null when there's not yet any data to smooth.
  Quad? add(Quad? quad) {
    if (quad == null || !_isValid(quad)) {
      _consecutiveMisses++;
      // A missing/invalid frame breaks a run of incompatible observations.
      // Otherwise several isolated chair detections, separated by genuine
      // misses, can accumulate into a false "lost document" state.
      if (!_outlineSuppressed) _unmatchedFrames = 0;
      _challenger.clear();
      if (_consecutiveMisses >= missesBeforeReset) {
        reset();
      }
      return _outlineSuppressed ? null : _tracked;
    }
    _consecutiveMisses = 0;
    if (_tracked == null) {
      _append(quad);
      _tracked = quad;
      return quad;
    }

    if (_sameDocument(_tracked!, quad)) {
      _challenger.clear();
      _unmatchedFrames = 0;
      _outlineSuppressed = false;
      _append(quad);

      final displayed = _tracked!;
      final median = _median();
      final mean = _recentMean(4);
      final rawDelta = displayed.maxCornerDistance(quad);
      final medianDelta = displayed.maxCornerDistance(median);
      final meanDelta = displayed.maxCornerDistance(mean);

      // A perfectly still sheet may produce alternating 1% corner errors
      // from auto-exposure, focus, subpixel contour fitting or faint edges.
      // The old interpolation followed those errors on every frame and the
      // green edges visibly vibrated. A genuine displacement, in contrast,
      // causes *several consecutive observations* to move their mean.
      //
      // Keep the EXACT same displayed points while the recent geometry
      // agrees within a small noise envelope. This also prevents needless
      // overlay paints and preserves the shutter's visible four corners.
      // Median protects against a one-frame spike; mean rejects alternating
      // jitter even when an odd-sized median alternates sign.
      if ((meanDelta <= .012 && medianDelta <= .014) ||
          (meanDelta <= .008 && rawDelta <= .036)) {
        return displayed;
      }

      // Once consistent movement exceeds the noise envelope, follow the
      // actual object without the long lag of a full-window median. Smaller
      // shifts are damped more strongly than large intentional movement.
      final blendRecent = rawDelta > .040 ? .76 : .46;
      final target = Quad.interpolate(median, quad, blendRecent);
      final distance = displayed.maxCornerDistance(target);
      if (distance <= .004) return displayed;
      final alpha = distance < .020 ? .30 : distance < .055 ? .53 : .74;
      _tracked = Quad.interpolate(displayed, target, alpha);
      return _tracked;
    }

    // Do not pollute the confirmed document's median with a competing quad.
    // Require consecutive *mutually matching* candidates before moving the
    // outline. This also handles a genuinely new document entering view.
    _unmatchedFrames++;
    if (_challenger.isEmpty ||
        !_sameDocument(_challenger.first, quad) ||
        !_sameDocument(_challenger.last, quad)) {
      _challenger.clear();
    }
    _challenger.addLast(quad);
    // A new rectangle that grows abruptly into the preview border is much
    // more likely to be the chair/table behind a document than the document
    // itself. It may still become the target if it remains consistent for
    // twice as many frames; legitimate page changes are not blocked forever.
    // A smaller box inside the tracked page that still runs along one of
    // its borders is the page cut short by a ruled line, not a new page.
    // It must persist much longer before it may replace the full page.
    final requiredFrames = isTruncatedPage(quad, _tracked!)
        ? switchConfirmationFrames * truncatedPageConfirmationFactor
        : _borderTakeover(quad)
        ? switchConfirmationFrames * 2
        : switchConfirmationFrames;
    if (_challenger.length >= requiredFrames) {
      final incoming = _challenger.toList();
      _buffer.clear();
      for (final candidate in incoming) {
        _append(candidate);
      }
      _tracked = _median();
      _challenger.clear();
      _unmatchedFrames = 0;
      _outlineSuppressed = false;
      return _tracked;
    }

    // Only hide a stale document when the detector has no *coherent* new
    // target. A near-border challenger intentionally needs extra confirmation
    // (often 8 frames), so the ordinary 6-frame hide threshold must not make
    // the box blink out just before that confirmation finishes.
    // Incoherent alternatives still hide the old outline promptly.
    if (_unmatchedFrames >= maxUnmatchedFrames &&
        _challenger.length < switchConfirmationFrames) {
      _outlineSuppressed = true;
      return null;
    }
    return _outlineSuppressed ? null : _tracked;
  }

  bool _isValid(Quad quad) {
    final points = quad.points;
    if (points.any((p) => !p.dx.isFinite || !p.dy.isFinite ||
        p.dx < 0 || p.dx > 1 || p.dy < 0 || p.dy > 1)) {
      return false;
    }
    if (quad.area < .008 || quad.area > .96) {
      return false;
    }
    // Camera/preview bounds are not document edges. Reject a near-full-frame
    // quadrilateral even if its four points are otherwise geometrically valid.
    if (quad.area > .53 && _nearPreviewEdgeCount(quad) >= 3) {
      return false;
    }
    // A smoothing step must never display a bow-tie or crossed corner order.
    for (var i = 0; i < points.length; i++) {
      final a = points[i];
      final b = points[(i + 1) % points.length];
      final c = points[(i + 2) % points.length];
      final cross = (b.dx - a.dx) * (c.dy - b.dy) -
          (b.dy - a.dy) * (c.dx - b.dx);
      if (cross <= .0001) {
        return false;
      }
    }
    return true;
  }

  int _nearPreviewEdgeCount(Quad quad) => quad.points.where((p) =>
      p.dx <= .022 || p.dx >= .978 || p.dy <= .022 || p.dy >= .978).length;

  bool _borderTakeover(Quad candidate) =>
      _tracked != null &&
      candidate.area > _tracked!.area * 1.35 &&
      _nearPreviewEdgeCount(candidate) >= 2;

  void _append(Quad quad) {
    _buffer.addLast(quad);
    while (_buffer.length > windowSize) {
      _buffer.removeFirst();
    }
  }

  bool _sameDocument(Quad a, Quad b) {
    final smallerArea = math.min(a.area, b.area);
    final largerArea = math.max(a.area, b.area);
    if (smallerArea < 0.001 || largerArea / smallerArea > 1.65) {
      return false;
    }
    return a.maxCornerDistance(b) <= switchDistanceThreshold;
  }

  /// Average of the most recent observations, used only to detect
  /// persistent movement (not as the visible corner coordinates). This
  /// keeps the output quiet even if a 7-sample median flips back/forth
  /// between two equally plausible subpixel paper edges.
  Quad _recentMean(int count) {
    final recent = _buffer.toList().reversed.take(count).toList();
    assert(recent.isNotEmpty);
    Offset mean(Offset Function(Quad) corner) {
      var x = 0.0;
      var y = 0.0;
      for (final observation in recent) {
        final p = corner(observation);
        x += p.dx;
        y += p.dy;
      }
      return Offset(x / recent.length, y / recent.length);
    }

    return Quad(
      topLeft: mean((q) => q.topLeft),
      topRight: mean((q) => q.topRight),
      bottomRight: mean((q) => q.bottomRight),
      bottomLeft: mean((q) => q.bottomLeft),
    );
  }

  Quad _median() {
    final items = _buffer.toList();
    Offset medianOffset(Offset Function(Quad) pick) {
      final xs = items.map((q) => pick(q).dx).toList()..sort();
      final ys = items.map((q) => pick(q).dy).toList()..sort();
      final mid = xs.length ~/ 2;
      return Offset(xs[mid], ys[mid]);
    }

    return Quad(
      topLeft: medianOffset((q) => q.topLeft),
      topRight: medianOffset((q) => q.topRight),
      bottomRight: medianOffset((q) => q.bottomRight),
      bottomLeft: medianOffset((q) => q.bottomLeft),
    );
  }
}
