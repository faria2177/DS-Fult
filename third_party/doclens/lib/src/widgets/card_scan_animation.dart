import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../fallback/file_io.dart';
import '../quad.dart';
import 'reference_id_card_chrome.dart';

/// Shutter animation for card capture (reference video 386540):
///
/// 1. The captured still stays on screen; the detected card gets a teal
///    outline and a teal scan band sweeps down over it.
/// 2. The flattened (cropped) card appears in the card frame and a second
///    band sweeps over it.
///
/// About 1.3 s in total; [onDone] is called once at the end.
class CardScanAnimation extends StatefulWidget {
  const CardScanAnimation({
    super.key,
    required this.rawImagePath,
    required this.rawImageSize,
    required this.quad,
    this.croppedImagePath,
    this.portraitGuide = false,
    this.accent = const Color(0xFF19C5B0),
    required this.onDone,
    this.duration = const Duration(milliseconds: 1300),
  });

  final String rawImagePath;
  final Size rawImageSize;

  /// Card corners in raw image pixels.
  final Quad quad;
  final String? croppedImagePath;
  final bool portraitGuide;
  final Color accent;
  final VoidCallback onDone;
  final Duration duration;

  @override
  State<CardScanAnimation> createState() => _CardScanAnimationState();
}

class _CardScanAnimationState extends State<CardScanAnimation>
    with SingleTickerProviderStateMixin {
  late final AnimationController _t = AnimationController(
      vsync: this, duration: widget.duration)
    ..addStatusListener((status) {
      if (status == AnimationStatus.completed) widget.onDone();
    })
    ..forward();

  Uint8List? _raw;
  Uint8List? _cropped;

  @override
  void initState() {
    super.initState();
    readFileBytes(widget.rawImagePath).then((bytes) {
      if (mounted) setState(() => _raw = bytes);
    }, onError: (_) {});
    final cropped = widget.croppedImagePath;
    if (cropped != null) {
      readFileBytes(cropped).then((bytes) {
        if (mounted) setState(() => _cropped = bytes);
      }, onError: (_) {});
    }
  }

  // Phase boundaries as fractions of the whole animation.
  static const _sweepEnd = .50;
  static const _morphEnd = .60;

  @override
  void dispose() {
    _t.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final area = constraints.biggest;
          return AnimatedBuilder(
            animation: _t,
            builder: (context, _) {
              final v = _t.value;
              final morph = ((v - _sweepEnd) / (_morphEnd - _sweepEnd))
                  .clamp(0.0, 1.0);
              final frame = cardFrameRect(area,
                  portraitGuide: widget.portraitGuide);
              final raw = _raw;
              final cropped = _cropped;
              return Stack(fit: StackFit.expand, children: [
                // The still, exactly where the live preview showed it.
                if (raw != null)
                  Image.memory(raw, fit: BoxFit.cover, gaplessPlayback: true,
                      errorBuilder: (context, error, stack) => const ColoredBox(
                          color: Colors.black)),
                if (v < _morphEnd)
                  Opacity(
                    opacity: 1 - morph,
                    child: CustomPaint(painter: _QuadSweepPainter(
                      corners: _toScreen(area),
                      progress: (v / _sweepEnd).clamp(0.0, 1.0),
                      accent: widget.accent,
                    )),
                  ),
                if (v >= _sweepEnd) ...[
                  Opacity(opacity: morph * .75,
                      child: const ColoredBox(color: Colors.black)),
                  Positioned.fromRect(
                    rect: Rect.lerp(_quadBounds(area), frame,
                        Curves.easeOut.transform(morph))!,
                    child: Opacity(
                      opacity: morph,
                      child: Stack(fit: StackFit.expand, children: [
                        if (cropped != null)
                          Image.memory(cropped, fit: BoxFit.fill,
                              gaplessPlayback: true,
                              errorBuilder: (context, error, stack) =>
                                  const ColoredBox(color: Colors.white))
                        else
                          const ColoredBox(color: Colors.white),
                        CustomPaint(painter: _QuadSweepPainter(
                          corners: null,
                          progress: ((v - _morphEnd) / (1 - _morphEnd))
                              .clamp(0.0, 1.0),
                          accent: widget.accent,
                        )),
                      ]),
                    ),
                  ),
                ],
              ]);
            },
          );
        },
      );

  /// Raw-image quad → screen points under BoxFit.cover.
  List<Offset> _toScreen(Size area) {
    final image = widget.rawImageSize;
    if (image.width <= 0 || image.height <= 0) {
      return [Offset.zero, Offset(area.width, 0),
        Offset(area.width, area.height), Offset(0, area.height)];
    }
    final scale = math.max(area.width / image.width, area.height / image.height);
    final dx = (area.width - image.width * scale) / 2;
    final dy = (area.height - image.height * scale) / 2;
    Offset map(Offset p) => Offset(p.dx * scale + dx, p.dy * scale + dy);
    final q = widget.quad;
    final pts = [q.topLeft, q.topRight, q.bottomRight, q.bottomLeft];
    var twice = 0.0;
    for (var i = 0; i < 4; i++) {
      final a = pts[i], b = pts[(i + 1) % 4];
      twice += a.dx * b.dy - b.dx * a.dy;
    }
    // No credible card outline: sweep the whole still instead.
    if (twice.abs() / 2 < image.width * image.height * .01) {
      return [map(Offset.zero), map(Offset(image.width, 0)),
        map(Offset(image.width, image.height)), map(Offset(0, image.height))];
    }
    return pts.map(map).toList();
  }

  Rect _quadBounds(Size area) {
    final pts = _toScreen(area);
    var l = pts.first.dx, r = l, t = pts.first.dy, b = t;
    for (final p in pts) {
      l = math.min(l, p.dx);
      r = math.max(r, p.dx);
      t = math.min(t, p.dy);
      b = math.max(b, p.dy);
    }
    return Rect.fromLTRB(l, t, r, b);
  }
}

