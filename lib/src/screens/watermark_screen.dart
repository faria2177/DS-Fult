import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../storage/document_store.dart';
import '../theme.dart';

enum WatermarkPlacement { topLeft, center, bottomRight }

extension WatermarkPlacementView on WatermarkPlacement {
  String get label => switch (this) {
    WatermarkPlacement.topLeft => 'Top left',
    WatermarkPlacement.center => 'Center',
    WatermarkPlacement.bottomRight => 'Bottom right',
  };

  Alignment get alignment => switch (this) {
    WatermarkPlacement.topLeft => Alignment.topLeft,
    WatermarkPlacement.center => Alignment.center,
    WatermarkPlacement.bottomRight => Alignment.bottomRight,
  };
}

/// Text watermarking on a copied page image, without a PDF export round trip.
class WatermarkScreen extends StatefulWidget {
  const WatermarkScreen({super.key, required this.store,
      required this.documentId, required this.pageId});

  final DocumentStore store;
  final String documentId;
  final String pageId;

  @override
  State<WatermarkScreen> createState() => _WatermarkScreenState();
}

class _WatermarkScreenState extends State<WatermarkScreen> {
  final TextEditingController _label = TextEditingController(text: 'DocScanner');
  WatermarkPlacement _placement = WatermarkPlacement.center;
  Color _color = Colors.black;
  double _opacity = .46;
  double _fontFraction = .062;
  double _rotationDegrees = -25;
  bool _tiled = false;
  double _aspect = .72;
  String? _imagePath;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _loadPage();
  }

  Future<void> _loadPage() async {
    final doc = widget.store.byId(widget.documentId);
    final page = doc?.pages.where((item) => item.id == widget.pageId).firstOrNull;
    if (page == null) return;
    try {
      final bytes = await File(page.path).readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final aspect = frame.image.width / frame.image.height;
      frame.image.dispose();
      codec.dispose();
      if (mounted) setState(() { _imagePath = page.path; _aspect = aspect; });
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not load image: $error')));
      }
    }
  }

  @override
  void dispose() {
    _label.dispose();
    super.dispose();
  }

  Future<void> _apply() async {
    final path = _imagePath;
    final label = _label.text.trim();
    if (_busy || path == null || label.isEmpty) return;
    setState(() => _busy = true);
    try {
      final bytes = await WatermarkComposer.composite(
        await File(path).readAsBytes(),
        text: label, placement: _placement, color: _color,
        opacity: _opacity, fontFraction: _fontFraction,
        rotationDegrees: _rotationDegrees, tiled: _tiled,
      );
      await widget.store.replacePageBytes(widget.documentId,
          widget.pageId, bytes, extension: '.png', asWatermark: true);
      if (mounted) {
        Navigator.pop(context, true);
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not apply watermark: $error')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _removeLast() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await widget.store.removeLastWatermark(widget.documentId, widget.pageId);
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Cannot remove watermark: $error')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final page = widget.store.byId(widget.documentId)?.pages
        .where((item) => item.id == widget.pageId).firstOrNull;
    return Scaffold(
    appBar: AppBar(title: const Text('Add Watermark')),
    body: SafeArea(child: LayoutBuilder(builder: (context, viewport) =>
      Column(children: [
      if (_busy) const LinearProgressIndicator(color: dsTeal),
      Expanded(child: Center(child: _imagePath == null
          ? const CircularProgressIndicator()
          : LayoutBuilder(builder: (context, constraints) {
              final width = (constraints.maxHeight * _aspect)
                  .clamp(1.0, constraints.maxWidth).toDouble();
              final height = width / _aspect;
              return SizedBox(width: width, height: height,
                child: Stack(fit: StackFit.expand, children: [
                  Image.file(File(_imagePath!), fit: BoxFit.fill),
                  CustomPaint(painter: _WatermarkPreviewPainter(
                    text: _label.text, placement: _placement, color: _color,
                    opacity: _opacity, fontFraction: _fontFraction,
                    rotationDegrees: _rotationDegrees, tiled: _tiled,
                  )),
                ]),
              );
            }))),
      ConstrainedBox(
        constraints: BoxConstraints(maxHeight: viewport.maxHeight * .63),
        child: SingleChildScrollView(child: Column(children: [
      Padding(padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        child: TextField(
          controller: _label,
          onChanged: (_) => setState(() {}),
          maxLength: 80,
          decoration: const InputDecoration(labelText: 'Watermark text',
              prefixIcon: Icon(Icons.text_fields), border: OutlineInputBorder()),
        )),
      SizedBox(height: 44, child: ListView(scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 14), children: [
          for (final place in WatermarkPlacement.values)
            Padding(padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(label: Text(place.label),
                selected: _placement == place,
                onSelected: (_) => setState(() => _placement = place))),
        ],
      )),
      Padding(padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
        child: SegmentedButton<bool>(
          segments: const [
            ButtonSegment(value: false, label: Text('Single')),
            ButtonSegment(value: true, label: Text('Tile')),
          ],
          selected: {_tiled},
          onSelectionChanged: (values) =>
              setState(() => _tiled = values.first),
        )),
      Row(children: [
        const SizedBox(width: 16), const Text('Ink'),
        const SizedBox(width: 14),
        for (final color in [Colors.black, Colors.white,
            const Color(0xFF1244A2), const Color(0xFFE84545),
            const Color(0xFF008577), const Color(0xFFE78A13)])
          Padding(padding: const EdgeInsets.only(right: 12),
            child: InkWell(onTap: () => setState(() => _color = color),
              child: CircleAvatar(radius: _color == color ? 17 : 15,
                backgroundColor: color,
                child: _color == color
                    ? Icon(Icons.check, size: 16,
                        color: color == Colors.white ? Colors.black : Colors.white)
                    : null)),
          ),
      ]),
      _slider('Size', _fontFraction, .025, .12,
          (value) => setState(() => _fontFraction = value)),
      _slider('Opacity', _opacity, .15, 1,
          (value) => setState(() => _opacity = value)),
      _slider('Rotate', _rotationDegrees, -45, 45,
          (value) => setState(() => _rotationDegrees = value)),
      Padding(padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
        child: SizedBox(width: double.infinity, child: FilledButton.icon(
          onPressed: _busy || _label.text.trim().isEmpty ? null : _apply,
          icon: const Icon(Icons.check),
          label: const Text('Apply Watermark'),
          style: FilledButton.styleFrom(backgroundColor: dsTeal),
        )),
      ),
      if (page?.watermarkBackupPath != null)
        TextButton.icon(
          onPressed: _busy ? null : _removeLast,
          icon: const Icon(Icons.delete_outline),
          label: const Text('Remove Last Watermark'),
        ),
        ])),
      ),
    ]))),
  );
  }

  Widget _slider(String label, double value, double min, double max,
      ValueChanged<double> update) => Row(children: [
    SizedBox(width: 82, child: Padding(
      padding: const EdgeInsets.only(left: 16), child: Text(label))),
    Expanded(child: Slider(value: value, min: min, max: max,
        activeColor: dsTeal, onChanged: update)),
  ]);
}

