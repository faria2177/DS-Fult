import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../services/image_text_processor.dart';
import '../storage/document_store.dart';
import 'video_tool_style.dart';

enum SmartEraseMode { pen, rectangle, magic, handwriting, text }

/// Reference-video editor with a real offline brush/rectangle processor.
/// It does not claim automatic AI handwriting segmentation.
class SmartEraseScreen extends StatefulWidget {
  const SmartEraseScreen({
    super.key, required this.store,
    required this.documentId, required this.pageId,
  });

  final DocumentStore store;
  final String documentId;
  final String pageId;

  @override
  State<SmartEraseScreen> createState() => _SmartEraseScreenState();
}

class _SmartEraseScreenState extends State<SmartEraseScreen> {
  Uint8List? _current;
  Uint8List? _original;
  double _aspect = .72;
  double _strokeRadius = .012;
  SmartEraseMode _mode = SmartEraseMode.pen;
  List<Offset> _stroke = [];
  final List<Uint8List> _undo = [];
  final List<Uint8List> _redo = [];
  bool _busy = false;
  bool _changed = false;
  bool _compare = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final doc = widget.store.byId(widget.documentId);
    final page = doc?.pages.where((p) => p.id == widget.pageId).firstOrNull;
    if (page == null) return;
    try {
      final bytes = await File(page.path).readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final aspect = frame.image.width / frame.image.height;
      frame.image.dispose();
      codec.dispose();
      if (mounted) {
        setState(() {
          _current = bytes;
          _original = bytes;
          _aspect = aspect;
        });
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Cannot open page: $error')));
      }
    }
  }

  Offset _normalise(Offset point, Size size) => Offset(
    (point.dx / size.width).clamp(0.0, 1.0).toDouble(),
    (point.dy / size.height).clamp(0.0, 1.0).toDouble(),
  );

  Future<void> _applyStroke() async {
    final current = _current;
    final points = _stroke;
    if (current == null || _busy || points.isEmpty) return;
    setState(() { _busy = true; _stroke = []; });
    try {
      Uint8List next;
      if ((_mode == SmartEraseMode.rectangle ||
              _mode == SmartEraseMode.text) && points.length > 1) {
        final rect = Rect.fromPoints(points.first, points.last);
        if (rect.width.abs() < .005 || rect.height.abs() < .005) return;
        next = await ImageTextProcessor.replace(current,
          normalizedArea: Rect.fromLTRB(
            rect.left.clamp(0.0, 1.0).toDouble(),
            rect.top.clamp(0.0, 1.0).toDouble(),
            rect.right.clamp(0.0, 1.0).toDouble(),
            rect.bottom.clamp(0.0, 1.0).toDouble()),
          replacement: '',
        );
      } else if (_mode == SmartEraseMode.rectangle ||
          _mode == SmartEraseMode.text) {
        // A rectangle needs two distinct endpoints; do not accidentally
        // erase with a brush after an incomplete drag.
        return;
      } else {
        next = await ImageTextProcessor.eraseBrush(current,
          normalizedPoints: points,
          normalizedRadius: _mode == SmartEraseMode.magic
              ? _strokeRadius * 1.35
              : _mode == SmartEraseMode.handwriting
                  ? _strokeRadius * .72
                  : _strokeRadius,
        );
      }
      if (mounted) {
        setState(() {
          _undo.add(current);
          if (_undo.length > 12) _undo.removeAt(0);
          _redo.clear();
          _current = next;
          _changed = true;
        });
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not erase selected area: $error')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _undoStroke() {
    if (_undo.isEmpty || _current == null || _busy) return;
    setState(() {
      _redo.add(_current!);
      _current = _undo.removeLast();
      _changed = _undo.isNotEmpty || _current != _original;
    });
  }

  void _redoStroke() {
    if (_redo.isEmpty || _current == null || _busy) return;
    setState(() {
      _undo.add(_current!);
      _current = _redo.removeLast();
      _changed = true;
    });
  }

  Future<void> _save() async {
    final current = _current;
    if (_busy || current == null) return;
    if (!_changed) { Navigator.pop(context); return; }
    setState(() => _busy = true);
    try {
      await widget.store.replacePageBytes(widget.documentId, widget.pageId,
          current, extension: '.png', filter: 'Smart Erase');
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not save changes: $error')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _cancel() async {
    if (_busy) return;
    if (!_changed) {
      Navigator.pop(context);
      return;
    }
    final discard = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Discard your edits?'),
        content: const Text(
          'Changes are not saved until you tap the check mark.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialog, false),
              child: const Text('Keep editing')),
          FilledButton(onPressed: () => Navigator.pop(dialog, true),
              child: const Text('Discard')),
        ],
      ),
    );
    if (mounted && discard == true) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) => VideoToolStyle.wrapDark(Scaffold(
    backgroundColor: const Color(0xFF29292C),
    body: SafeArea(child: Column(children: [
      // Reference-style tool selector. Every mode is wired to a real local
      // image-editing operation. Magic is an offline brush approximation,
      // not a proprietary content-aware AI inpainting model.
      Container(
        color: const Color(0xFF2C2C30),
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            PopupMenuButton<double>(
              tooltip: 'Pen and brush size',
              enabled: !_busy,
              onSelected: (radius) => setState(() {
                _mode = SmartEraseMode.pen;
                _strokeRadius = radius;
              }),
              itemBuilder: (_) => const [
                PopupMenuItem(value: .006, child: Text('Pen · Fine')),
                PopupMenuItem(value: .012, child: Text('Pen · Medium')),
                PopupMenuItem(value: .022, child: Text('Pen · Large')),
                PopupMenuItem(value: .033, child: Text('Pen · Extra large')),
              ],
              child: _toolFace(Icons.edit_outlined, 'Pen',
                selected: _mode == SmartEraseMode.pen, dropdown: true),
            ),
            _modeButton(SmartEraseMode.rectangle,
                Icons.crop_square_outlined, 'Rectangle'),
            _modeButton(SmartEraseMode.magic,
                Icons.auto_fix_high_outlined, 'Magic'),
            _modeButton(SmartEraseMode.handwriting,
                Icons.draw_outlined, 'Handwriting'),
            _modeButton(SmartEraseMode.text,
                Icons.text_fields_outlined, 'Erase Text'),
          ]),
        ),
      ),
      Container(
        height: 60,
        color: const Color(0xFF2C2C30),
        child: Row(children: [
          IconButton(
            tooltip: 'Cancel Smart Erase',
            onPressed: _busy ? null : _cancel,
            icon: const Icon(Icons.close, color: Colors.white, size: 30),
          ),
          const Expanded(child: Text('Smart Erase',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white, fontSize: 20))),
          IconButton(
            tooltip: 'Apply Smart Erase',
            onPressed: _busy || _current == null ? null : _save,
            icon: const Icon(Icons.check, color: Colors.white, size: 30),
          ),
        ]),
      ),
      if (_busy) const LinearProgressIndicator(),
      if (_undo.isNotEmpty || _redo.isNotEmpty)
        Row(children: [
          IconButton(tooltip: 'Undo', onPressed: _busy ? null : _undoStroke,
            icon: const Icon(Icons.undo, color: Colors.white)),
          IconButton(tooltip: 'Redo', onPressed: _busy ? null : _redoStroke,
            icon: const Icon(Icons.redo, color: Colors.white)),
          const Spacer(),
          IconButton(tooltip: 'Compare with original',
            onPressed: () => setState(() => _compare = !_compare),
            icon: const Icon(Icons.compare, color: Colors.white)),
        ]),
      Expanded(child: Center(child: _current == null
        ? const CircularProgressIndicator()
        : LayoutBuilder(builder: (context, bounds) {
            final width = (bounds.maxHeight * _aspect)
                .clamp(1.0, bounds.maxWidth).toDouble();
            final height = width / _aspect;
            final size = Size(width, height);
            return SizedBox(width: width, height: height,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                // A single tap is a valid Pen/Magic/Handwriting erasure.
                // Rectangles and text boxes still require a drag gesture.
                onTapUp: _busy || _compare ? null : (details) async {
                  if (_mode == SmartEraseMode.rectangle ||
                      _mode == SmartEraseMode.text) return;
                  setState(() {
                    _stroke = [_normalise(details.localPosition, size)];
                  });
                  await _applyStroke();
                },
                onPanStart: _busy || _compare ? null : (details) => setState(() {
                  _stroke = [_normalise(details.localPosition, size)];
                }),
                onPanCancel: _busy || _compare ? null :
                    () => setState(() => _stroke = []),
                onPanUpdate: _busy || _compare ? null : (details) {
                  final point = _normalise(details.localPosition, size);
                  if (_stroke.isEmpty) return;
                  if (_mode == SmartEraseMode.text ||
                      _mode == SmartEraseMode.rectangle) {
                    setState(() => _stroke = [_stroke.first, point]);
                  } else if ((point - _stroke.last).distance > .002) {
                    setState(() => _stroke.add(point));
                  }
                },
                onPanEnd: _busy || _compare ? null : (_) => _applyStroke(),
                child: Stack(fit: StackFit.expand, children: [
                  Image.memory(_compare ? _original! : _current!,
                    fit: BoxFit.fill, gaplessPlayback: true),
                  if (!_compare)
                    CustomPaint(painter: _EraseStrokePainter(
                      _stroke, _mode, _strokeRadius)),
                  if (_busy)
                    Container(color: Colors.black38,
                      child: const Center(child: Text('Removing selected area…',
                        style: TextStyle(color: Colors.white)))),
                ]),
              ),
            );
          }))),
      Container(color: VideoToolStyle.header,
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 5),
        child: Column(children: [
          Row(children: [
            const SizedBox(width: 72,
              child: Text('Stroke', textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white70, fontSize: 13))),
            Expanded(child: Slider(
              min: .004, max: .035, value: _strokeRadius,
              activeColor: VideoToolStyle.teal,
              onChanged: (value) => setState(() => _strokeRadius = value))),
          ]),
          const SizedBox(height: 5),
          Text(_mode == SmartEraseMode.text
              ? 'Drag a rectangle over printed text'
              : _mode == SmartEraseMode.rectangle
                  ? 'Drag a rectangle to remove the selected area'
                  : _mode == SmartEraseMode.handwriting
                      ? 'Brush over handwriting for local removal'
                      : _mode == SmartEraseMode.magic
                          ? 'Brush over a mark: locally match its background'
                          : 'Draw a brush stroke to erase the selected mark',
              style: const TextStyle(color: VideoToolStyle.muted,
                fontSize: 11)),
        ]),
      ),
    ])),
  ));

  Widget _toolFace(IconData icon, String label, {
    required bool selected, bool dropdown = false,
  }) => Container(
    width: 111,
    height: 70,
    margin: const EdgeInsets.symmetric(horizontal: 3),
    decoration: BoxDecoration(
      color: selected ? const Color(0xFF49494C) : Colors.transparent,
      borderRadius: BorderRadius.circular(10),
    ),
    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(icon, color: Colors.white, size: 29),
        if (dropdown) const Padding(
          padding: EdgeInsets.only(left: 5),
          child: Icon(Icons.arrow_drop_down, color: Colors.white, size: 19),
        ),
      ]),
      const SizedBox(height: 5),
      Text(label, style: const TextStyle(
        fontSize: 12, color: Colors.white)),
    ]),
  );

  Widget _modeButton(SmartEraseMode mode, IconData icon, String label) {
    final selected = _mode == mode;
    return InkWell(
      key: Key('smart-erase-${mode.name}'),
      onTap: _busy ? null : () => setState(() {
        _mode = mode;
        _stroke = [];
      }),
      child: _toolFace(icon, label, selected: selected),
    );
  }

}

