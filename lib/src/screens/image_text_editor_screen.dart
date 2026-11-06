import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../services/image_text_processor.dart';
import '../storage/document_store.dart';
import '../theme.dart';

class DetectedTextRegion {
  const DetectedTextRegion(this.bounds, this.text);

  /// Image coordinates normalized to 0..1.
  final Rect bounds;
  final String text;
}

enum _EditMode { select, add, erase }

/// Edit text directly in the document image, with tap-to-select OCR bounds.
/// Bengali OCR provides transcript text but (currently) no word coordinates;
/// users can insert Bengali by tapping the desired position in Add mode.
class ImageTextEditorScreen extends StatefulWidget {
  const ImageTextEditorScreen({
    super.key,
    required this.store,
    required this.documentId,
    required this.pageId,
    required this.regions,
  });

  final DocumentStore store;
  final String documentId;
  final String pageId;
  final List<DetectedTextRegion> regions;

  @override
  State<ImageTextEditorScreen> createState() => _ImageTextEditorScreenState();
}

class _ImageTextEditorScreenState extends State<ImageTextEditorScreen> {
  _EditMode _mode = _EditMode.select;
  double _aspect = .70;
  String? _path;
  bool _busy = false;
  Rect? _drag;
  Offset? _dragStart;
  final List<Uint8List> _undo = [];

  @override
  void initState() {
    super.initState();
    _loadPage();
  }

  Future<void> _loadPage() async {
    final doc = widget.store.byId(widget.documentId);
    final page = doc?.pages.where((p) => p.id == widget.pageId).firstOrNull;
    if (page == null) return;
    final bytes = await File(page.path).readAsBytes();
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    final aspect = frame.image.width / frame.image.height;
    frame.image.dispose();
    codec.dispose();
    if (!mounted) return;
    setState(() {
      _path = page.path;
      _aspect = aspect;
    });
  }

  void _tap(TapDownDetails details, Size size) {
    if (_busy) return;
    final point = Offset(
      (details.localPosition.dx / size.width).clamp(0.0, 1.0),
      (details.localPosition.dy / size.height).clamp(0.0, 1.0),
    );
    if (_mode == _EditMode.erase) return;
    final matching = widget.regions.where((r) => r.bounds.inflate(.012).contains(point));
    final region = _mode == _EditMode.select && matching.isNotEmpty
        ? matching.first
        : DetectedTextRegion(
            Rect.fromLTWH(point.dx.clamp(0.0, .50),
                point.dy.clamp(0.0, .91), .49, .08),
            '',
          );
    _promptReplace(region);
  }

