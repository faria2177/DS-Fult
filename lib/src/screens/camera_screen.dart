import 'dart:async';
import 'dart:io';

import 'package:doclens/doclens.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../services/document_edges.dart';
import '../services/image_processor.dart';
import '../services/scan_settings_store.dart';
import '../theme.dart';
import 'manual_camera_screen.dart';
import 'id_card_templates.dart';
import 'scan_more_settings_screen.dart';

/// Live native document contour tracking with manual shutter capture.
/// Kept behind this screen so callers always receive the same list of paths.
/// The manual camera is retained as a fallback on unsupported devices.
class CameraScreen extends StatefulWidget {
  const CameraScreen({
    super.key,
    this.cardMode = false,
    this.cardTemplate,
    this.side,
    this.onOpenIdCards,
  });

  final bool cardMode;
  final IdCardTemplate? cardTemplate;
  final String? side;
  final Future<void> Function(BuildContext context)? onOpenIdCards;

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  bool _finished = false;
  bool _processingGallery = false;
  bool _cameraSuspended = false;
  bool _batchMode = false;
  bool _ready = false;
  bool _restarting = false;
  Offset _level = Offset.zero;
  StreamSubscription<dynamic>? _levelSubscription;
  ReferenceScanSettings _settings = ReferenceScanSettings();
  List<ScanCameraMode> _cameraModes = const [];
  String _appliedIdentity = '';
  static const _outlineColor = dsTeal;
  final _picker = ImagePicker();

  String get _cameraIdentity => [
        _batchMode,
        _settings.autoCapture,
        _settings.autoCrop,
        _settings.autoAdjustBorders,
        _settings.adjustAfterEachScan,
        _settings.resolution,
        _settings.orientation.name,
      ].join('|');

  @override
  void initState() {
    super.initState();
    unawaited(_prepareSettings());
  }

  Future<void> _prepareSettings() async {
    final settings = await ScanSettingsStore.load();
    final modes = await ScanSettingsStore.availableModes();
    if (modes.isNotEmpty &&
        (settings.resolution == 'auto' ||
         !modes.any((mode) => mode.id == settings.resolution))) {
      settings.selectResolution(modes.first.id);
    }
    if (!mounted) {
      settings.dispose();
      return;
    }
    _settings.dispose();
    _settings = settings;
    _cameraModes = modes;
    _appliedIdentity = _cameraIdentity;
    _settings.addListener(_onSettingsChanged);
    _syncLevelStream();
    await _applyOrientation(_settings.orientation);
    if (mounted) setState(() => _ready = true);
  }

  Future<void> _applyOrientation(ScanOrientationMode mode) async {
    await SystemChrome.setPreferredOrientations(switch (mode) {
      ScanOrientationMode.auto => [],
      ScanOrientationMode.portrait => [DeviceOrientation.portraitUp],
      ScanOrientationMode.landscape => [
        DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight],
    });
  }

  void _onSettingsChanged() {
    unawaited(ScanSettingsStore.save(_settings));
    unawaited(_applyOrientation(_settings.orientation));
    _syncLevelStream();
    final identity = _cameraIdentity;
    if (_ready && identity != _appliedIdentity && !_cameraSuspended) {
      _appliedIdentity = identity;
      unawaited(_restartCamera());
    } else if (mounted) {
      setState(() {});
    }
  }

  void _syncLevelStream() {
    if (!_settings.spiritLevel) {
      unawaited(_levelSubscription?.cancel() ?? Future<void>.value());
      _levelSubscription = null;
      return;
    }
    if (_levelSubscription != null) return;
    _levelSubscription = const EventChannel('doclens/level')
        .receiveBroadcastStream().listen((event) {
      if (!mounted || !_settings.spiritLevel || event is! Map) return;
      final x = event['x'];
      final y = event['y'];
      if (x is num && y is num) {
        setState(() => _level = Offset(x.toDouble(), y.toDouble()));
      }
    }, onError: (Object _) {});
  }

