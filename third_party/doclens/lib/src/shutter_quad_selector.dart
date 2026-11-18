import 'quad.dart';
import 'truncated_page.dart';

/// Chooses which green outline a manual shutter press should crop.
///
/// On lined notebook paper the live detector can swap the page border for
/// a ruled line, so the green box suddenly covers only part of the page.
/// Seen in the field: page 02 of a notebook scan lost its bottom third
/// although the box had been on the full page just before.
///
/// The selector keeps a short history of the painted outlines. At the tap
/// it returns the painted outline, unless that outline is the steady page
/// of the last seconds cut short (see [isTruncatedPage]) and only appeared
/// recently; then the full page wins. A different document, or a box the
/// user keeps on screen long enough, is used as painted.
class ShutterQuadSelector {
  ShutterQuadSelector({
    this.window = const Duration(milliseconds: 3000),
    this.insideJump = const Duration(milliseconds: 1500),
    this.minSteady = const Duration(milliseconds: 400),
    this.sameTolerance = 0.04,
  });

  /// How far back the history reaches.
  final Duration window;

  /// A truncated page (see [isTruncatedPage]) is treated as a jump for
  /// this long.
  final Duration insideJump;

  /// How long the earlier outline must have been on screen to be trusted.
  final Duration minSteady;

  /// Largest corner distance, in normalized preview units, for two
  /// outlines to count as the same target.
  final double sameTolerance;

  final List<_Painted> _history = [];

  /// Record the outline painted at [at] (null = no box on screen).
  void record(Quad? quad, DateTime at) {
    if (_history.isNotEmpty && _same(_history.last.quad, quad)) {
      // Keep the segment start; only the latest corners are updated so a
      // slowly tracking box does not reset its own age.
      _history.last = _Painted(quad, _history.last.since);
    } else {
      _history.add(_Painted(quad, at));
    }
    final cutoff = at.subtract(window * 2);
    while (_history.length > 2 && _history[1].since.isBefore(cutoff)) {
      _history.removeAt(0);
    }
  }

  void clear() => _history.clear();

  /// The outline to crop for a shutter press at [now].
  Quad? select(DateTime now) {
    if (_history.isEmpty) return null;
    final current = _history.last;
    final quad = current.quad;
    if (quad == null) return null;
    final age = now.difference(current.since);
    if (age >= insideJump) return quad;

    // Find the outline held longest in the window before the current one.
    final start = now.subtract(window);
    _Painted? best;
    var bestTime = Duration.zero;
    for (var i = 0; i < _history.length - 1; i++) {
      final item = _history[i];
      final candidate = item.quad;
      if (candidate == null || _same(candidate, quad)) continue;
      var support = Duration.zero;
      for (var j = 0; j < _history.length - 1; j++) {
        final other = _history[j];
        if (!_same(other.quad, candidate)) continue;
        final from = other.since.isBefore(start) ? start : other.since;
        final to = _history[j + 1].since;
        if (to.isAfter(from)) support += to.difference(from);
      }
      if (support > bestTime) {
        bestTime = support;
        best = item;
      }
    }
    final steady = best?.quad;
    if (steady == null || bestTime < minSteady) return quad;
    // The page cut short by a ruled line: keep the full page.
    if (isTruncatedPage(quad, steady)) return steady;
    return quad;
  }

  bool _same(Quad? a, Quad? b) {
    if (a == null || b == null) return a == null && b == null;
    final pa = a.points;
    final pb = b.points;
    for (var i = 0; i < 4; i++) {
      if ((pa[i] - pb[i]).distance > sameTolerance) return false;
    }
    return true;
  }
}

class _Painted {
  const _Painted(this.quad, this.since);
  final Quad? quad;
  final DateTime since;
}
