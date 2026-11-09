import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../storage/document_store.dart';
import 'video_tool_style.dart';

/// Draws a visible handwritten signature over an image-backed document page.
/// This is an electronic image signature, not an X.509 PDF digital signature.
class SignatureScreen extends StatefulWidget {
  const SignatureScreen({
    super.key,
    required this.store,
    required this.documentId,
    required this.pageId,
    this.brushMode = false,
  });

  final DocumentStore store;
  final String documentId;
  final String pageId;
  final bool brushMode;

  @override
  State<SignatureScreen> createState() => _SignatureScreenState();
}

class _SignatureScreenState extends State<SignatureScreen> {
  final List<List<Offset>> _strokes = [];
  final List<Color> _strokeColors = [];
  final List<double> _strokeScales = [];
  List<Offset>? _activeStroke;
  String? _path;
  double _aspectRatio = 0.72;
  Color _ink = Colors.black;
  double _strokeScale = .006;
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
      final ratio = frame.image.width / frame.image.height;
      frame.image.dispose();
      codec.dispose();
      if (mounted) setState(() { _path = page.path; _aspectRatio = ratio; });
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Cannot load page: $error')));
      }
    }
  }

  Offset _normalize(Offset local, Size size) => Offset(
    (local.dx / size.width).clamp(0.0, 1.0),
    (local.dy / size.height).clamp(0.0, 1.0),
  );

  void _start(DragStartDetails details, Size size) {
    if (_busy) return;
    setState(() => _activeStroke = [_normalize(details.localPosition, size)]);
  }

  void _update(DragUpdateDetails details, Size size) {
    final active = _activeStroke;
    if (_busy || active == null) return;
    setState(() => active.add(_normalize(details.localPosition, size)));
  }

  void _finish() {
    final active = _activeStroke;
    if (active == null) return;
    setState(() {
      if (active.isNotEmpty) {
        _strokes.add(List.of(active));
        _strokeColors.add(_ink);
        _strokeScales.add(_strokeScale);
      }
      _activeStroke = null;
    });
  }

  void _undo() {
    if (_busy || _strokes.isEmpty) return;
    setState(() {
      _strokes.removeLast();
      _strokeColors.removeLast();
      _strokeScales.removeLast();
    });
  }

  Future<void> _save() async {
    final path = _path;
    if (path == null || _busy || _strokes.isEmpty) return;
    setState(() => _busy = true);
    try {
      final bytes = await File(path).readAsBytes();
      final encoded = await SignatureComposer.composite(
        bytes, _strokes,
        inkColor: _ink,
        strokeColors: _strokeColors,
        strokeScales: _strokeScales,
      );
      await widget.store.replacePageBytes(
        widget.documentId,
        widget.pageId,
        encoded,
        extension: '.png',
      );
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not save signature: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Theme(data: VideoToolStyle.dark, child: Scaffold(
    appBar: AppBar(
      title: Text(widget.brushMode ? 'Brush' : 'Sign PDF'),
      actions: [
        IconButton(onPressed: _strokes.isEmpty || _busy ? null : _undo,
            tooltip: 'Undo last stroke', icon: const Icon(Icons.undo)),
        IconButton(onPressed: _strokes.isEmpty || _busy ? null :
            () => setState(() {
              _strokes.clear();
              _strokeColors.clear();
              _strokeScales.clear();
            }),
            tooltip: 'Clear signature', icon: const Icon(Icons.delete_outline)),
      ],
    ),
    body: SafeArea(child: Column(children: [
      if (_busy) const LinearProgressIndicator(),
      Container(
        width: double.infinity,
        color: VideoToolStyle.header,
        padding: const EdgeInsets.fromLTRB(18, 13, 18, 16),
        child: Row(children: [
          Container(width: 44, height: 44,
            decoration: BoxDecoration(color: VideoToolStyle.teal
                .withValues(alpha: .15),
              borderRadius: BorderRadius.circular(13)),
            child: const Icon(Icons.draw_outlined,
                color: VideoToolStyle.teal)),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
            children: [
            Text(widget.brushMode ? 'Draw on document' : 'Add your signature',
              style: const TextStyle(fontSize: 17,
                  fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(widget.brushMode
                ? 'Draw directly on the page using your finger.'
                : 'Sign on the page. Preview each stroke before applying.',
              style: const TextStyle(color: VideoToolStyle.muted,
                  fontSize: 12)),
          ])),
        ]),
      ),
      Expanded(child: Container(
        color: VideoToolStyle.background,
        padding: const EdgeInsets.all(12),
        child: Center(child: _path == null
          ? const CircularProgressIndicator()
          : LayoutBuilder(builder: (context, constraints) {
              final width = (constraints.maxHeight * _aspectRatio)
                  .clamp(1.0, constraints.maxWidth).toDouble();
              final height = width / _aspectRatio;
              final size = Size(width, height);
              return SizedBox(
                width: width,
                height: height,
                child: Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: VideoToolStyle.teal
                        .withValues(alpha: .4), width: 1.2),
                  ),
                  child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onPanStart: (details) => _start(details, size),
                  onPanUpdate: (details) => _update(details, size),
                  onPanEnd: (_) => _finish(),
                  onPanCancel: _finish,
                  child: Stack(fit: StackFit.expand, children: [
                    Image.file(File(_path!), fit: BoxFit.fill),
                    CustomPaint(painter: SignaturePainter(
                      strokes: [..._strokes, ?_activeStroke],
                      inkColor: _ink,
                      strokeColors: [..._strokeColors,
                        if (_activeStroke != null) _ink],
                      strokeScales: [..._strokeScales,
                        if (_activeStroke != null) _strokeScale],
                    )),
                  ]),
                  ),
                ),
              );
            })),
      )),
      Container(
        padding: const EdgeInsets.fromLTRB(18, 13, 18, 15),
        decoration: const BoxDecoration(color: VideoToolStyle.header,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
        child: Column(mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Expanded(child: Text('Ink color',
              style: TextStyle(fontWeight: FontWeight.w700))),
            TextButton.icon(
              onPressed: _busy || _strokes.isEmpty ? null : _undo,
              icon: const Icon(Icons.undo, size: 19), label: const Text('Undo')),
            TextButton.icon(
              onPressed: _busy || _strokes.isEmpty ? null : () => setState(() {
                _strokes.clear();
                _strokeColors.clear();
                _strokeScales.clear();
              }),
              icon: const Icon(Icons.delete_outline, size: 19),
              label: const Text('Clear')),
          ]),
          const SizedBox(height: 4),
          Row(children: [
            for (final entry in <(String, Color)>[
              ('Black', Colors.black),
              ('Blue', const Color(0xFF1244A2)),
              ('Red', const Color(0xFFDD3246)),
              ('Green', const Color(0xFF008F68)),
              if (widget.brushMode) ('White', Colors.white),
            ]) ...[
              Semantics(label: '${entry.$1} ink', button: true,
                selected: _ink == entry.$2,
                child: InkWell(
                  onTap: _busy ? null : () => setState(() => _ink = entry.$2),
                  borderRadius: BorderRadius.circular(30),
                  child: Container(width: 40, height: 40,
                    margin: const EdgeInsets.only(right: 12),
                    decoration: BoxDecoration(color: entry.$2,
                      shape: BoxShape.circle,
                      border: Border.all(color: _ink == entry.$2
                          ? VideoToolStyle.teal : Colors.white38,
                          width: _ink == entry.$2 ? 3 : 1)),
                    child: _ink == entry.$2 ? const Icon(Icons.check,
                      size: 19, color: Colors.white) : null,
                  ),
                )),
            ],
          ]),
          const SizedBox(height: 10),
          Row(children: [
            const Text('Pen size', style: TextStyle(fontSize: 13)),
            const SizedBox(width: 8),
            const Icon(Icons.circle, size: 7),
            Expanded(child: Slider(
              value: _strokeScale, min: .002, max: .025,
              activeColor: VideoToolStyle.teal,
              onChanged: _busy ? null : (size) => setState(() =>
                  _strokeScale = size),
            )),
            const Icon(Icons.circle, size: 19),
          ]),
          const SizedBox(height: 5),
          SizedBox(width: double.infinity, child: FilledButton.icon(
          onPressed: _busy || _strokes.isEmpty ? null : _save,
          icon: const Icon(Icons.check),
          label: Text(_busy ? 'Applying…' : widget.brushMode
              ? 'Apply Brush' : 'Apply Signature'),
          style: VideoToolStyle.tealButton,
          )),
        ]),
      ),
    ])),
  ));
}

