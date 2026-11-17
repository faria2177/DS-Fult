import 'dart:collection';
import 'dart:math' as math;
import 'dart:ui';

import 'quad.dart';

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
///
/// Nothing is drawn for a *first* sighting. A quadrilateral must be seen in
/// [acquireConfirmationFrames] mutually agreeing frames before the outline
/// appears, so a one- or two-frame phantom rectangle on an empty desk never
/// flashes on screen. A document that was being tracked and dropped out for
/// a moment is restored at once if it comes back in the same place within
/// [reacquireFrames].
class QuadSmoother {
  QuadSmoother({
    this.windowSize = 5,
    this.missesBeforeReset = 5,
    this.switchConfirmationFrames = 4,
    this.maxUnmatchedFrames = 6,
    this.switchDistanceThreshold = 0.12,
    this.acquireConfirmationFrames = 3,
    this.acquireDistanceThreshold = 0.05,
    this.reacquireFrames = 12,
  })  : assert(windowSize > 0 && windowSize.isOdd,
            'windowSize should be odd for a true median'),
        assert(missesBeforeReset > 0),
        assert(switchConfirmationFrames > 0),
        assert(maxUnmatchedFrames >= switchConfirmationFrames),
        assert(switchDistanceThreshold > 0),
        assert(acquireConfirmationFrames > 0),
        assert(acquireDistanceThreshold > 0),
        assert(reacquireFrames >= 0);

  final int windowSize;
  final int missesBeforeReset;
  final int switchConfirmationFrames;
  final int maxUnmatchedFrames;

  /// Maximum normalized corner displacement treated as the same document in
  /// a single frame. Quad coordinates are in the `[0, 1]` camera preview.
  final double switchDistanceThreshold;

  /// Consecutive agreeing detections needed before a new outline is shown.
  /// `1` restores the old "draw the very first detection" behaviour.
  final int acquireConfirmationFrames;

  /// Maximum normalized corner displacement between the detections that
  /// confirm a first sighting. Deliberately tighter than
  /// [switchDistanceThreshold]: random background rectangles rarely land on
  /// the same four corners several frames in a row, a real page does.
  final double acquireDistanceThreshold;

  /// Frames after losing a tracked document during which the same outline
  /// is restored on its first reappearance, without a new confirmation run.
  final int reacquireFrames;

  final Queue<Quad> _buffer = Queue<Quad>();
  final Queue<Quad> _challenger = Queue<Quad>();
  Quad? _tracked;
  int _consecutiveMisses = 0;
  int _unmatchedFrames = 0;
  bool _outlineSuppressed = false;

  // First-sighting confirmation and quick re-acquisition state.
  int _acquireMisses = 0;
  Quad? _lost;
  int _lostAge = 0;

  // Frames the displayed outline has been held unchanged; see [_settle].
  int _heldFrames = 0;

  void reset() {
    _clearTracking();
    _lost = null;
    _lostAge = 0;
  }

  void _clearTracking() {
    _buffer.clear();
    _challenger.clear();
    _tracked = null;
    _consecutiveMisses = 0;
    _unmatchedFrames = 0;
    _outlineSuppressed = false;
    _acquireMisses = 0;
    _heldFrames = 0;
  }