  Future<void> _restartCamera() async {
    if (_restarting || !mounted || _finished) return;
    _restarting = true;
    await _suspendCamera();
    if (mounted && !_finished) {
      _appliedIdentity = _cameraIdentity;
      setState(() => _cameraSuspended = false);
    }
    _restarting = false;
  }

  @override
  void dispose() {
    unawaited(_levelSubscription?.cancel() ?? Future<void>.value());
    _settings.removeListener(_onSettingsChanged);
    _settings.dispose();
    unawaited(SystemChrome.setPreferredOrientations([]));
    super.dispose();
  }

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
    if (batchMode && _settings.useSystemCamera) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('System Camera supports Single scan only.'),
      ));
      return;
    }
    await _suspendCamera();
    if (!mounted || _finished) return;
    setState(() {
      _batchMode = batchMode;
      _appliedIdentity = _cameraIdentity;
      _cameraSuspended = false;
    });
  }

  ScanFilter get _selectedFilter => switch (_settings.effect) {
        ScanEffectPreset.original => ScanFilter.original,
        ScanEffectPreset.lighten => ScanFilter.lighten,
        ScanEffectPreset.enhance => ScanFilter.enhance,
        ScanEffectPreset.magicPro => ScanFilter.magicColor,
        ScanEffectPreset.noWatermark => ScanFilter.noWatermark,
        ScanEffectPreset.noShadow => ScanFilter.shadowFree,
        ScanEffectPreset.noHandwriting => ScanFilter.noHandwriting,
        ScanEffectPreset.blackWhite => ScanFilter.blackWhite,
        ScanEffectPreset.eco => ScanFilter.eco,
        ScanEffectPreset.grayscale => ScanFilter.grayscale,
        ScanEffectPreset.invert => ScanFilter.invert,
      };

  Future<void> _finishProcessed(List<String> paths,
      {bool applySelectedEffect = true}) async {
    if (!mounted || _finished || paths.isEmpty) return;
    setState(() => _processingGallery = true);
    try {
      final processed = <String>[];
      final useEffect = applySelectedEffect && !widget.cardMode &&
          _selectedFilter != ScanFilter.original;
      final folder = useEffect ? await getTemporaryDirectory() : null;
      for (var i = 0; i < paths.length; i++) {
        final original = paths[i];
        var result = original;
        if (useEffect && folder != null) {
          try {
            final filtered = await ImageProcessor.process(
              await File(original).readAsBytes(), filter: _selectedFilter,
            );
            final file = File(p.join(folder.path,
                'ds_effect_${DateTime.now().microsecondsSinceEpoch}_$i.jpg'));
            await file.writeAsBytes(filtered, flush: true);
            result = file.path;
          } catch (_) {
            // Keep the unmodified accepted scan if a complex filter fails.
          }
        }
        processed.add(result);
        if (_settings.saveScansToGallery) {
          await ScanSettingsStore.saveImageToGallery(result);
        }
      }
      if (mounted) _finish(processed);
    } catch (_) {
      if (mounted) _finish(paths);
    } finally {
      if (mounted && !_finished) {
        setState(() => _processingGallery = false);
      }
    }
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
      await _finishProcessed(cropped.paths,
        applySelectedEffect: _settings.importFromGallery);
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

  Future<void> _systemCamera() async {
    if (_cameraSuspended || _finished) return;
    await _suspendCamera();
    if (!mounted) return;
    try {
      final image = await _picker.pickImage(
        source: ImageSource.camera, imageQuality: 100,
      );
      if (image == null || !mounted) return;
      final cropped = await DocumentEdges.autoCropFiles([image.path]);
      await _finishProcessed(cropped.paths);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('System camera failed: $error')),
        );
      }
    } finally {
      if (mounted && !_finished) setState(() => _cameraSuspended = false);
    }
  }

  Future<void> _openMoreSettings() async {
    if (_cameraSuspended || _finished) return;
    await _suspendCamera();
    if (!mounted) return;
    try {
      await Navigator.of(context).push<void>(MaterialPageRoute(
        builder: (_) => ScanMoreSettingsScreen(settings: _settings),
      ));
    } finally {
      if (mounted && !_finished) {
        _appliedIdentity = _cameraIdentity;
        setState(() => _cameraSuspended = false);
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

  Future<void> _openIdCards() async {
    final open = widget.onOpenIdCards;
    if (open == null || widget.cardMode || _finished || _cameraSuspended) return;
    await _suspendCamera();
    if (!mounted) return;
    try {
      await open(context);
    } finally {
      if (mounted && !_finished) setState(() => _cameraSuspended = false);
    }
  }

  Future<void> _confirmDiscardCard() async {
    if (_finished || !mounted) return;
    final discard = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF28282A),
        title: const Text('Discard your scans?',
          style: TextStyle(color: Colors.white, fontSize: 18)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.white70))),
          TextButton(onPressed: () => Navigator.pop(context, true),
            child: const Text('Discard', style: TextStyle(
              color: Colors.deepOrange))),
        ],
      ),
    );
    if (discard == true && mounted && !_finished) {
      _finished = true;
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.black,
        body: Stack(children: [
          Positioned.fill(child: !_ready || _cameraSuspended
              ? const ColoredBox(color: Colors.black)
              : DoclensScreen(
                  key: ValueKey(_cameraIdentity),
                  multiPage: _batchMode,
                  referenceScanChrome: !widget.cardMode,
                  referenceIdCardChrome: widget.cardMode,
                  referenceCardLabel: widget.cardTemplate?.label ?? 'ID Card',
                  referenceCardSide: widget.side ?? 'Front',
                  referenceCardPortraitGuide:
                      widget.cardTemplate?.portraitGuide ?? false,
                  onReferenceCardClose: _confirmDiscardCard,
                  referenceSettings: _settings,
                  referenceCameraModes: _cameraModes,
                  referenceLevel: _level,
                  onReferenceMoreSettings: _openMoreSettings,
                  referenceDoubleFocus: _settings.doubleFocus,
                  onReferenceShutterTap: () {
                    if (_settings.sound) {
                      unawaited(SystemSound.play(SystemSoundType.click));
                    }
                  },
                  onReferenceCaptureOverride:
                      _settings.useSystemCamera && !widget.cardMode
                          ? _systemCamera : null,
                  onBatchModeChanged: _switchMode,
                  onImportFiles: _gallery,
                  onImportImages: _gallery,
                  onManualScan: _manual,
                  onOpenIdCards: _openIdCards,
                  appBarTitle: widget.side ?? (_batchMode ? 'Batch Scan' : 'DocScanner'),
                  captureHintText: widget.side ?? 'Align all four corners',
                  useLabel: 'Use scan',
                  addPageLabel: 'Add page',
                  doneLabel: 'Done',
                  editCornersLabel: 'Adjust corners',
                  retakeLabel: 'Retake',
                  accentColor: _outlineColor,
                  warningColor: _outlineColor,
                  overlayStyle: QuadOverlayStyle.outline,
                  enableAutoCapture: _settings.autoCapture &&
                      !_settings.useSystemCamera,
                  enablePerspectiveWarp: _settings.autoCrop &&
                      (!_batchMode || _settings.autoAdjustBorders),
                  captureSize: _settings.resolution == 'auto'
                      ? null : _settings.resolution,
                  enableEditCorners: true,
                  imageEnhancement: ImageEnhancement.none,
                  jpegQuality: 95,
                  config: DocumentEdges.scannerConfig,
                  onComplete: (results) {
                    if (_cameraSuspended) return;
                    final paths = results
                        .map((result) => result.croppedImagePath ?? result.rawImagePath)
                        .where((path) => path.isNotEmpty)
                        .toList();
                    if (paths.isNotEmpty) unawaited(_finishProcessed(paths));
                  },
                  onCapture: (result) {
                    if (_cameraSuspended) return;
                    final path = result.croppedImagePath ?? result.rawImagePath;
                    if (path.isNotEmpty) unawaited(_finishProcessed([path]));
                  },
                )),
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

}