  Future<void> _promptReplace(DetectedTextRegion region) async {
    final controller = TextEditingController(text: region.text);
    final replacement = await showDialog<String>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Replace text on image'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 4,
          decoration: const InputDecoration(
            hintText: 'Type English or বাংলা text',
            helperText: 'Blank text removes the selected region',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialog),
              child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dialog, controller.text),
              child: const Text('Apply')),
        ],
      ),
    );
    controller.dispose();
    if (replacement != null) await _apply(region.bounds, replacement);
  }

  Future<void> _apply(Rect bounds, String replacement) async {
    final path = _path;
    if (path == null || _busy) return;
    setState(() => _busy = true);
    try {
      final previous = await File(path).readAsBytes();
      final modified = await ImageTextProcessor.replace(
        previous,
        normalizedArea: bounds,
        replacement: replacement,
      );
      await widget.store.replacePageBytes(
        widget.documentId,
        widget.pageId,
        modified,
        extension: '.png',
      );
      _undo.add(previous);
      if (_undo.length > 3) _undo.removeAt(0);
      await _loadPage();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Image edit failed: $error')));
      }
    } finally {
      if (mounted) setState(() { _busy = false; _drag = null; });
    }
  }

  Future<void> _restore() async {
    if (_undo.isEmpty || _busy) return;
    final previous = _undo.removeLast();
    setState(() => _busy = true);
    try {
      final extension = previous.length > 3 && previous[0] == 0x89 &&
              previous[1] == 0x50
          ? '.png'
          : '.jpg';
      await widget.store.replacePageBytes(widget.documentId, widget.pageId,
          previous, extension: extension);
      await _loadPage();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Edit on Image'), actions: [
      IconButton(tooltip: 'Undo', onPressed: _undo.isEmpty ? null : _restore,
          icon: const Icon(Icons.undo)),
      TextButton(onPressed: () => Navigator.pop(context),
          child: const Text('Done', style: TextStyle(color: dsTeal))),
    ]),
    body: SafeArea(child: Column(children: [
      if (_busy) const LinearProgressIndicator(),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Text(
          switch (_mode) {
            _EditMode.select => 'Tap an outlined OCR line to replace it',
            _EditMode.add => 'Tap any location to add English or বাংলা text',
            _EditMode.erase => 'Drag a rectangle to erase marks or text',
          },
          style: const TextStyle(color: dsMuted),
        ),
      ),
      Expanded(child: Center(child: _path == null
          ? const CircularProgressIndicator()
          : LayoutBuilder(builder: (context, available) {
              final maxHeight = available.maxHeight;
              final maxWidth = available.maxWidth;
              final width = (maxHeight * _aspect).clamp(1.0, maxWidth);
              final height = width / _aspect;
              final size = Size(width, height);
              return SizedBox(
                width: width,
                height: height,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapDown: (details) => _tap(details, size),
                  onPanStart: _mode != _EditMode.erase ? null : (details) {
                    _dragStart = Offset(details.localPosition.dx / width,
                        details.localPosition.dy / height);
                  },
                  onPanUpdate: _mode != _EditMode.erase ? null : (details) {
                    final start = _dragStart;
                    if (start == null) return;
                    final point = Offset(details.localPosition.dx / width,
                        details.localPosition.dy / height);
                    setState(() => _drag = Rect.fromPoints(start, point));
                  },
                  onPanEnd: _mode != _EditMode.erase ? null : (_) {
                    final rect = _drag;
                    _dragStart = null;
                    if (rect != null && rect.width.abs() > .01 &&
                        rect.height.abs() > .01) {
                      _apply(Rect.fromLTRB(
                        rect.left.clamp(0.0, 1.0),
                        rect.top.clamp(0.0, 1.0),
                        rect.right.clamp(0.0, 1.0),
                        rect.bottom.clamp(0.0, 1.0),
                      ), '');
                    }
                  },
                  child: Stack(fit: StackFit.expand, children: [
                    Image.file(File(_path!), key: ValueKey(_path),
                        fit: BoxFit.fill),
                    CustomPaint(painter: _TextRegionsPainter(
                        _mode == _EditMode.select ? widget.regions : const [],
                        _drag)),
                  ]),
                ),
              );
            }))),
      const SizedBox(height: 10),
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 18),
        child: SegmentedButton<_EditMode>(
          selected: {_mode},
          onSelectionChanged: (value) => setState(() => _mode = value.first),
          segments: const [
            ButtonSegment(value: _EditMode.select, icon: Icon(Icons.touch_app_outlined),
                label: Text('Replace')),
            ButtonSegment(value: _EditMode.add, icon: Icon(Icons.text_fields),
                label: Text('Add')),
            ButtonSegment(value: _EditMode.erase, icon: Icon(Icons.auto_fix_normal),
                label: Text('Erase')),
          ],
        ),
      ),
    ])),
  );
}

class _TextRegionsPainter extends CustomPainter {
  const _TextRegionsPainter(this.regions, this.drag);
  final List<DetectedTextRegion> regions;
  final Rect? drag;

  @override
  void paint(Canvas canvas, Size size) {
    final outline = Paint()
      ..color = dsTeal
      ..strokeWidth = 1.8
      ..style = PaintingStyle.stroke;
    final fill = Paint()..color = dsTeal.withValues(alpha: .10);
    for (final region in regions) {
      final rect = Rect.fromLTRB(region.bounds.left * size.width,
          region.bounds.top * size.height, region.bounds.right * size.width,
          region.bounds.bottom * size.height);
      canvas.drawRect(rect, fill);
      canvas.drawRect(rect, outline);
    }
    if (drag != null) {
      final rect = Rect.fromLTRB(drag!.left * size.width, drag!.top * size.height,
          drag!.right * size.width, drag!.bottom * size.height);
      canvas.drawRect(rect, Paint()..color = Colors.orange.withValues(alpha: .25));
      canvas.drawRect(rect, Paint()
        ..color = Colors.orange
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke);
    }
  }

  @override
  bool shouldRepaint(covariant _TextRegionsPainter oldDelegate) =>
      oldDelegate.regions != regions || oldDelegate.drag != drag;
}