  /// Add [quad] (or null for a missed frame) and return the smoothed quad.
  /// Returns null when there's not yet any data to smooth.
  Quad? add(Quad? quad) {
    if (quad == null || !_isValid(quad)) {
      if (_tracked == null) {
        // Still waiting for a first sighting to be confirmed. One dropped
        // frame is tolerated; two in a row mean the candidate was not real.
        _ageLost();
        _acquireMisses++;
        if (_acquireMisses >= 2) _challenger.clear();
        return null;
      }
      _consecutiveMisses++;
      // A missing/invalid frame breaks a run of incompatible observations.
      // Otherwise several isolated chair detections, separated by genuine
      // misses, can accumulate into a false "lost document" state.
      if (!_outlineSuppressed) _unmatchedFrames = 0;
      _challenger.clear();
      if (_consecutiveMisses >= missesBeforeReset) {
        final last = _outlineSuppressed ? null : _tracked;
        _clearTracking();
        _lost = last;
        _lostAge = 0;
      }
      return _outlineSuppressed ? null : _tracked;
    }
    _consecutiveMisses = 0;
    if (_tracked == null) {
      return _acquire(quad);
    }

    if (_sameDocument(_tracked!, quad)) {
      _challenger.clear();
      _unmatchedFrames = 0;
      _outlineSuppressed = false;
      final previous = _buffer.isEmpty ? null : _buffer.last;
      _append(quad);

      final displayed = _tracked!;
      final median = _median();
      final mean = _recentMean(4, displayed);
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
        return _settle(displayed, median);
      }

      // The previous frame still agreed with the outline and this one jumps
      // away from it: treat it as a detector outlier until a second frame
      // says the same. Real movement is delayed by one frame only, while a
      // single bad contour can no longer kick the whole box sideways.
      if (rawDelta > .030 && previous != null &&
          displayed.maxCornerDistance(previous) <= .012) {
        return displayed;
      }
      _heldFrames = 0;

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
    final requiredFrames = _borderTakeover(quad)
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
      _heldFrames = 0;
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

  /// Handles a valid detection while nothing is displayed.
  Quad? _acquire(Quad quad) {
    _acquireMisses = 0;
    final lost = _lost;
    if (lost != null && _lostAge <= reacquireFrames && _agrees(lost, quad)) {
      // The page we were just tracking blinked out and is back in place.
      _lost = null;
      _challenger.clear();
      _append(quad);
      _tracked = lost.maxCornerDistance(quad) <= .014 ? lost : quad;
      _heldFrames = 0;
      return _tracked;
    }
    _ageLost();
    if (_challenger.isNotEmpty &&
        (!_agrees(_challenger.first, quad) ||
            !_agrees(_challenger.last, quad))) {
      _challenger.clear();
    }
    _challenger.addLast(quad);
    if (_challenger.length < acquireConfirmationFrames) return null;
    for (final candidate in _challenger) {
      _append(candidate);
    }
    _challenger.clear();
    _lost = null;
    // The median of the confirming frames is a better first outline than
    // whichever single frame happened to arrive last.
    _tracked = _median();
    _heldFrames = 0;
    return _tracked;
  }

  void _ageLost() {
    if (_lost == null) return;
    _lostAge++;
    if (_lostAge > reacquireFrames) _lost = null;
  }

  bool _agrees(Quad a, Quad b) {
    final smallerArea = math.min(a.area, b.area);
    final largerArea = math.max(a.area, b.area);
    if (smallerArea < 0.001 || largerArea / smallerArea > 1.35) {
      return false;
    }
    return a.maxCornerDistance(b) <= acquireDistanceThreshold;
  }

  /// Called while the outline is being held still. If a whole window of
  /// tightly agreeing detections sits a little away from the held corners,
  /// move onto their median once. The corners then rest on the consensus of
  /// several frames instead of on the single frame that first locked, which
  /// is more accurate and still does not vibrate: noisy windows never pass
  /// the spread test, and a settled outline has nothing left to correct.
  Quad _settle(Quad displayed, Quad median) {
    _heldFrames++;
    if (_heldFrames < windowSize || _buffer.length < windowSize) {
      return displayed;
    }
    final offset = displayed.maxCornerDistance(median);
    if (offset <= .004) return displayed;
    for (final observation in _buffer) {
      if (observation.maxCornerDistance(median) > .008) return displayed;
    }
    _heldFrames = 0;
    _tracked = median;
    return median;
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
  ///
  /// With a full set of [count] samples the one farthest from [displayed]
  /// is left out. A single wild contour would otherwise drag the average
  /// for the next few frames and let ordinary noise through; real movement
  /// shifts every sample, so it is still noticed.
  Quad _recentMean(int count, Quad displayed) {
    final recent = _buffer.toList().reversed.take(count).toList();
    assert(recent.isNotEmpty);
    if (recent.length >= 4) {
      var farthest = 0;
      var farthestDistance = -1.0;
      for (var i = 0; i < recent.length; i++) {
        final distance = displayed.maxCornerDistance(recent[i]);
        if (distance > farthestDistance) {
          farthestDistance = distance;
          farthest = i;
        }
      }
      recent.removeAt(farthest);
    }
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
