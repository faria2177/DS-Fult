import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../services/document_edges.dart';
import '../services/image_processor.dart';
import '../theme.dart';

/// Editable crop state is kept separately for every page. Moving to another
/// page never discards the current four-corner adjustment or rotation.
class BatchCropPageState {
  BatchCropPageState()
      : corners = [...CropQuad.inset().corners];

  final List<Offset> corners;
  int turns = 0;
  bool confirmed = false;
  // Initial machine detection is only a suggestion. Re-editing a previously
  // saved ID must never overwrite a side the user did not touch.
  bool touched = false;

  bool updateHandle(int handle, Offset delta) {
    final proposal = [...corners];
    if (handle < 4) {
      proposal[handle] += delta;
    } else {
      final a = handle - 4;
      final b = (a + 1) % 4;
      proposal[a] += delta;
      proposal[b] += delta;
    }
    // Reject crossed, inverted or off-image quads while dragging any of the
    // four corner or four edge-midpoint handles.
    if (!CropQuad(proposal).isValid) return false;
    corners..clear()..addAll(proposal);
    confirmed = true;
    touched = true;
    return true;
  }

  List<Offset> get handles => [
    ...corners,
    for (var edge = 0; edge < 4; edge++)
      Offset.lerp(corners[edge], corners[(edge + 1) % 4], .5)!,
  ];
}

class BatchCropScreen extends StatefulWidget {
  const BatchCropScreen({super.key, required this.imagePaths,
      this.initialIndex = 0, this.preferIdCardBounds = false,
      this.onlyEdited = false, this.sideLabels = const <String>[],
      this.comparisonPaths = const <String>[]});

  final List<String> imagePaths;
  final int initialIndex;
  final bool preferIdCardBounds;
  /// Preserve every existing saved/filtered side unless the user actually
  /// dragged a handle, rotated it, or explicitly requested Auto Crop.
  final bool onlyEdited;
  final List<String> sideLabels;
  final List<String> comparisonPaths;

  @override
  State<BatchCropScreen> createState() => _BatchCropScreenState();
}