/// Teal outline + a band of light sweeping from the top edge to the bottom
/// edge of a quad (or of the whole canvas when [corners] is null).
class _QuadSweepPainter extends CustomPainter {
  _QuadSweepPainter({required this.corners, required this.progress,
      required this.accent});

  final List<Offset>? corners;
  final double progress;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final c = corners ?? [Offset.zero, Offset(size.width, 0),
      Offset(size.width, size.height), Offset(0, size.height)];
    final outline = Path()..addPolygon(c, true);
    if (corners != null) {
      canvas.drawPath(outline, Paint()..color = accent.withValues(alpha: .14));
      canvas.drawPath(outline, Paint()
        ..color = accent
        ..strokeWidth = 2.5
        ..style = PaintingStyle.stroke);
    }
    // Points on the left (TL→BL) and right (TR→BR) edges at height t.
    Offset left(double t) => Offset.lerp(c[0], c[3], t)!;
    Offset right(double t) => Offset.lerp(c[1], c[2], t)!;
    const tail = .22;
    final lead = progress;
    final start = math.max(0.0, lead - tail);
    if (lead <= 0) return;
    canvas.save();
    canvas.clipPath(outline);
    final band = Path()
      ..moveTo(left(start).dx, left(start).dy)
      ..lineTo(right(start).dx, right(start).dy)
      ..lineTo(right(lead).dx, right(lead).dy)
      ..lineTo(left(lead).dx, left(lead).dy)
      ..close();
    final from = Offset.lerp(left(start), right(start), .5)!;
    final to = Offset.lerp(left(lead), right(lead), .5)!;
    canvas.drawPath(band, Paint()..shader = _gradient(from, to));
    canvas.drawLine(left(lead), right(lead), Paint()
      ..color = Color.lerp(accent, Colors.white, .55)!
      ..strokeWidth = 3);
    canvas.restore();
  }

  Shader _gradient(Offset from, Offset to) => LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [accent.withValues(alpha: 0), accent.withValues(alpha: .55)],
      ).createShader(Rect.fromPoints(
          Offset(math.min(from.dx, to.dx) - 1, from.dy),
          Offset(math.max(from.dx, to.dx) + 1, to.dy + .01)));

  @override
  bool shouldRepaint(covariant _QuadSweepPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.corners != corners;
}
