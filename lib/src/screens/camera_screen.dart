import 'package:doclens/doclens.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../services/document_edges.dart';
import '../theme.dart';
import 'manual_camera_screen.dart';

/// Live native document contour tracking with manual shutter capture.
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
  bool _processingGallery = false;
  bool _cameraSuspended = false;
  bool _batchMode = false;
  static const _outlineColor = Color(0xFF28C78A);
  final _picker = ImagePicker();

  void _finish(List<String> paths) {
    if (_finished || !mounted) return;
    _finished = true;
    Navigator.of(context).pop(paths);
  }

  /// Allow CameraX to release its camera session before a different scanner,
  /// manual camera, or the system image picker opens. This avoids racing two
  /// camera owners when switching Single / Batch.
  Future<void> _suspendCamera() async {
    if (!mounted) return;
    setState(() => _cameraSuspended = true);
    await Future<void>.delayed(const Duration(milliseconds: 350));
  }

  Future<void> _switchMode(bool batchMode) async {
    if (_finished || _cameraSuspended || _batchMode == batchMode ||
        _processingGallery || widget.cardMode) {
      return;
    }
    await _suspendCamera();
    if (!mounted || _finished) return;
    setState(() {
      _batchMode = batchMode;
      _cameraSuspended = false;
    });
  }

  Future<void> _gallery() async {
    if (_processingGallery || _cameraSuspended || _finished) return;
    try {
      await _suspendCamera();
      if (!mounted) return;
      final files = await _picker.pickMultiImage(
        limit: widget.cardMode ? 2 : null,
        requestFullMetadata: false,
      );
      if (files.isEmpty || !mounted) return;
      setState(() => _processingGallery = true);
      final cropped = await DocumentEdges.autoCropFiles(
        files.map((file) => file.path).toList(),
      );
      if (!mounted) return;
      _finish(cropped.paths);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gallery import failed: $error')),
      );
    } finally {
      if (mounted && !_finished) {
        setState(() {
          _processingGallery = false;
          _cameraSuspended = false;
        });
      }
    }
  }

  Future<void> _manual() async {
    if (_cameraSuspended || _finished) return;
    await _suspendCamera();
    if (!mounted) return;
    try {
      final files = await Navigator.of(context).push<List<String>>(
        MaterialPageRoute(
          builder: (_) => ManualCameraScreen(
            cardMode: widget.cardMode,
            side: widget.side,
          ),
        ),
      );
      if (files != null && files.isNotEmpty) _finish(files);
    } finally {
      if (mounted && !_finished) {
        setState(() => _cameraSuspended = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.black,
        body: Stack(children: [
          Positioned.fill(
            child: _cameraSuspended
                ? const ColoredBox(color: Colors.black)
                : _batchMode
                    ? DoclensMultiScreen(
                        appBarTitle: 'Batch Scan',
                        captureHintText: 'Align green edges • Tap shutter',
                        addPageLabel: 'Add page',
                        doneLabel: 'Done',
                        editCornersLabel: 'Adjust corners',
                        accentColor: _outlineColor,
                        warningColor: _outlineColor,
                        overlayStyle: QuadOverlayStyle.outline,
                        enableAutoCapture: false,
                        enableEditCorners: true,
                        imageEnhancement: ImageEnhancement.enhanced,
                        jpegQuality: 95,
                        config: DocumentEdges.scannerConfig,
                        onComplete: (results) {
                          if (_cameraSuspended) return;
                          final paths = results
                              .map((result) => result.croppedImagePath ?? result.rawImagePath)
                              .where((path) => path.isNotEmpty)
                              .toList();
                          if (paths.isNotEmpty) _finish(paths);
                        },
                      )
                    : DoclensScreen(
                        appBarTitle: widget.side ?? 'DocScanner',
                        captureHintText: widget.side ??
                            'Align green edges • Tap shutter',
                        useLabel: 'Use scan',
                        editCornersLabel: 'Adjust edges',
                        retakeLabel: 'Retake',
                        accentColor: _outlineColor,
                        warningColor: _outlineColor,
                        overlayStyle: QuadOverlayStyle.outline,
                        enableAutoCapture: false,
                        enableEditCorners: true,
                        autoCaptureStabilityDuration:
                            const Duration(milliseconds: 1100),
                        autoCaptureConfirmationDelay:
                            const Duration(milliseconds: 400),
                        imageEnhancement: ImageEnhancement.enhanced,
                        jpegQuality: 95,
                        config: DocumentEdges.scannerConfig,
                        onCapture: (result) {
                          if (_cameraSuspended) return;
                          final path = result.croppedImagePath ??
                              result.rawImagePath;
                          if (path.isNotEmpty) _finish([path]);
                        },
                      ),
          ),
          if (!widget.cardMode && !_cameraSuspended)
            Positioned(
              bottom: 174,
              left: 0,
              right: 0,
              child: Center(
                child: Material(
                  color: const Color(0xDF182329),
                  borderRadius: BorderRadius.circular(30),
                  child: Padding(
                    padding: const EdgeInsets.all(3),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      _modeButton('Single', false),
                      _modeButton('Batch', true),
                    ]),
                  ),
                ),
              ),
            ),
          if (!_cameraSuspended)
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
          if (_processingGallery)
            const Positioned.fill(
              child: ColoredBox(
                color: Color(0xBB000000),
                child: Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    CircularProgressIndicator(color: dsTeal),
                    SizedBox(height: 16),
                    Text('Detecting document edges & auto-cropping…',
                        style: TextStyle(color: Colors.white)),
                  ]),
                ),
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

  Widget _modeButton(String label, bool batch) {
    final selected = _batchMode == batch;
    return InkWell(
      borderRadius: BorderRadius.circular(28),
      onTap: () => _switchMode(batch),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: 91,
        padding: const EdgeInsets.symmetric(vertical: 11),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF697176) : Colors.transparent,
          borderRadius: BorderRadius.circular(28),
        ),
        child: Text(label, textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            )),
      ),
    );
  }
}
