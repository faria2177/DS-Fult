import 'dart:io';
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
      );
      await widget.store.replacePageBytes(widget.documentId,
          widget.pageId, bytes, extension: '.png');
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

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Add Watermark')),
    body: SafeArea(child: Column(children: [
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
                  Padding(padding: EdgeInsets.all(width * .055),
                    child: Align(alignment: _placement.alignment,
                      child: Text(_label.text,
                        maxLines: 3, textAlign: TextAlign.center,
                        style: TextStyle(
                          color: _color.withValues(alpha: _opacity),
                          fontSize: width * _fontFraction,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ]),
              );
            }))),
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
      Row(children: [
        const SizedBox(width: 16), const Text('Ink'),
        const SizedBox(width: 14),
        for (final color in [Colors.black, Colors.white,
            const Color(0xFF1244A2), const Color(0xFFE84545)])
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
      Padding(padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
        child: SizedBox(width: double.infinity, child: FilledButton.icon(
          onPressed: _busy || _label.text.trim().isEmpty ? null : _apply,
          icon: const Icon(Icons.check),
          label: const Text('Apply Watermark'),
          style: FilledButton.styleFrom(backgroundColor: dsTeal),
        )),
      ),
    ])),
  );

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
  static Future<Uint8List> composite(
    Uint8List original, {
    required String text,
    WatermarkPlacement placement = WatermarkPlacement.center,
    Color color = Colors.black,
    double opacity = .46,
    double fontFraction = .062,
  }) async {
    if (text.trim().isEmpty) throw ArgumentError('Watermark must not be empty');
    final codec = await ui.instantiateImageCodec(original);
    final frame = await codec.getNextFrame();
    final image = frame.image;
    try {
      final width = image.width.toDouble();
      final height = image.height.toDouble();
      final size = width < height ? width : height;
      final painter = TextPainter(
        text: TextSpan(text: text.trim(), style: TextStyle(
          color: color.withValues(alpha: opacity.clamp(0.0, 1.0).toDouble()),
          fontWeight: FontWeight.w700,
          fontSize: size * fontFraction.clamp(.025, .12),
        )),
        textAlign: TextAlign.center,
        textDirection: TextDirection.ltr,
        maxLines: 3,
      )..layout(maxWidth: width * .86);
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
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.drawImage(image, Offset.zero, Paint());
      painter.paint(canvas, Offset(x, y));
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
