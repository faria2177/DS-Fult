import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../services/image_processor.dart';
import '../theme.dart';

class CropScreen extends StatefulWidget {
  const CropScreen({super.key, required this.imagePath});
  final String imagePath;

  @override
  State<CropScreen> createState() => _CropScreenState();
}

class _CropScreenState extends State<CropScreen> {
  final List<Offset> _corners = [...CropQuad.inset().corners];
  Uint8List? _imageBytes;
  double _ratio = .7;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final bytes = await File(widget.imagePath).readAsBytes();
    final image = await ui.decodeImageFromList(bytes);
    final ratio = image.width / image.height;
    image.dispose();
    if (mounted) setState(() {
      _imageBytes = bytes;
      _ratio = ratio;
    });
  }

  Future<void> _apply() async {
    if (_imageBytes == null || _busy) return;
    setState(() => _busy = true);
    try {
      final image = await ImageProcessor.process(_imageBytes!, crop: CropQuad(_corners));
      if (mounted) Navigator.pop(context, image);
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Crop failed: $error')));
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
            TextButton(onPressed: _busy ? null : _apply, child: const Text('Done',
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
                            onPanUpdate: (details) => setState(() {
                              _corners[i] = Offset(
                                (_corners[i].dx + details.delta.dx / width).clamp(.0, 1.0),
                                (_corners[i].dy + details.delta.dy / height).clamp(.0, 1.0),
                              );
                            }),
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
          if (_busy) const LinearProgressIndicator(color: dsTeal),
          const Padding(
            padding: EdgeInsets.fromLTRB(30, 18, 30, 28),
            child: Text('Drag all four corners to the document edges.',
                textAlign: TextAlign.center, style: TextStyle(color: Colors.white70)),
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