class _EraseStrokePainter extends CustomPainter {
  const _EraseStrokePainter(this.points, this.mode, this.radius);

  final List<Offset> points;
  final SmartEraseMode mode;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) return;
    final paint = Paint()
      ..color = VideoToolStyle.teal.withValues(alpha: .48)
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke
      ..strokeWidth = radius * size.shortestSide * 2;
    Offset fromNormal(Offset p) => Offset(p.dx * size.width,
        p.dy * size.height);
    if ((mode == SmartEraseMode.text ||
         mode == SmartEraseMode.rectangle) && points.length > 1) {
      canvas.drawRect(Rect.fromPoints(fromNormal(points.first),
          fromNormal(points.last)), paint..style = PaintingStyle.fill);
    } else {
      final path = Path()..moveTo(fromNormal(points.first).dx,
          fromNormal(points.first).dy);
      for (final point in points.skip(1)) {
        final pos = fromNormal(point);
        path.lineTo(pos.dx, pos.dy);
      }
      canvas.drawPath(path, paint);
      canvas.drawCircle(fromNormal(points.first), paint.strokeWidth / 2,
          paint..style = PaintingStyle.fill);
    }
  }

  @override
  bool shouldRepaint(covariant _EraseStrokePainter old) =>
      old.points != points || old.mode != mode || old.radius != radius;
}
