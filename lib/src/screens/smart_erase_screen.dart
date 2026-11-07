import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../services/image_text_processor.dart';
import '../storage/document_store.dart';
import 'video_tool_style.dart';

enum SmartEraseMode { magic, handwriting, text }

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
  SmartEraseMode _mode = SmartEraseMode.magic;
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
      if (_mode == SmartEraseMode.text && points.length > 1) {
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
      } else {
        next = await ImageTextProcessor.eraseBrush(current,
          normalizedPoints: points,
          normalizedRadius: _strokeRadius,
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

  @override
  Widget build(BuildContext context) => VideoToolStyle.wrapDark(Scaffold(
    backgroundColor: const Color(0xFF38383B),
    appBar: AppBar(title: const Text('Smart Erase'), actions: [
      Padding(padding: const EdgeInsets.fromLTRB(0, 8, 12, 8),
        child: FilledButton(
          onPressed: _busy || _current == null ? null : _save,
          style: VideoToolStyle.tealButton,
          child: const Text('Save'),
        ),
      ),
    ]),
    body: SafeArea(child: Column(children: [
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
                onPanStart: _busy || _compare ? null : (details) => setState(() {
                  _stroke = [_normalise(details.localPosition, size)];
                }),
                onPanUpdate: _busy || _compare ? null : (details) {
                  final point = _normalise(details.localPosition, size);
                  if (_stroke.isEmpty) return;
                  if (_mode == SmartEraseMode.text) {
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
          Row(mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _modeButton(SmartEraseMode.magic, Icons.auto_fix_high, 'Magic'),
              _modeButton(SmartEraseMode.handwriting, Icons.draw, 'Handwriting'),
              _modeButton(SmartEraseMode.text, Icons.text_fields, 'Text'),
            ]),
          const SizedBox(height: 9),
          Text(_mode == SmartEraseMode.text
              ? 'Drag a box around text to remove it locally'
              : 'Brush over the unwanted area to remove it locally',
              style: const TextStyle(color: VideoToolStyle.muted,
                fontSize: 11)),
        ]),
      ),
    ])),
  ));

  Widget _modeButton(SmartEraseMode mode, IconData icon, String label) {
    final selected = _mode == mode;
    return InkWell(onTap: _busy ? null : () => setState(() => _mode = mode),
      child: Padding(padding: const EdgeInsets.symmetric(horizontal: 6,
        vertical: 4), child: Column(children: [
          Icon(icon, color: selected ? VideoToolStyle.teal : Colors.white,
            size: 25),
          const SizedBox(height: 5),
          Text(label, style: TextStyle(fontSize: 12,
            color: selected ? VideoToolStyle.teal : Colors.white)),
        ])),
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
    if (mode == SmartEraseMode.text && points.length > 1) {
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