/// One painter is used for the on-screen preview and final full-resolution
/// output. Coordinates are always normalized to the original page dimensions.
class SignaturePainter extends CustomPainter {
  const SignaturePainter({required this.strokes, required this.inkColor,
      this.strokeColors, this.strokeScales});

  final List<List<Offset>> strokes;
  final Color inkColor;
  final List<Color>? strokeColors;
  final List<double>? strokeScales;

  @override
  void paint(Canvas canvas, Size size) {
    for (var index = 0; index < strokes.length; index++) {
      final stroke = strokes[index];
      if (stroke.isEmpty) continue;
      final color = strokeColors != null && index < strokeColors!.length
          ? strokeColors![index] : inkColor;
      final scale = strokeScales != null && index < strokeScales!.length
          ? strokeScales![index] : .006;
      final pen = Paint()
        ..color = color
        ..strokeWidth = (size.shortestSide * scale).clamp(1.5, 75.0).toDouble()
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke;
      final first = Offset(stroke.first.dx * size.width,
          stroke.first.dy * size.height);
      final path = Path()..moveTo(first.dx, first.dy);
      if (stroke.length == 1) {
        canvas.drawCircle(first, pen.strokeWidth / 2, Paint()..color = color);
      } else {
        for (final point in stroke.skip(1)) {
          path.lineTo(point.dx * size.width, point.dy * size.height);
        }
        canvas.drawPath(path, pen);
      }
    }
  }

  @override
  bool shouldRepaint(SignaturePainter old) =>
      old.strokes != strokes || old.inkColor != inkColor ||
      old.strokeColors != strokeColors || old.strokeScales != strokeScales;
}

class SignatureComposer {
  /// Renders signature strokes onto a copy of the source page image.
  static Future<Uint8List> composite(
    Uint8List original,
    List<List<Offset>> strokes, {
    Color inkColor = Colors.black,
    List<Color>? strokeColors,
    List<double>? strokeScales,
  }) async {
    final codec = await ui.instantiateImageCodec(original);
    final frame = await codec.getNextFrame();
    final source = frame.image;
    try {
      final size = Size(source.width.toDouble(), source.height.toDouble());
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.drawImage(source, Offset.zero, Paint());
      SignaturePainter(strokes: strokes, inkColor: inkColor,
          strokeColors: strokeColors, strokeScales: strokeScales)
          .paint(canvas, size);
      final output = await recorder.endRecording()
          .toImage(source.width, source.height);
      try {
        final data = await output.toByteData(format: ui.ImageByteFormat.png);
        if (data == null) throw StateError('Unable to encode signed page');
        return data.buffer.asUint8List();
      } finally {
        output.dispose();
      }
    } finally {
      source.dispose();
      codec.dispose();
    }
  }
}
