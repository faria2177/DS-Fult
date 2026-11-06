import 'package:doclens/doclens.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../theme.dart';
import 'manual_camera_screen.dart';

/// Live native document contour tracking, stability gating and auto-capture.
/// Kept behind this screen so callers always receive the same list of paths.
/// The manual camera is retained as a fallback on unsupported devices.
class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key, this.cardMode = false, this.side});

  final bool cardMode;
  final String? side;

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  bool _finished = false;
  final _picker = ImagePicker();

  void _finish(List<String> paths) {
    if (_finished || !mounted) return;
    _finished = true;
    Navigator.of(context).pop(paths);
  }

  Future<void> _gallery() async {
    try {
      final files = await _picker.pickMultiImage(
        limit: widget.cardMode ? 2 : null,
        requestFullMetadata: false,
      );
      if (files.isNotEmpty) _finish(files.map((file) => file.path).toList());
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gallery import failed: $error')),
      );
    }
  }

  Future<void> _manual() async {
    final files = await Navigator.of(context).push<List<String>>(
      MaterialPageRoute(
        builder: (_) => ManualCameraScreen(
          cardMode: widget.cardMode,
          side: widget.side,
        ),
      ),
    );
    if (files != null && files.isNotEmpty) _finish(files);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.black,
        body: Stack(children: [
          Positioned.fill(
            child: DoclensScreen(
              appBarTitle: widget.side ?? 'DocScanner',
              captureHintText: widget.side ?? 'Hold steady • Auto capture',
              useLabel: 'Use scan',
              editCornersLabel: 'Adjust edges',
              retakeLabel: 'Retake',
              accentColor: dsTeal,
              overlayStyle: QuadOverlayStyle.cornersFilled,
              enableAutoCapture: true,
              enableEditCorners: true,
              autoCaptureStabilityDuration: const Duration(milliseconds: 850),
              autoCaptureConfirmationDelay: const Duration(milliseconds: 350),
              imageEnhancement: ImageEnhancement.enhanced,
              jpegQuality: 95,
              config: const ScannerConfig(
                detectionPolarity: DetectionPolarity.auto,
                enableSharpnessGate: true,
                detectionThrottleHz: 12,
              ),
              onCapture: (result) {
                final path = result.croppedImagePath ?? result.rawImagePath;
                if (path.isNotEmpty) _finish([path]);
              },
            ),
          ),
          Positioned(
            bottom: 112,
            left: 12,
            right: 12,
            child: SafeArea(
              top: false,
              child: Row(children: [
                _shortcut(Icons.photo_library_outlined, 'Gallery', _gallery),
                const Spacer(),
                _shortcut(Icons.camera_outlined, 'Manual', _manual),
              ]),
            ),
          ),
        ]),
      );

  Widget _shortcut(IconData icon, String label, VoidCallback action) =>
      Material(
        color: const Color(0xBB111D22),
        borderRadius: BorderRadius.circular(28),
        child: InkWell(
          borderRadius: BorderRadius.circular(28),
          onTap: action,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(icon, size: 20, color: Colors.white),
              const SizedBox(width: 6),
              Text(label, style: const TextStyle(color: Colors.white)),
            ]),
          ),
        ),
      );
}
