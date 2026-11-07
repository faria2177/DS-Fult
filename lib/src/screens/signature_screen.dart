import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../storage/document_store.dart';
import '../theme.dart';

/// Draws a visible handwritten signature over an image-backed document page.
/// This is an electronic image signature, not an X.509 PDF digital signature.
class SignatureScreen extends StatefulWidget {
  const SignatureScreen({
    super.key,
    required this.store,
    required this.documentId,
    required this.pageId,
  });

  final DocumentStore store;
  final String documentId;
  final String pageId;

  @override
  State<SignatureScreen> createState() => _SignatureScreenState();
}

class _SignatureScreenState extends State<SignatureScreen> {
  final List<List<Offset>> _strokes = [];
  List<Offset>? _activeStroke;
  String? _path;
  double _aspectRatio = 0.72;
  Color _ink = Colors.black;
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
      if (active.isNotEmpty) _strokes.add(List.of(active));
      _activeStroke = null;
    });
  }

  void _undo() {
    if (_busy || _strokes.isEmpty) return;
    setState(() => _strokes.removeLast());
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
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Sign Document'),
      actions: [
        IconButton(onPressed: _strokes.isEmpty || _busy ? null : _undo,
            tooltip: 'Undo last stroke', icon: const Icon(Icons.undo)),
        IconButton(onPressed: _strokes.isEmpty || _busy ? null :
            () => setState(() => _strokes.clear()),
            tooltip: 'Clear signature', icon: const Icon(Icons.delete_outline)),
      ],
    ),
    body: SafeArea(child: Column(children: [
      if (_busy) const LinearProgressIndicator(),
      const Padding(
        padding: EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: Text('Draw your signature on the page with a finger. '
            'Changes are saved only when you tap Apply.',
            textAlign: TextAlign.center, style: TextStyle(color: dsMuted)),
      ),
      Expanded(child: Center(child: _path == null
          ? const CircularProgressIndicator()
          : LayoutBuilder(builder: (context, constraints) {
              final width = (constraints.maxHeight * _aspectRatio)
                  .clamp(1.0, constraints.maxWidth).toDouble();
              final height = width / _aspectRatio;
              final size = Size(width, height);
              return SizedBox(
                width: width,
                height: height,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onPanStart: (details) => _start(details, size),
                  onPanUpdate: (details) => _update(details, size),
                  onPanEnd: (_) => _finish(),
                  onPanCancel: _finish,
                  child: Stack(fit: StackFit.expand, children: [
                    Image.file(File(_path!), fit: BoxFit.fill),
                    CustomPaint(painter: SignaturePainter(
                      strokes: [..._strokes, if (_activeStroke != null) _activeStroke!],
                      inkColor: _ink,
                    )),
                  ]),
                ),
              );
            }))),
      Padding(
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 6),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          const Text('Ink:'),
          const SizedBox(width: 14),
          for (final color in [Colors.black, const Color(0xFF1244A2)])
            Padding(
              padding: const EdgeInsets.only(right: 10),
              child: InkWell(
                borderRadius: BorderRadius.circular(28),
                onTap: () => setState(() => _ink = color),
                child: CircleAvatar(
                  backgroundColor: color,
                  radius: _ink == color ? 19 : 16,
                  child: _ink == color
                      ? const Icon(Icons.check, size: 18, color: Colors.white)
                      : null,
                ),
              ),
            ),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 20),
        child: FilledButton.icon(
          onPressed: _busy || _strokes.isEmpty ? null : _save,
          icon: const Icon(Icons.check),
          label: Text(_busy ? 'Applying…' : 'Apply Signature'),
          style: FilledButton.styleFrom(backgroundColor: dsTeal,
              minimumSize: const Size(double.infinity, 50)),
        ),
      ),
    ])),
  );
}

/// One painter is used for the on-screen preview and final full-resolution
/// output. Coordinates are always normalized to the original page dimensions.
class SignaturePainter extends CustomPainter {
  const SignaturePainter({required this.strokes, required this.inkColor});

  final List<List<Offset>> strokes;
  final Color inkColor;

  @override
  void paint(Canvas canvas, Size size) {
    final pen = Paint()
      ..color = inkColor
      ..strokeWidth = (size.shortestSide * .006).clamp(1.5, 18.0).toDouble()
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    for (final stroke in strokes) {
      if (stroke.isEmpty) continue;
      final first = Offset(stroke.first.dx * size.width,
          stroke.first.dy * size.height);
      final path = Path()..moveTo(first.dx, first.dy);
      if (stroke.length == 1) {
        canvas.drawCircle(first, pen.strokeWidth / 2, Paint()..color = inkColor);
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
      old.strokes != strokes || old.inkColor != inkColor;
}

class SignatureComposer {
  /// Renders signature strokes onto a copy of the source page image.
  static Future<Uint8List> composite(
    Uint8List original,
    List<List<Offset>> strokes, {
    Color inkColor = Colors.black,
  }) async {
    final codec = await ui.instantiateImageCodec(original);
    final frame = await codec.getNextFrame();
    final source = frame.image;
    try {
      final size = Size(source.width.toDouble(), source.height.toDouble());
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.drawImage(source, Offset.zero, Paint());
      SignaturePainter(strokes: strokes, inkColor: inkColor)
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
