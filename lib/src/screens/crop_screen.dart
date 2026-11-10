import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../services/document_edges.dart';
import '../services/image_processor.dart';
import '../theme.dart';

class CropScreen extends StatefulWidget {
  const CropScreen({super.key, required this.imagePath,
      this.preferIdCardBounds = false});
  final String imagePath;
  final bool preferIdCardBounds;

  @override
  State<CropScreen> createState() => _CropScreenState();
}

class _CropScreenState extends State<CropScreen> {
  final List<Offset> _corners = [...CropQuad.inset().corners];
  Uint8List? _imageBytes;
  double _ratio = .7;
  bool _busy = false;
  bool _detecting = false;
  // Inset handles are only a draggable starting point. They must never cut
  // 5% off every edge when automatic detection failed and Done is tapped.
  bool _cropSelectionConfirmed = false;
  String _hint = 'Drag the four handles to adjust the document.';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final bytes = await File(widget.imagePath).readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final image = frame.image;
      final ratio = image.width / image.height;
      image.dispose();
      codec.dispose();
      if (!mounted) return;
      setState(() {
        _imageBytes = bytes;
        _ratio = ratio;
      });
      await _autoDetect();
    } catch (error) {
      if (mounted) setState(() => _hint = 'Could not load image: $error');
    }
  }

  Future<void> _autoDetect() async {
    if (_detecting || _busy || _imageBytes == null) return;
    setState(() => _detecting = true);
    try {
      final detected = await DocumentEdges.detectSafeStillOutline(widget.imagePath,
          preferIdCardBounds: widget.preferIdCardBounds);
      if (!mounted) return;
      final points = detected?.quad?.points;
      setState(() {
        if (points == null) {
          _hint = 'No reliable outer border. Drag the corners to crop; Done keeps the original unless you adjust them.';
        } else {
          _corners
            ..clear()
            ..addAll(points);
          _cropSelectionConfirmed = true;
          _hint = 'Four corners detected. Review edges before saving.';
        }
      });
    } catch (error) {
      if (mounted) {
        setState(() => _hint = 'Automatic detection unavailable. Drag corners manually.');
      }
    } finally {
      if (mounted) setState(() => _detecting = false);
    }
  }

  void _resetCorners() {
    setState(() {
      _corners
        ..clear()
        ..addAll(CropQuad.inset().corners);
      _cropSelectionConfirmed = false;
      _hint = 'Full photo restored. Drag corners to crop; Done keeps it unchanged if you do not adjust.';
    });
  }

  Future<void> _apply() async {
    if (_imageBytes == null || _busy || _detecting) return;
    if (!CropQuad(_corners).isValid) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('The four corners must form a valid document shape.'),
      ));
      return;
    }
    setState(() => _busy = true);
    try {
      final image = _cropSelectionConfirmed
          ? await ImageProcessor.process(_imageBytes!, crop: CropQuad(_corners))
          : _imageBytes!;
      if (mounted) Navigator.pop(context, image);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Crop failed: $error')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: const Color(0xFF101519),
        appBar: AppBar(
          backgroundColor: const Color(0xFF101519),
          foregroundColor: Colors.white,
          title: const Text('Adjust corners'),
          actions: [
            TextButton(onPressed: _busy || _detecting ? null : _apply, child: const Text('Done',
                style: TextStyle(color: dsTeal, fontWeight: FontWeight.bold))),
          ],
        ),
        body: SafeArea(child: Column(children: [
          Expanded(child: Center(child: LayoutBuilder(builder: (_, constraints) {
            final maxHeight = math.max(1, constraints.maxHeight - 32);
            final width = math.min(constraints.maxWidth - 24, maxHeight * _ratio);
            final height = width / _ratio;
            return SizedBox(
              width: width, height: height,
              child: _imageBytes == null
                  ? const Center(child: CircularProgressIndicator())
                  : Stack(children: [
                      Positioned.fill(child: Image.memory(_imageBytes!, fit: BoxFit.fill)),
                      Positioned.fill(child: CustomPaint(
                        painter: _CropOverlayPainter(_corners),
                      )),
                      for (var i = 0; i < 4; i++)
                        Positioned(
                          left: _corners[i].dx * width - 23,
                          top: _corners[i].dy * height - 23,
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onPanUpdate: (details) {
                              final candidate = [..._corners];
                              candidate[i] = Offset(
                                (_corners[i].dx + details.delta.dx / width).clamp(.0, 1.0),
                                (_corners[i].dy + details.delta.dy / height).clamp(.0, 1.0),
                              );
                              if (CropQuad(candidate).isValid) {
                                setState(() {
                                  _corners[i] = candidate[i];
                                  _cropSelectionConfirmed = true;
                                });
                              }
                            },
                            child: Container(
                              width: 46, height: 46,
                              alignment: Alignment.center,
                              child: Container(
                                width: 19, height: 19,
                                decoration: BoxDecoration(
                                  color: dsTeal,
                                  shape: BoxShape.circle,
                                  border: Border.all(color: Colors.white, width: 2),
                                ),
                              ),
                            ),
                          ),
                        ),
                    ]),
            );
          }))),
          if (_busy || _detecting) const LinearProgressIndicator(color: dsTeal),
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 12, 22, 28),
            child: Column(children: [
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                OutlinedButton.icon(
                  onPressed: _busy || _detecting || _imageBytes == null ? null : _autoDetect,
                  icon: const Icon(Icons.auto_fix_high_outlined),
                  label: const Text('Auto Detect'),
                ),
                const SizedBox(width: 12),
                OutlinedButton.icon(
                  onPressed: _busy || _detecting ? null : _resetCorners,
                  icon: const Icon(Icons.crop_free_outlined),
                  label: const Text('Reset'),
                ),
              ]),
              const SizedBox(height: 10),
              Text(_hint, textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70)),
            ]),
          ),
        ])),
      );
}

class _CropOverlayPainter extends CustomPainter {
  const _CropOverlayPainter(this.points);
  final List<Offset> points;

  @override
  void paint(Canvas canvas, Size size) {
    final mapped = points.map((p) => Offset(p.dx * size.width, p.dy * size.height)).toList();
    final path = Path()..moveTo(mapped[0].dx, mapped[0].dy);
    for (final point in mapped.skip(1)) {
      path.lineTo(point.dx, point.dy);
    }
    path.close();
    canvas.drawPath(path, Paint()
      ..color = const Color(0x2200B69B)
      ..style = PaintingStyle.fill);
    canvas.drawPath(path, Paint()
      ..color = dsTeal
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke);
    final linePen = Paint()..color = const Color(0xAAFFFFFF)..strokeWidth = .8;
    for (var i = 1; i < 3; i++) {
      final first = Offset.lerp(mapped[0], mapped[3], i / 3)!;
      final last = Offset.lerp(mapped[1], mapped[2], i / 3)!;
      canvas.drawLine(first, last, linePen);
      final top = Offset.lerp(mapped[0], mapped[1], i / 3)!;
      final bottom = Offset.lerp(mapped[3], mapped[2], i / 3)!;
      canvas.drawLine(top, bottom, linePen);
    }
  }

  @override
  bool shouldRepaint(covariant _CropOverlayPainter oldDelegate) => true;
}