/// Exact same text layout is used on-device at the original image resolution.
class WatermarkComposer {
  static void paint(
    Canvas canvas,
    Size bounds, {
    required String text,
    WatermarkPlacement placement = WatermarkPlacement.center,
    Color color = Colors.black,
    double opacity = .46,
    double fontFraction = .062,
    double rotationDegrees = 0,
    bool tiled = false,
  }) {
    if (text.trim().isEmpty) return;
    final width = bounds.width;
    final height = bounds.height;
    final shortSide = math.min(width, height);
    final painter = TextPainter(
      text: TextSpan(text: text.trim(), style: TextStyle(
        color: color.withValues(alpha: opacity.clamp(0.0, 1.0).toDouble()),
        fontWeight: FontWeight.w700,
        fontSize: shortSide * fontFraction.clamp(.025, .12),
      )),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
      maxLines: 3,
    )..layout(maxWidth: width * .86);

    final angle = rotationDegrees.clamp(-45.0, 45.0) * math.pi / 180;
    void drawAt(Offset center) {
      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.rotate(angle);
      painter.paint(canvas, Offset(-painter.width / 2, -painter.height / 2));
      canvas.restore();
    }

    if (tiled) {
      final stepX = math.max(width * .4, painter.width * 1.35);
      final stepY = math.max(height * .19, painter.height * 3.5);
      for (var y = stepY / 2; y < height + stepY / 2; y += stepY) {
        for (var x = stepX / 2; x < width + stepX / 2; x += stepX) {
          drawAt(Offset(x, y));
        }
      }
    } else {
      final x = switch (placement) {
        WatermarkPlacement.topLeft => width * .055,
        WatermarkPlacement.center => (width - painter.width) / 2,
        WatermarkPlacement.bottomRight => width * .945 - painter.width,
      };
      final y = switch (placement) {
        WatermarkPlacement.topLeft => height * .055,
        WatermarkPlacement.center => (height - painter.height) / 2,
        WatermarkPlacement.bottomRight => height * .945 - painter.height,
      };
      drawAt(Offset(x + painter.width / 2, y + painter.height / 2));
    }
  }

  static Future<Uint8List> composite(
    Uint8List original, {
    required String text,
    WatermarkPlacement placement = WatermarkPlacement.center,
    Color color = Colors.black,
    double opacity = .46,
    double fontFraction = .062,
    double rotationDegrees = 0,
    bool tiled = false,
  }) async {
    if (text.trim().isEmpty) throw ArgumentError('Watermark must not be empty');
    final codec = await ui.instantiateImageCodec(original);
    final frame = await codec.getNextFrame();
    final image = frame.image;
    try {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.drawImage(image, Offset.zero, Paint());
      paint(canvas, Size(image.width.toDouble(), image.height.toDouble()),
          text: text, placement: placement, color: color, opacity: opacity,
          fontFraction: fontFraction, rotationDegrees: rotationDegrees,
          tiled: tiled);
      final output = await recorder.endRecording()
          .toImage(image.width, image.height);
      try {
        final data = await output.toByteData(format: ui.ImageByteFormat.png);
        if (data == null) throw StateError('Watermark rendering failed');
        return data.buffer.asUint8List();
      } finally {
        output.dispose();
      }
    } finally {
      image.dispose();
      codec.dispose();
    }
  }
}

class _WatermarkPreviewPainter extends CustomPainter {
  const _WatermarkPreviewPainter({
    required this.text,
    required this.placement,
    required this.color,
    required this.opacity,
    required this.fontFraction,
    required this.rotationDegrees,
    required this.tiled,
  });

  final String text;
  final WatermarkPlacement placement;
  final Color color;
  final double opacity;
  final double fontFraction;
  final double rotationDegrees;
  final bool tiled;

  @override
  void paint(Canvas canvas, Size size) => WatermarkComposer.paint(
      canvas, size, text: text, placement: placement, color: color,
      opacity: opacity, fontFraction: fontFraction,
      rotationDegrees: rotationDegrees, tiled: tiled);

  @override
  bool shouldRepaint(covariant _WatermarkPreviewPainter old) =>
      old.text != text || old.placement != placement || old.color != color ||
      old.opacity != opacity || old.fontFraction != fontFraction ||
      old.rotationDegrees != rotationDegrees || old.tiled != tiled;
}
