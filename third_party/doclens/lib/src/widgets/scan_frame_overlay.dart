import 'package:flutter/material.dart';

import '../quad.dart';
import '../models.dart';

/// The part of the camera buffer that is actually visible on screen, in
/// normalized `[0, 1]` buffer coordinates. The preview is scaled with
/// `BoxFit.cover`, so on most phones the left/right or top/bottom of the
/// buffer are cropped away. [DoclensView] provides this to overlays.
class DoclensVisibleRegion extends InheritedWidget {
  const DoclensVisibleRegion({
    super.key,
    required this.rect,
    required super.child,
  });

  final Rect rect;

  static const Rect full = Rect.fromLTRB(0, 0, 1, 1);

  static Rect of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<DoclensVisibleRegion>()
          ?.rect ?? full;

  /// Visible normalized region of a [buffer] drawn with `BoxFit.cover`
  /// into [viewport].
  static Rect coverRegion(Size buffer, Size viewport) {
    if (buffer.isEmpty || viewport.isEmpty) return full;
    final scale = (viewport.width / buffer.width) >
            (viewport.height / buffer.height)
        ? viewport.width / buffer.width
        : viewport.height / buffer.height;
    final w = ((viewport.width / scale) / buffer.width).clamp(0.0, 1.0);
    final h = ((viewport.height / scale) / buffer.height).clamp(0.0, 1.0);
    final left = (1 - w) / 2;
    final top = (1 - h) / 2;
    return Rect.fromLTWH(left, top, w, h);
  }

  @override
  bool updateShouldNotify(DoclensVisibleRegion oldWidget) =>
      oldWidget.rect != rect;
}

/// CamScanner-style live outline.
///
/// While no document is found, a thin green frame runs along the four
/// edges of the visible camera preview. As soon as a document is found the
/// frame's four corners glide onto the document's four corners, and when
/// the document is lost they glide back out to the screen edges.
///
/// Only the drawing is animated. Capture still uses the detected quad the
/// controller recorded, never the idle frame or an in-between shape.
class ScanFrameOverlay extends StatefulWidget {
  const ScanFrameOverlay({
    super.key,
    required this.quad,
    required this.status,
    this.accent = const Color(0xFF19BC9C),
    this.warning = const Color(0xFFFFB454),
    this.duration = const Duration(milliseconds: 280),
    this.idleInset = .006,
  });

  /// The detected document, or null when nothing is detected.
  final Quad? quad;
  final DetectionStatus status;
  final Color accent;
  final Color warning;
  final Duration duration;

  /// Gap between the idle frame and the preview edge (normalized).
  final double idleInset;

  /// Jumps smaller than this follow the detector directly instead of
  /// gliding, so ordinary tracking never lags behind the page.
  static const double glideThreshold = .08;

  @override
  State<ScanFrameOverlay> createState() => _ScanFrameOverlayState();
}

class _ScanFrameOverlayState extends State<ScanFrameOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _motion = AnimationController(
    vsync: this, duration: widget.duration, value: 1);
  late final CurvedAnimation _curve = CurvedAnimation(
    parent: _motion, curve: Curves.easeOutCubic);

  Quad? _from;
  Quad? _to;
  double _fromDetected = 0;
  double _toDetected = 0;
  Rect? _region;

  Quad _idle(Rect region) {
    final r = region.deflate(widget.idleInset);
    return Quad(
      topLeft: r.topLeft,
      topRight: r.topRight,
      bottomRight: r.bottomRight,
      bottomLeft: r.bottomLeft,
    );
  }

  Quad _shown() {
    final to = _to!;
    final from = _from ?? to;
    return Quad.interpolate(from, to, _curve.value);
  }

  double _detected() =>
      _fromDetected + (_toDetected - _fromDetected) * _curve.value;

  void _retarget(Rect region) {
    final target = widget.quad ?? _idle(region);
    final detected = widget.quad == null ? 0.0 : 1.0;
    if (_to == null) {
      // First frame: start from the screen edges so a page that is already
      // in view visibly "snaps in", as in the reference app.
      _from = _idle(region);
      _to = target;
      _fromDetected = 0;
      _toDetected = detected;
      _motion.forward(from: widget.quad == null ? 1 : 0);
      return;
    }
    final current = _shown();
    final small = detected == _toDetected &&
        current.maxCornerDistance(target) < ScanFrameOverlay.glideThreshold;
    if (small && !_motion.isAnimating) {
      _from = target;
      _to = target;
      _fromDetected = _toDetected = detected;
      return;
    }
    if (small) {
      // Keep gliding toward the moving page.
      _to = target;
      return;
    }
    _fromDetected = _detected();
    _from = current;
    _to = target;
    _toDetected = detected;
    _motion.forward(from: 0);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final region = DoclensVisibleRegion.of(context);
    if (region != _region) {
      final first = _region == null;
      _region = region;
      if (first) {
        _retarget(region);
      } else if (widget.quad == null) {
        _from = _to = _idle(region);
      }
    }
  }

  @override
  void didUpdateWidget(ScanFrameOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.quad != widget.quad && _region != null) {
      _retarget(_region!);
    }
  }

  @override
  void dispose() {
    _curve.dispose();
    _motion.dispose();
    super.dispose();
  }

  Color _color() {
    if (widget.quad != null) return widget.accent;
    switch (widget.status) {
      case DetectionStatus.tilted:
      case DetectionStatus.tooClose:
      case DetectionStatus.tooFar:
        return widget.warning;
      case DetectionStatus.searching:
      case DetectionStatus.noPaper:
      case DetectionStatus.aligned:
      case DetectionStatus.focusing:
      case DetectionStatus.confirming:
        return widget.accent;
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _curve,
    builder: (context, _) => CustomPaint(
      painter: _ScanFramePainter(
        quad: _to == null ? null : _shown(),
        detected: _detected(),
        color: _color(),
      ),
    ),
  );
}

class _ScanFramePainter extends CustomPainter {
  _ScanFramePainter({
    required this.quad,
    required this.detected,
    required this.color,
  });

  final Quad? quad;
  final double detected;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final q = quad;
    if (q == null) return;
    final s = q.scaleToSize(size);
    final path = Path()
      ..moveTo(s.topLeft.dx, s.topLeft.dy)
      ..lineTo(s.topRight.dx, s.topRight.dy)
      ..lineTo(s.bottomRight.dx, s.bottomRight.dy)
      ..lineTo(s.bottomLeft.dx, s.bottomLeft.dy)
      ..close();
    // The idle screen frame is a thin line; a found page gets the thicker
    // border and the faint mint tint used before.
    if (detected > 0) {
      canvas.drawPath(path,
          Paint()..color = color.withValues(alpha: .065 * detected));
    }
    canvas.drawPath(path, Paint()
      ..color = color.withValues(alpha: .80 + .15 * detected)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5 + 2.5 * detected
      ..strokeJoin = StrokeJoin.round);
  }

  @override
  bool shouldRepaint(_ScanFramePainter old) =>
      old.quad != quad || old.detected != detected || old.color != color;
}