class _BatchCropScreenState extends State<BatchCropScreen> {
  late final List<BatchCropPageState> _edits = [
    for (var i = 0; i < widget.imagePaths.length; i++) BatchCropPageState(),
  ];
  final Map<int, Uint8List> _bytes = {};
  final Map<int, double> _ratios = {};
  int _index = 0;
  bool _working = false;
  String _hint = 'Drag the four corners or edge handles.';

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex.clamp(0,
        math.max(0, widget.imagePaths.length - 1)).toInt();
    _load(_index);
  }

  Future<void> _load(int index) async {
    if (_working || _bytes.containsKey(index)) return;
    setState(() => _working = true);
    try {
      final bytes = await File(widget.imagePaths[index]).readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final ratio = frame.image.width / frame.image.height;
      frame.image.dispose();
      codec.dispose();
      if (!mounted) return;
      setState(() { _bytes[index] = bytes; _ratios[index] = ratio; });
      await _detect(index);
    } catch (_) {
      if (mounted) {
        setState(() => _hint =
            'Unable to load this page. The original is unchanged.');
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _detect(int index, {bool requested = false}) async {
    try {
      final result = await DocumentEdges.detectSafeStillOutline(
          widget.imagePaths[index],
          preferIdCardBounds: widget.preferIdCardBounds);
      if (!mounted) return;
      final points = result?.quad?.points;
      if (points == null) {
        if (index == _index) {
          setState(() => _hint =
              'No reliable outside border. Adjust manually or keep the original.');
        }
      } else {
        setState(() {
          _edits[index].corners..clear()..addAll(points);
          _edits[index].confirmed = true;
          if (requested) _edits[index].touched = true;
          if (index == _index) _hint = 'Outside corners found. Review before Done.';
        });
      }
    } catch (_) {
      if (mounted && index == _index) {
        setState(() => _hint = 'Auto Crop unavailable; drag the corners manually.');
      }
    }
  }

  Future<void> _autoCrop({bool all = false}) async {
    if (_working) return;
    setState(() => _working = true);
    try {
      if (all) {
        for (var i = 0; i < widget.imagePaths.length; i++) {
          await _detect(i, requested: true);
        }
      } else {
        await _detect(_index, requested: true);
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _changePage(int index) async {
    if (_working || index < 0 || index >= widget.imagePaths.length) return;
    setState(() { _index = index; _hint = 'Drag corners to refine this page.'; });
    await _load(index);
  }

  void _rotate(int delta) {
    if (_working) return;
    setState(() {
      _edits[_index].turns = (_edits[_index].turns + delta + 4) % 4;
      _edits[_index].touched = true;
    });
  }

  Future<void> _done() async {
    if (_working) return;
    setState(() { _working = true; _hint = 'Applying page corrections…'; });
    try {
      final output = <int, Uint8List>{};
      for (var i = 0; i < widget.imagePaths.length; i++) {
        final edit = _edits[i];
        if (widget.onlyEdited && !edit.touched) continue;
        if (!edit.confirmed && edit.turns == 0) continue;
        if (edit.confirmed && !CropQuad(edit.corners).isValid) {
          throw const FormatException('Invalid document corners.');
        }
        final source = _bytes[i] ?? await File(widget.imagePaths[i]).readAsBytes();
        output[i] = await ImageProcessor.process(source,
          crop: edit.confirmed ? CropQuad(edit.corners) : null,
          rotateDegrees: edit.turns * 90,
        );
      }
      if (mounted) Navigator.pop(context, output);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Could not apply crop: $error')));
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Widget _tool(IconData icon, String title, VoidCallback action) =>
      Expanded(child: InkWell(onTap: _working ? null : action,
        child: Column(mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 23, color: Colors.white),
            const SizedBox(height: 4),
            Text(title, style: const TextStyle(color: Colors.white, fontSize: 11)),
          ])));

  @override
  Widget build(BuildContext context) {
    final edit = _edits[_index];
    final bytes = _bytes[_index];
    final ratio = _ratios[_index] ?? .7;
    return PopScope(canPop: !_working, child: Scaffold(
      backgroundColor: const Color(0xFF141517),
      appBar: AppBar(
        backgroundColor: const Color(0xFF141517),
        foregroundColor: Colors.white,
        title: Text(widget.sideLabels.isEmpty ? 'Adjust Corners' : 'Crop',
            style: const TextStyle(fontSize: 17)),
      ),
      body: SafeArea(child: Column(children: [
        if (_working) const LinearProgressIndicator(color: dsTeal),
        Expanded(child: Center(child: LayoutBuilder(
          builder: (_, box) {
            final displayRatio = edit.turns.isOdd ? 1 / ratio : ratio;
            final displayWidth = math.max(1.0, math.min(
              box.maxWidth - 22, (box.maxHeight - 22) * displayRatio));
            final displayHeight = displayWidth / displayRatio;
            final width = edit.turns.isOdd ? displayHeight : displayWidth;
            final height = edit.turns.isOdd ? displayWidth : displayHeight;
            return bytes == null
                ? const Center(child: CircularProgressIndicator(color: dsTeal))
                : RotatedBox(quarterTurns: edit.turns,
                    child: SizedBox(width: width, height: height,
                      child: Stack(children: [
                        Positioned.fill(child: Image.memory(bytes, fit: BoxFit.fill)),
                        Positioned.fill(child: CustomPaint(
                          painter: _BatchCropOverlay(edit.corners))),
                        for (var handle = 0; handle < 8; handle++)
                          Positioned(
                            left: edit.handles[handle].dx * width - 18,
                            top: edit.handles[handle].dy * height - 18,
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onPanUpdate: (details) {
                                if (_working) return;
                                final moved = edit.updateHandle(handle,
                                  Offset(details.delta.dx / width,
                                         details.delta.dy / height));
                                if (moved) setState(() {});
                              },
                              child: SizedBox(width: 36, height: 36,
                                child: Center(child: Container(
                                  width: handle < 4 ? 13 : 19,
                                  height: handle < 4 ? 13 : 7,
                                  decoration: BoxDecoration(color: Colors.white,
                                    borderRadius: BorderRadius.circular(7),
                                    border: Border.all(color: dsTeal, width: 2)),
                                ))),
                            ),
                          ),
                      ])));
          },
        ))),
        Text(_hint, textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white60, fontSize: 11)),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          IconButton(onPressed: _working || _index == 0 ? null :
              () => _changePage(_index - 1),
              icon: const Icon(Icons.chevron_left), color: Colors.white),
          Text(widget.sideLabels.length == widget.imagePaths.length
                ? '${widget.sideLabels[_index]} · ${_index + 1}/${widget.imagePaths.length}'
                : '${_index + 1}/${widget.imagePaths.length}',
            style: const TextStyle(color: Colors.white70)),
          IconButton(onPressed: _working || _index + 1 >= widget.imagePaths.length
              ? null : () => _changePage(_index + 1),
              icon: const Icon(Icons.chevron_right), color: Colors.white),
        ]),
        Container(height: 76, color: const Color(0xFF27292C),
          child: Row(children: [
            _tool(Icons.rotate_left, 'Left', () => _rotate(3)),
            _tool(Icons.rotate_right, 'Right', () => _rotate(1)),
            _tool(Icons.crop_free, 'Auto Crop', () => _autoCrop()),
            _tool(Icons.select_all, 'All', () => _autoCrop(all: true)),
          ])),
        Container(height: 48, color: const Color(0xFF27292C),
          child: Row(children: [
            TextButton.icon(onPressed: _working ? null : () => Navigator.pop(context),
              icon: const Icon(Icons.close, color: Colors.white),
              label: const Text('Cancel', style: TextStyle(color: Colors.white))),
            const Spacer(),
            TextButton.icon(onPressed: _working ? null : _done,
              icon: const Icon(Icons.check, color: dsTeal),
              label: const Text('Done', style: TextStyle(color: dsTeal))),
          ])),
      ])),
    ));
  }
}

class _BatchCropOverlay extends CustomPainter {
  const _BatchCropOverlay(this.corners);
  final List<Offset> corners;

  @override
  void paint(Canvas canvas, Size size) {
    final mapped = corners.map((p) => Offset(p.dx * size.width,
        p.dy * size.height)).toList();
    final border = Path()..moveTo(mapped[0].dx, mapped[0].dy);
    for (final point in mapped.skip(1)) { border.lineTo(point.dx, point.dy); }
    border.close();
    canvas.drawPath(border, Paint()..color = dsTeal.withValues(alpha: .13));
    canvas.drawPath(border, Paint()..color = dsTeal
        ..strokeWidth = 2.5..style = PaintingStyle.stroke);
    final grid = Paint()..color = Colors.white.withValues(alpha: .6)
        ..strokeWidth = .7;
    for (var n = 1; n < 3; n++) {
      canvas.drawLine(Offset.lerp(mapped[0], mapped[3], n / 3)!,
          Offset.lerp(mapped[1], mapped[2], n / 3)!, grid);
      canvas.drawLine(Offset.lerp(mapped[0], mapped[1], n / 3)!,
          Offset.lerp(mapped[3], mapped[2], n / 3)!, grid);
    }
  }

  @override
  bool shouldRepaint(covariant _BatchCropOverlay old) => true;
}
