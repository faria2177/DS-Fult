import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

import '../storage/document_store.dart';
import '../theme.dart';

/// Drag an image region and apply irreversible block pixelation locally.
class MosaicScreen extends StatefulWidget {
  const MosaicScreen({super.key, required this.store,
      required this.documentId, required this.pageId});
  final DocumentStore store;
  final String documentId;
  final String pageId;

  @override
  State<MosaicScreen> createState() => _MosaicScreenState();
}

class _MosaicScreenState extends State<MosaicScreen> {
  String? _path;
  double _aspect = .75;
  Offset? _start;
  Rect? _selection;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final doc = widget.store.byId(widget.documentId);
    if (doc == null) return;
    final page = doc.pages.where((p) => p.id == widget.pageId).firstOrNull;
    if (page == null) return;
    final bytes = await File(page.path).readAsBytes();
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    final aspect = frame.image.width / frame.image.height;
    frame.image.dispose();
    codec.dispose();
    if (mounted) setState(() { _path = page.path; _aspect = aspect; });
  }

  Offset _normalize(Offset offset, Size size) => Offset(
    (offset.dx / size.width).clamp(0.0, 1.0),
    (offset.dy / size.height).clamp(0.0, 1.0),
  );

  Future<void> _apply() async {
    final path = _path;
    final selected = _selection;
    if (path == null || selected == null || _busy) return;
    if (selected.width < .01 || selected.height < .01) return;
    setState(() => _busy = true);
    try {
      final result = await compute(_pixelate, <String, Object>{
        'bytes': await File(path).readAsBytes(),
        'area': [selected.left, selected.top, selected.right, selected.bottom],
      });
      await widget.store.replacePageBytes(widget.documentId,
          widget.pageId, result);
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Mosaic failed: $error')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Mosaic')),
    body: SafeArea(child: Column(children: [
      if (_busy) const LinearProgressIndicator(color: dsTeal),
      const Padding(padding: EdgeInsets.all(12),
        child: Text('Drag over the text or area you want to pixelate. '
            'Then tap Apply. This permanently changes the image.')),
      Expanded(child: Center(child: _path == null
          ? const CircularProgressIndicator()
          : LayoutBuilder(builder: (context, bounds) {
              final width = (bounds.maxHeight * _aspect)
                  .clamp(1.0, bounds.maxWidth).toDouble();
              final height = width / _aspect;
              final size = Size(width, height);
              return SizedBox(width: width, height: height,
                child: GestureDetector(
                  onPanStart: (details) => setState(() {
                    _start = _normalize(details.localPosition, size);
                    _selection = null;
                  }),
                  onPanUpdate: (details) {
                    final start = _start;
                    if (start == null) return;
                    final now = _normalize(details.localPosition, size);
                    setState(() => _selection = Rect.fromPoints(start, now));
                  },
                  child: Stack(fit: StackFit.expand, children: [
                    Image.file(File(_path!), fit: BoxFit.fill),
                    CustomPaint(painter: _MosaicSelectionPainter(_selection)),
                  ]),
                ),
              );
            }))),
      Padding(padding: const EdgeInsets.all(16), child: SizedBox(
        width: double.infinity, child: FilledButton.icon(
          onPressed: _selection == null || _busy ? null : _apply,
          icon: const Icon(Icons.blur_on), label: const Text('Apply Mosaic'),
        ),
      )),
    ])),
  );
}

class _MosaicSelectionPainter extends CustomPainter {
  const _MosaicSelectionPainter(this.selection);
  final Rect? selection;

  @override
  void paint(Canvas canvas, Size size) {
    final area = selection;
    if (area == null) return;
    final bounds = Rect.fromLTRB(area.left * size.width,
      area.top * size.height, area.right * size.width,
      area.bottom * size.height);
    canvas.drawRect(bounds, Paint()..color = dsTeal.withValues(alpha: .18));
    canvas.drawRect(bounds, Paint()
      ..color = dsTeal ..style = PaintingStyle.stroke ..strokeWidth = 2);
  }

  @override
  bool shouldRepaint(_MosaicSelectionPainter old) => old.selection != selection;
}

@visibleForTesting
Uint8List mosaicImageBytes(Uint8List bytes, Rect area, {int block = 18}) =>
    _pixelate({'bytes': bytes, 'area': [area.left, area.top,
        area.right, area.bottom], 'block': block});

Uint8List _pixelate(Map<String, Object> args) {
  final decoded = img.decodeImage(args['bytes']! as Uint8List);
  if (decoded == null) throw const FormatException('Unsupported image');
  final image = img.bakeOrientation(decoded);
  final coords = args['area']! as List<double>;
  final x1 = (coords[0] * image.width).floor().clamp(0, image.width - 1).toInt();
  final y1 = (coords[1] * image.height).floor().clamp(0, image.height - 1).toInt();
  final x2 = (coords[2] * image.width).ceil().clamp(0, image.width).toInt();
  final y2 = (coords[3] * image.height).ceil().clamp(0, image.height).toInt();
  final block = (args['block'] as int? ?? 18).clamp(4, 80).toInt();
  for (var y = y1; y < y2; y += block) {
    for (var x = x1; x < x2; x += block) {
      final sample = image.getPixel(x, y);
      final color = img.ColorRgb8(sample.r.toInt(), sample.g.toInt(),
          sample.b.toInt());
      img.fillRect(image, x1: x, y1: y,
          x2: (x + block - 1).clamp(x, x2 - 1).toInt(),
          y2: (y + block - 1).clamp(y, y2 - 1).toInt(), color: color);
    }
  }
  return Uint8List.fromList(img.encodeJpg(image, quality: 95));
}
