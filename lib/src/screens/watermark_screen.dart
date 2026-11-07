import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../storage/document_store.dart';
import 'video_tool_style.dart';

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
  bool _showAdjust = true;
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

  void _removeOrClear(bool hasPrevious) {
    if (hasPrevious) {
      _removeLast();
    } else {
      _label.clear();
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final page = widget.store.byId(widget.documentId)?.pages
        .where((item) => item.id == widget.pageId).firstOrNull;
    final hasPrevious = page?.watermarkBackupPath != null;
    return VideoToolStyle.wrapDark(Scaffold(
      backgroundColor: const Color(0xFF19191B),
      body: SafeArea(child: LayoutBuilder(builder: (context, viewport) =>
        Column(children: [
          if (_busy) const LinearProgressIndicator(),
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
          if (_showAdjust)
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: viewport.maxHeight * .55),
              child: Container(
                width: double.infinity,
                decoration: const BoxDecoration(
                  color: VideoToolStyle.header,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(14))),
                child: SingleChildScrollView(child: Column(children: [
                  IconButton(
                    onPressed: () => setState(() => _showAdjust = false),
                    icon: const Icon(Icons.keyboard_arrow_down,
                      color: VideoToolStyle.muted, size: 30)),
                  Padding(padding: const EdgeInsets.fromLTRB(14, 1, 14, 10),
                    child: TextField(
                      controller: _label,
                      maxLength: 80,
                      onChanged: (_) => setState(() {}),
                      decoration: const InputDecoration(
                        isDense: true, labelText: 'Watermark text',
                        border: OutlineInputBorder(),
                        suffixIcon: Icon(Icons.edit_outlined)),
                    )),
                  Row(children: [
                    for (final tiled in [false, true])
                      Expanded(child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size.fromHeight(44),
                            backgroundColor: _tiled == tiled
                                ? VideoToolStyle.teal.withValues(alpha: .14)
                                : VideoToolStyle.tile,
                            side: BorderSide(color: _tiled == tiled
                                ? VideoToolStyle.teal : Colors.transparent)),
                          onPressed: () => setState(() => _tiled = tiled),
                          child: Text(tiled ? 'Tile' : 'Single',
                            style: TextStyle(color: _tiled == tiled
                                ? VideoToolStyle.teal : Colors.white)),
                        ),
                      )),
                  ]),
                  const SizedBox(height: 12),
                  SizedBox(height: 36, child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    children: [
                      for (final ink in [Colors.black, Colors.white,
                        const Color(0xFF0DB89F), const Color(0xFFFF9C00),
                        const Color(0xFFFF6568), const Color(0xFF1686EB),
                        const Color(0xFFF2E67C), const Color(0xFFFFE000),
                        const Color(0xFF75D81B), const Color(0xFF008C5F)])
                        Padding(padding: const EdgeInsets.only(right: 13),
                          child: InkWell(onTap: () => setState(() => _color = ink),
                            child: Container(width: 27, height: 27,
                              decoration: BoxDecoration(shape: BoxShape.circle,
                                color: ink,
                                border: Border.all(color: _color == ink
                                    ? VideoToolStyle.teal : Colors.transparent,
                                    width: 2.5)),
                            ),
                          ),
                        ),
                    ],
                  )),
                  _slider('Opacity', _opacity, .10, 1,
                    (value) => setState(() => _opacity = value)),
                  _slider('Size', _fontFraction, .025, .12,
                    (value) => setState(() => _fontFraction = value)),
                  _slider('Rotate', _rotationDegrees, -45, 45,
                    (value) => setState(() => _rotationDegrees = value)),
                  SizedBox(height: 42, child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    children: [
                      for (final placement in WatermarkPlacement.values)
                        Padding(padding: const EdgeInsets.only(right: 7),
                          child: ChoiceChip(label: Text(placement.label),
                            selected: _placement == placement,
                            onSelected: (_) => setState(() =>
                                _placement = placement)),
                        ),
                    ],
                  )),
                  const SizedBox(height: 10),
                ])),
              ),
            )
          else
            Container(color: VideoToolStyle.header,
              padding: const EdgeInsets.symmetric(vertical: 11),
              child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _toolButton(Icons.text_fields, 'Edit Text',
                      () => setState(() => _showAdjust = true)),
                  _toolButton(Icons.tune, 'Adjust',
                      () => setState(() => _showAdjust = true)),
                  _toolButton(Icons.delete_outline, 'Remove Watermark',
                      () => _removeOrClear(hasPrevious)),
                ],
              ),
            ),
          VideoToolBottomBar(
            title: 'Add Watermark', busy: _busy,
            onCancel: () => Navigator.pop(context),
            onDone: _label.text.trim().isEmpty ? () {
              if (hasPrevious) _removeLast();
            } : _apply,
          ),
        ]))),
    ));
  }

  Widget _toolButton(IconData icon, String label, VoidCallback callback) =>
      InkWell(onTap: callback,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, color: Colors.white, size: 22),
          const SizedBox(height: 4),
          Text(label, style: const TextStyle(color: Colors.white, fontSize: 11)),
        ]));

  Widget _slider(String label, double value, double min, double max,
      ValueChanged<double> update) => Row(children: [
    SizedBox(width: 82, child: Padding(
      padding: const EdgeInsets.only(left: 16),
      child: Text(label, style: const TextStyle(color: Colors.white70)))),
    Expanded(child: Slider(value: value, min: min, max: max,
        activeColor: VideoToolStyle.teal, onChanged: update)),
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
