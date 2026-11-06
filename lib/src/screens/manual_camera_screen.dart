import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../theme.dart';

/// Camera preview and capture. Guide corners are a framing aid: automatic
/// contour tracking is a separate native image-analysis milestone.
class ManualCameraScreen extends StatefulWidget {
  const ManualCameraScreen({super.key, this.cardMode = false, this.side});

  final bool cardMode;
  final String? side;

  @override
  State<ManualCameraScreen> createState() => _ManualCameraScreenState();
}

class _ManualCameraScreenState extends State<ManualCameraScreen> with WidgetsBindingObserver {
  CameraController? _controller;
  bool _busy = false;
  String? _error;
  bool _flash = false;
  final _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      final devices = await availableCameras();
      if (devices.isEmpty) throw StateError('Camera is not available');
      final back = devices.where((c) => c.lensDirection == CameraLensDirection.back);
      final camera = back.isNotEmpty ? back.first : devices.first;
      final controller = CameraController(
        camera,
        ResolutionPreset.max,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() {
        _controller = controller;
        _error = null;
      });
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final old = _controller;
    if (state == AppLifecycleState.inactive || state == AppLifecycleState.paused) {
      _controller = null;
      old?.dispose();
    } else if (state == AppLifecycleState.resumed && _controller == null) {
      _initialize();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _takePicture() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized || _busy) return;
    setState(() => _busy = true);
    try {
      final picture = await controller.takePicture();
      if (mounted) Navigator.pop(context, [picture.path]);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not capture image: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _toggleFlash() async {
    final controller = _controller;
    if (controller == null) return;
    try {
      await controller.setFlashMode(_flash ? FlashMode.off : FlashMode.auto);
      setState(() => _flash = !_flash);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Flash unavailable: $error')));
      }
    }
  }

  Future<void> _import() async {
    try {
      final photos = await _picker.pickMultiImage(
        limit: widget.cardMode ? 2 : null,
        requestFullMetadata: false,
      );
      if (photos.isNotEmpty && mounted) {
        Navigator.pop(context, photos.map((photo) => photo.path).toList());
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Gallery import failed: $error')));
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
            child: Row(children: [
              IconButton(onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close, color: Colors.white, size: 30)),
              const Spacer(),
              IconButton(onPressed: _toggleFlash,
                  icon: Icon(_flash ? Icons.flash_auto : Icons.flash_off, color: Colors.white)),
              const SizedBox(width: 12),
              const Text('HD', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              const SizedBox(width: 18),
              IconButton(onPressed: () {},
                  icon: const Icon(Icons.more_vert, color: Colors.white)),
            ]),
          ),
          Expanded(child: LayoutBuilder(builder: (_, constraints) {
            return Stack(fit: StackFit.expand, children: [
              if (_controller case final controller?)
                if (controller.value.isInitialized)
                  Center(child: ClipRect(child: FittedBox(
                    fit: BoxFit.cover,
                    child: SizedBox(
                      width: constraints.maxWidth,
                      height: constraints.maxWidth * controller.value.aspectRatio,
                      child: CameraPreview(controller),
                    ),
                  ))),
              if (_controller == null && _error == null)
                const Center(child: CircularProgressIndicator(color: dsTeal)),
              if (_error != null)
                Center(child: Padding(padding: const EdgeInsets.all(30),
                    child: Text(_error!, textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white)))),
              CustomPaint(painter: _CameraGuidePainter(card: widget.cardMode)),
              Align(
                alignment: widget.cardMode ? const Alignment(0, -.83) : const Alignment(0, -.92),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.black54, borderRadius: BorderRadius.circular(25)),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
                    child: Text(widget.side ?? 'Fit it into the borders',
                        style: const TextStyle(color: Colors.white, fontSize: 15)),
                  ),
                ),
              ),
            ]);
          })),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 14, 24, 22),
            child: Row(children: [
              Expanded(child: IconButton(
                tooltip: 'Import images', onPressed: _import,
                icon: const Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.add_photo_alternate_outlined, color: Colors.white, size: 28),
                  SizedBox(height: 3),
                  Text('Import Images', style: TextStyle(color: Colors.white, fontSize: 10)),
                ]),
              )),
              Expanded(child: GestureDetector(
                onTap: _takePicture,
                child: Container(
                  height: 77, width: 77,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white,
                    border: Border.all(color: dsTeal, width: 6),
                  ),
                  child: Center(child: _busy
                      ? const CircularProgressIndicator(color: dsTeal)
                      : Container(width: 58, height: 58,
                          decoration: BoxDecoration(shape: BoxShape.circle,
                              border: Border.all(color: Colors.black, width: 2)))),
                ),
              )),
              Expanded(child: Text(widget.cardMode ? 'ID Card' : 'Scan', textAlign: TextAlign.center,
                  style: const TextStyle(color: dsTeal, fontSize: 16))),
            ]),
          ),
        ])),
      );
}

class _CameraGuidePainter extends CustomPainter {
  const _CameraGuidePainter({required this.card});
  final bool card;

  @override
  void paint(Canvas canvas, Size size) {
    final width = size.width * .83;
    final height = card ? width * .63 : mathMin(size.height * .72, width * 1.34);
    final rect = Rect.fromCenter(
        center: Offset(size.width / 2, size.height / 2), width: width, height: height);
    final dim = Paint()..color = const Color(0x55000000);
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, rect.top), dim);
    canvas.drawRect(Rect.fromLTWH(0, rect.bottom, size.width, size.height - rect.bottom), dim);
    canvas.drawRect(Rect.fromLTWH(0, rect.top, rect.left, height), dim);
    canvas.drawRect(Rect.fromLTWH(rect.right, rect.top, size.width - rect.right, height), dim);
    final pen = Paint()..color = Colors.white..strokeWidth = 3.7..style = PaintingStyle.stroke;
    const length = 25.0;
    for (final corner in [
      (Offset(rect.left, rect.top), 1.0, 1.0),
      (Offset(rect.right, rect.top), -1.0, 1.0),
      (Offset(rect.right, rect.bottom), -1.0, -1.0),
      (Offset(rect.left, rect.bottom), 1.0, -1.0),
    ]) {
      final (p, dx, dy) = corner;
      final path = Path()
        ..moveTo(p.dx + dx * length, p.dy)
        ..lineTo(p.dx, p.dy)
        ..lineTo(p.dx, p.dy + dy * length);
      canvas.drawPath(path, pen);
    }
  }

  @override
  bool shouldRepaint(covariant _CameraGuidePainter oldDelegate) => oldDelegate.card != card;
}

double mathMin(double a, double b) => a < b ? a : b;
