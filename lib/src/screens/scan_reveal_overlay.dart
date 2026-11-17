import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme.dart';

/// What the shutter produced, for the post-capture animation.
class ScanRevealData {
  const ScanRevealData({required this.rawPath, required this.imageSize,
      required this.corners});

  /// The captured photo, upright.
  final String rawPath;

  /// [rawPath]'s pixel size.
  final Size imageSize;

  /// Document corners in [rawPath] pixels (TL, TR, BR, BL), or empty when
  /// the whole photo is the document.
  final List<Offset> corners;
}

/// Post-shutter animation, purely visual.
///
/// While the scan is processed, the frozen photo is shown with the document
/// highlighted and a glowing line sweeping over it. When [resultPath]
/// arrives, the line makes one last top-to-bottom pass that uncovers the
/// finished, cropped and enhanced page, then [onRevealed] is called.
/// Detection, crop and enhancement are not affected in any way.
class ScanRevealOverlay extends StatefulWidget {
  const ScanRevealOverlay({super.key, required this.data, this.resultPath,
      required this.onRevealed});

  final ScanRevealData data;
  final String? resultPath;
  final VoidCallback onRevealed;

  static const revealDuration = Duration(milliseconds: 650);

  @override
  State<ScanRevealOverlay> createState() => _ScanRevealOverlayState();
}

class _ScanRevealOverlayState extends State<ScanRevealOverlay>
    with TickerProviderStateMixin {
  late final AnimationController _sweep = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1100))
    ..repeat(reverse: true);
  late final AnimationController _reveal = AnimationController(
      vsync: this, duration: ScanRevealOverlay.revealDuration)
    ..addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        Future<void>.delayed(const Duration(milliseconds: 180), () {
          if (mounted) widget.onRevealed();
        });
      }
    });
  bool _revealing = false;

  @override
  void initState() {
    super.initState();
    _startRevealIfReady();
  }

  @override
  void didUpdateWidget(ScanRevealOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    _startRevealIfReady();
  }

  void _startRevealIfReady() {
    final result = widget.resultPath;
    if (result == null || _revealing) return;
    _revealing = true;
    // Decode first so the page is already there when the line uncovers it.
    precacheImage(FileImage(File(result)), context).whenComplete(() {
      if (!mounted) return;
      _sweep.stop();
      _reveal.forward();
    });
  }

  @override
  void dispose() {
    _sweep.dispose();
    _reveal.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black,
      child: LayoutBuilder(builder: (context, constraints) {
        final box = Size(constraints.maxWidth, constraints.maxHeight);
        final image = widget.data.imageSize;
        final scale = math.min(box.width / image.width,
            box.height / image.height);
        final shown = Size(image.width * scale, image.height * scale);
        final origin = Offset((box.width - shown.width) / 2,
            (box.height - shown.height) / 2);
        final corners = widget.data.corners.length == 4
            ? [for (final c in widget.data.corners) origin + c * scale]
            : [origin, origin + Offset(shown.width, 0),
                origin + Offset(shown.width, shown.height),
                origin + Offset(0, shown.height)];
        final bounds = _bounds(corners);
        return Stack(children: [
          Positioned.fromRect(
            rect: origin & shown,
            child: Image.file(File(widget.data.rawPath), fit: BoxFit.fill,
                gaplessPlayback: true,
                errorBuilder: (_, _, _) => const SizedBox.shrink()),
          ),
          Positioned.fill(child: AnimatedBuilder(
            animation: Listenable.merge([_sweep, _reveal]),
            builder: (context, _) {
              final revealing = _reveal.value > 0;
              final t = revealing
                  ? Curves.easeInOut.transform(_reveal.value)
                  : _sweep.value;
              return Stack(children: [
                CustomPaint(
                  size: box,
                  painter: _HighlightPainter(corners: corners,
                      dim: revealing ? .55 + .2 * _reveal.value : .55),
                ),
                if (widget.resultPath != null && revealing)
                  Positioned.fromRect(
                    rect: bounds,
                    child: ClipRect(
                      child: Align(
                        alignment: Alignment.topCenter,
                        heightFactor: t,
                        child: SizedBox(
                          width: bounds.width, height: bounds.height,
                          child: Image.file(File(widget.resultPath!),
                              fit: BoxFit.contain, gaplessPlayback: true,
                              errorBuilder: (_, _, _) =>
                                  const SizedBox.shrink()),
                        ),
                      ),
                    ),
                  ),
                CustomPaint(
                  size: box,
                  painter: _ScanLinePainter(corners: corners, bounds: bounds,
                      progress: t, fade: revealing && _reveal.value > .92
                          ? (1 - _reveal.value) / .08 : 1),
                ),
              ]);
            },
          )),
        ]);
      }),
    );
  }

  static Rect _bounds(List<Offset> corners) {
    var left = corners.first.dx, right = left;
    var top = corners.first.dy, bottom = top;
    for (final c in corners) {
      left = math.min(left, c.dx);
      right = math.max(right, c.dx);
      top = math.min(top, c.dy);
      bottom = math.max(bottom, c.dy);
    }
    return Rect.fromLTRB(left, top, right, bottom);
  }
}

/// Dims everything outside the document and outlines it.
class _HighlightPainter extends CustomPainter {
  _HighlightPainter({required this.corners, required this.dim});

  final List<Offset> corners;
  final double dim;

  @override
  void paint(Canvas canvas, Size size) {
    final document = Path()..addPolygon(corners, true);
    final outside = Path.combine(PathOperation.difference,
        Path()..addRect(Offset.zero & size), document);
    canvas.drawPath(outside,
        Paint()..color = Colors.black.withValues(alpha: dim));
    canvas.drawPath(document, Paint()
      ..color = dsTeal.withValues(alpha: .9)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2);
  }

  @override
  bool shouldRepaint(_HighlightPainter old) =>
      old.dim != dim || old.corners != corners;
}

/// A glowing horizontal line at [progress] (0 top .. 1 bottom), clipped to
/// the document, with a soft trail above it.
class _ScanLinePainter extends CustomPainter {
  _ScanLinePainter({required this.corners, required this.bounds,
      required this.progress, required this.fade});

  final List<Offset> corners;
  final Rect bounds;
  final double progress;
  final double fade;

  @override
  void paint(Canvas canvas, Size size) {
    if (fade <= 0) return;
    final y = bounds.top + bounds.height * progress;
    canvas.save();
    canvas.clipRect(bounds.inflate(1));
    final trail = math.min(60.0, bounds.height * .25);
    canvas.drawRect(
      Rect.fromLTRB(bounds.left, y - trail, bounds.right, y),
      Paint()..shader = LinearGradient(
        begin: Alignment.topCenter, end: Alignment.bottomCenter,
        colors: [dsTeal.withValues(alpha: 0),
          dsTeal.withValues(alpha: .28 * fade)],
      ).createShader(Rect.fromLTRB(bounds.left, y - trail, bounds.right, y)),
    );
    canvas.drawLine(Offset(bounds.left, y), Offset(bounds.right, y), Paint()
      ..color = dsTeal.withValues(alpha: .9 * fade)
      ..strokeWidth = 7
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6));
    canvas.drawLine(Offset(bounds.left, y), Offset(bounds.right, y), Paint()
      ..color = Colors.white.withValues(alpha: .95 * fade)
      ..strokeWidth = 2);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_ScanLinePainter old) =>
      old.progress != progress || old.fade != fade || old.bounds != bounds;
}
