import 'dart:collection';
import 'dart:math' as math;
import 'dart:ui';

import 'quad.dart';

/// Sliding-window median filter with document-identity hysteresis.
///
/// Each corner is independently median-filtered (median X, median Y) over
/// the last [windowSize] observations *of the same document*. A detector can
/// briefly prefer a background rectangle when light changes: feeding that
/// outlier directly into the median produces a visibly jumping green box.
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
    this.switchConfirmationFrames = 3,
    this.maxUnmatchedFrames = 6,
    this.switchDistanceThreshold = 0.12,
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

  final Queue<Quad> _buffer = Queue<Quad>();
  final Queue<Quad> _challenger = Queue<Quad>();
  int _consecutiveMisses = 0;
  int _unmatchedFrames = 0;

  void reset() {
    _buffer.clear();
    _challenger.clear();
    _consecutiveMisses = 0;
    _unmatchedFrames = 0;
  }

  /// Add [quad] (or null for a missed frame) and return the smoothed quad.
  /// Returns null when there's not yet any data to smooth.
  Quad? add(Quad? quad) {
    if (quad == null) {
      _consecutiveMisses++;
      _challenger.clear();
      if (_consecutiveMisses >= missesBeforeReset) reset();
      return _buffer.isEmpty || _unmatchedFrames >= maxUnmatchedFrames
          ? null
          : _median();
    }
    _consecutiveMisses = 0;
    if (_buffer.isEmpty) {
      _append(quad);
      return quad;
    }

    if (_sameDocument(_median(), quad)) {
      _challenger.clear();
      _unmatchedFrames = 0;
      _append(quad);
      return _median();
    }

    // Do not pollute the confirmed document's median with a competing quad.
    // Require consecutive *mutually matching* candidates before moving the
    // outline. This also handles a genuinely new document entering view.
    _unmatchedFrames++;
    if (_challenger.isEmpty || !_sameDocument(_challenger.last, quad)) {
      _challenger.clear();
    }
    _challenger.addLast(quad);
    if (_challenger.length >= switchConfirmationFrames) {
      final incoming = _challenger.toList();
      _buffer.clear();
      for (final candidate in incoming) {
        _append(candidate);
      }
      _challenger.clear();
      _unmatchedFrames = 0;
      return _median();
    }

    // Rapid camera movement can produce a different candidate each frame.
    // In that case a stale outline is worse than displaying no outline.
    if (_unmatchedFrames >= maxUnmatchedFrames) return null;
    return _median();
  }

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
