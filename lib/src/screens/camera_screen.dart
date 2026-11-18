import 'dart:async';
import 'dart:io';

import 'package:doclens/doclens.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../services/camera_crop_review_decision.dart';
import '../services/document_edges.dart';
import '../services/gallery_import_flow.dart';
import '../services/image_processor.dart';
import '../services/online_auto_crop_service.dart';
import '../services/scan_settings_store.dart';
import '../theme.dart';
import 'batch_crop_screen.dart';
import 'manual_camera_screen.dart';
import 'id_card_templates.dart';
import 'id_card_template_screen.dart';
import 'scan_more_settings_screen.dart';
import 'scan_reveal_overlay.dart';

/// Live native document contour tracking with manual shutter capture.
/// Kept behind this screen so callers always receive the same list of paths.
/// The manual camera is retained as a fallback on unsupported devices.
class CameraScreen extends StatefulWidget {
  const CameraScreen({
    super.key,
    this.cardMode = false,
    this.cardTemplate,
    this.side,
    this.cardCaptureLimit,
    this.onOpenIdCards,
    this.onCardSourcePaths,
    this.onOutputSourcePaths,
  });

  final bool cardMode;
  final IdCardTemplate? cardTemplate;
  final String? side;
  /// Remaining sides in this session; null means unlimited card pages.
  final int? cardCaptureLimit;
  /// Raw upright stills are retained for lossless four-corner correction.
  final ValueChanged<List<String>>? onCardSourcePaths;
  /// Processed pages and full upright originals are aligned by index.
  /// HomeShell can persist originals separately for later re-crop.
  final ValueChanged<List<String>>? onOutputSourcePaths;
  final Future<void> Function(BuildContext context,
      IdCardTemplate template)? onOpenIdCards;

  /// Only options that reconfigure the native camera belong in this key.
  /// Switching Single/Batch or revealing ID Cards changes Flutter chrome,
  /// not the CameraX session, under the default auto-border policy.
  static String captureConfigKey(ReferenceScanSettings settings,
      {required bool batchMode}) => [
        if (settings.autoCrop && !settings.autoAdjustBorders) batchMode,
        settings.autoCapture,
        settings.autoCrop,
        settings.autoAdjustBorders,
        settings.adjustAfterEachScan,
        settings.resolution,
        settings.orientation.name,
      ].join('|');

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  bool _finished = false;
  bool _processingGallery = false;
  // Post-shutter scan animation (visual only, single camera captures).
  ScanRevealData? _reveal;
  String? _revealResult;
  Completer<void>? _revealDone;
  bool _cameraSuspended = false;
  bool _batchMode = false;
  bool _showIdCards = false;
  IdCardTemplate _idCardTemplate = IdCardTemplate.general;
  bool _ready = false;
  bool _restarting = false;
  Offset _level = Offset.zero;
  StreamSubscription<dynamic>? _levelSubscription;
  ReferenceScanSettings _settings = ReferenceScanSettings();
  List<ScanCameraMode> _cameraModes = const [];
  String _appliedIdentity = '';
  static const _outlineColor = dsTeal;
  final _picker = ImagePicker();

  int? get _cardLimit => !widget.cardMode ? null
      : (widget.cardCaptureLimit ??
          (widget.cardTemplate == null || widget.cardTemplate?.sideCount == 2
              ? 2 : null));

  bool get _detectCardBounds => widget.cardMode &&
      (widget.cardTemplate == null ||
          (widget.cardTemplate != IdCardTemplate.general &&
           !widget.cardTemplate!.portraitGuide));

  String get _cameraIdentity => CameraScreen.captureConfigKey(
        _settings, batchMode: _batchMode,
      );

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

  /// Release CameraX only before opening another camera owner or file picker.
  /// Mode-only changes must not pass through this black placeholder.
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
    final before = _cameraIdentity;
    setState(() {
      _batchMode = batchMode;
    });
    if (before != _cameraIdentity) {
      // Auto-adjust off changes native perspective-warp configuration.
      // That setting still requires a controlled rebind.
      await _restartCamera();
    }
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
      {bool applySelectedEffect = true,
       Set<String> confirmedCrops = const <String>{},
       List<String>? originalSourcePaths}) async {
    if (!mounted || _finished || paths.isEmpty) return;
    // Fall back to current output only for legacy manual-camera callers.
    final sources = originalSourcePaths != null &&
            originalSourcePaths.length == paths.length
        ? List<String>.of(originalSourcePaths) : List<String>.of(paths);
    setState(() => _processingGallery = true);
    try {
      final processed = <String>[];
      // ID Card sides get the chosen scan effect too (Enhance by default),
      // so cards come out bright like other scans instead of grey.
      final useEffect = applySelectedEffect &&
          _selectedFilter != ScanFilter.original;
      final folder = useEffect ? await getTemporaryDirectory() : null;
      for (var i = 0; i < paths.length; i++) {
        final original = paths[i];
        var result = original;
        if (useEffect && folder != null) {
          try {
            final filtered = await ImageProcessor.process(
              await File(original).readAsBytes(), filter: _selectedFilter,
              documentMode: confirmedCrops.contains(original),
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
      if (mounted && _reveal != null && processed.length == 1) {
        // Let the scan line uncover the finished page before leaving.
        final done = Completer<void>();
        _revealDone = done;
        setState(() => _revealResult = processed.first);
        await done.future.timeout(const Duration(seconds: 3),
            onTimeout: () {});
      }
      if (mounted) {
        widget.onOutputSourcePaths?.call(sources);
        _finish(processed);
      }
    } catch (_) {
      if (mounted) {
        widget.onOutputSourcePaths?.call(sources);
        _finish(paths);
      }
    } finally {
      if (mounted && !_finished) {
        setState(() {
          _processingGallery = false;
          _reveal = null;
          _revealResult = null;
        });
      }
    }
  }

  /// CameraX can return a full-resolution raw photo without a detected quad.
  /// Recover those captures with the same safe still-image auto-crop pipeline
  /// used by gallery import. Never re-crop a successful native perspective
  /// result, and never force an uncertain crop of the original image.
  Future<void> _discardCanceledCameraCaptures(
      List<ScanResult> results, List<String> generatedOutputs) async {
    // CameraCapture results are privately owned temporary files, unlike
    // gallery/image imports. Never remove user-selected import originals.
    final files = <String>{
      for (final result in results) ...[
        result.rawImagePath,
        if (result.croppedImagePath != null) result.croppedImagePath!,
      ],
      ...generatedOutputs,
    };
    for (final path in files) {
      if (path.isEmpty) {
        continue;
      }
      try {
        final file = File(path);
        if (await file.exists()) {
          await file.delete();
        }
      } catch (_) {
        // Cancellation must always return to the camera, including when
        // Android has already cleaned one of its temporary cache files.
      }
    }
  }

  Future<void> _finishCapturedResults(List<ScanResult> results) async {
    if (!mounted || _finished || _processingGallery || results.isEmpty) return;
    final only = results.length == 1 ? results.first : null;
    setState(() {
      _processingGallery = true;
      _revealResult = null;
      _reveal = only != null && !widget.cardMode &&
              only.rawImagePath.isNotEmpty &&
              only.rawImageSize.width > 0 && only.rawImageSize.height > 0
          ? ScanRevealData(
              rawPath: only.rawImagePath,
              imageSize: only.rawImageSize,
              corners: only.detectedQuad.points)
          : null;
    });
    try {
    final outputs = <String>[];
    final rawPathsForOutputs = <String>[];
    final confirmedCrops = <String>{};
    final unresolvedSourcePaths = <String>[];
    final unresolvedOutputIndexes = <int>[];
    final capturedCornerHints = <int, List<Offset>>{};
    // If visible green corners could not be mapped to the JPEG, never seed
    // this review with a second, unrelated still-detector rectangle.
    final manualOnlyCameraPages = <int>{};
    for (final result in results) {
      final nativeCrop = result.croppedImagePath;
      final raw = result.rawImagePath;
      if (raw.isEmpty && (nativeCrop == null || nativeCrop.isEmpty)) continue;
      // Camera shutter contract: the visible green four-corner outline is the
      // crop target. A second still detector may *verify* the same paper, but
      // it must never silently replace those corners with a different quad.
      // This branch is camera-only; Gallery/Import keep their existing Online
      // First + still-image detector workflow completely unchanged.
      if (!widget.cardMode && result.liveOutlineAtShutter) {
        if (result.liveOutlineMatched &&
            nativeCrop != null && nativeCrop.isNotEmpty) {
          outputs.add(nativeCrop);
          rawPathsForOutputs.add(raw.isEmpty ? nativeCrop : raw);
          confirmedCrops.add(nativeCrop);
        } else if (raw.isNotEmpty) {
          // An incompatible still crop/rotation or different detected border
          // cannot be assumed to be the green outline. Preserve the original
          // and open corner adjustment with the captured hint when usable.
          outputs.add(raw);
          rawPathsForOutputs.add(raw);
          final hint = DocumentEdges.captureQuadHint(result);
          final reviewIndex = unresolvedSourcePaths.length;
          if (hint != null) {
            capturedCornerHints[reviewIndex] = hint.corners;
          } else {
            manualOnlyCameraPages.add(reviewIndex);
          }
          unresolvedSourcePaths.add(raw);
          unresolvedOutputIndexes.add(outputs.length - 1);
        }
        continue;
      }
      // Camera-only: a successful native perspective crop is final. Never
      // run Online First / another still detector over its raw original;
      // doing so can silently substitute an interior text box or turn the
      // page after the green outline was already confirmed.
      // Imports still retain their separate Online First detection path.
      if (!widget.cardMode && nativeCrop != null && nativeCrop.isNotEmpty) {
        outputs.add(nativeCrop);
        rawPathsForOutputs.add(raw.isEmpty ? nativeCrop : raw);
        confirmedCrops.add(nativeCrop);
        continue;
      }
      // With no native crop and no green shutter outline, still-image
      // fallback remains available for legacy/system camera behavior.
      if (raw.isNotEmpty && await OnlineAutoCropConfig.canUpload()) {
        final first = await DocumentEdges.autoCropFiles([raw],
            preferIdCardBounds: _detectCardBounds,
            // Camera photos keep the detector chain they had before.
            galleryDetectors: false);
        if (first.croppedCount > 0) {
          outputs.add(first.paths.single);
          rawPathsForOutputs.add(raw);
          confirmedCrops.add(first.paths.single);
          continue;
        }
      }
      if (nativeCrop != null && nativeCrop.isNotEmpty) {
        outputs.add(nativeCrop);
        rawPathsForOutputs.add(raw.isEmpty ? nativeCrop : raw);
        confirmedCrops.add(nativeCrop);
        continue;
      }
      if (raw.isEmpty) continue;
      if (_settings.autoCrop || widget.cardMode) {
        final recovered = await DocumentEdges.autoCropFiles([raw],
            preferIdCardBounds: _detectCardBounds,
            // Camera photos keep the detector chain they had before.
            galleryDetectors: false);
        final path = recovered.paths.single;
        outputs.add(path);
        rawPathsForOutputs.add(raw);
        if (recovered.croppedCount > 0) {
          confirmedCrops.add(path);
        } else {
          // Never apply a guessed quad from a stale preview. Present the
          // actual upright still in the manual four-corner editor.
          final hint = DocumentEdges.captureQuadHint(result,
              preferIdCardBounds: _detectCardBounds);
          if (hint != null) {
            capturedCornerHints[unresolvedSourcePaths.length] = hint.corners;
          }
          unresolvedSourcePaths.add(raw);
          unresolvedOutputIndexes.add(outputs.length - 1);
        }
      } else {
        outputs.add(raw);
        rawPathsForOutputs.add(raw);
      }
    }
    if (unresolvedSourcePaths.isNotEmpty && mounted) {
      // Release the CameraX owner before opening another full-screen editor.
      await _suspendCamera();
      if (!mounted) return;
      final edits = await Navigator.of(context).push<Map<int, Uint8List>>(
        MaterialPageRoute(builder: (_) => BatchCropScreen(
          imagePaths: unresolvedSourcePaths,
          preferIdCardBounds: _detectCardBounds,
          capturedCornerHints: capturedCornerHints,
          manualOnlyCameraPages: manualOnlyCameraPages,
        )),
      );
      if (!mounted) return;
      // Cancel/Back returns null; Done returns an empty or populated map.
      // Previously null fell through to _finishProcessed(outputs), saving
      // the whole raw photo even when the user explicitly canceled.
      if (cameraCropReviewDecision(edits) ==
          CameraCropReviewDecision.discard) {
        // Discard ALL captures from this pending shutter transaction.
        // A multi-page batch is an uncommitted transaction too: cancel
        // must not silently save its successfully pre-cropped siblings.
        // Original files belong to the camera's private temporary cache.
        if (!widget.cardMode) {
          await _discardCanceledCameraCaptures(results, outputs);
        }
        if (mounted) {
          setState(() => _cameraSuspended = false);
        }
        return;
      }
      if (edits != null && edits.isNotEmpty) {
        final directory = await getTemporaryDirectory();
        for (final entry in edits.entries) {
          if (entry.key < 0 || entry.key >= unresolvedOutputIndexes.length) {
            continue;
          }
          final outputIndex = unresolvedOutputIndexes[entry.key];
          final file = File(p.join(directory.path,
              'ds_capture_adjust_${DateTime.now().microsecondsSinceEpoch}_'
              '$outputIndex.jpg'));
          await file.writeAsBytes(entry.value, flush: true);
          outputs[outputIndex] = file.path;
          confirmedCrops.add(file.path);
        }
      }
    }
    // Only explicit Done reaches this commit: Cancel/Back has already
    // returned without calling _finishProcessed or onOutputSourcePaths.
    if (outputs.isNotEmpty) {
      await _finishProcessed(outputs,
          confirmedCrops: confirmedCrops,
          originalSourcePaths: rawPathsForOutputs);
    }
    } finally {
      if (mounted && !_finished) {
        setState(() {
          _processingGallery = false;
          _reveal = null;
          _revealResult = null;
        });
      }
    }
  }

  Future<void> _gallery() async {
    if (_processingGallery || _cameraSuspended || _finished) return;
    try {
      await _suspendCamera();
      if (!mounted) return;
      // CamScanner-style Import Images: one in-app "Select Photo" grid with
      // Import(n), Enhance and Auto Crop, then straight to the document.
      // Auto Crop starts ticked even if live-capture cropping was disabled.
      final reviewed = await pickAndImportFromGallery(context,
        picker: _picker,
        limit: _cardLimit,
        initialAutoCrop: true,
        // Honour an explicit Original preset: auto-crop must not imply
        // colour/face/text enhancement of the user's source image.
        initialFilter: widget.cardMode ? ScanFilter.original :
            _selectedFilter,
        preferIdCardBounds: _detectCardBounds,
      );
      if (reviewed == null || !mounted) return;
      if (widget.cardMode) {
        widget.onCardSourcePaths?.call(reviewed.sourcePaths);
      }
      // The import screen already offers an actionable four-corner review.
      // This route immediately pops after _finishProcessed; showing a snackbar
      // here would linger over the document editor's bottom toolbar.
      await _finishProcessed(reviewed.paths, applySelectedEffect: false,
          originalSourcePaths: reviewed.sourcePaths);
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
      final cropped = await DocumentEdges.autoCropFiles([image.path],
          preferIdCardBounds: _detectCardBounds,
          // Camera photos keep the detector chain they had before.
          galleryDetectors: false);
      if (widget.cardMode) widget.onCardSourcePaths?.call([image.path]);
      final outputs = List<String>.of(cropped.paths);
      final confirmed = cropped.croppedCount == 0
          ? <String>{} : outputs.toSet();
      await _finishProcessed(outputs, confirmedCrops: confirmed,
          originalSourcePaths: [image.path]);
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
      if (files != null && files.isNotEmpty) {
        if (widget.cardMode) widget.onCardSourcePaths?.call(files);
        _finish(files);
      }
    } finally {
      if (mounted && !_finished) {
        setState(() => _cameraSuspended = false);
      }
    }
  }

  Future<void> _openIdCards() async {
    if (widget.onOpenIdCards == null || widget.cardMode ||
        _finished || _cameraSuspended) {
      return;
    }
    _settings.closePanel();
    setState(() => _showIdCards = true);
  }

  void _returnToScan() {
    if (_finished || !mounted) return;
    _settings.closePanel();
    setState(() => _showIdCards = false);
  }

  Future<void> _makeSelectedCard() async {
    final open = widget.onOpenIdCards;
    if (open == null || _finished || _cameraSuspended) return;
    await _suspendCamera();
    if (!mounted || _finished) return;
    try {
      await open(context, _idCardTemplate);
    } finally {
      if (mounted && !_finished) setState(() => _cameraSuspended = false);
    }
  }

  Future<void> _idCardsHd() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF121212),
      builder: (sheetContext) => SafeArea(child: SizedBox(height: 325,
        child: Column(children: [
          const Padding(padding: EdgeInsets.all(13), child: Text('HD Resolution',
            style: TextStyle(color: Colors.white, fontSize: 17))),
          Expanded(child: _cameraModes.isEmpty
            ? const Center(child: Text('Automatic (device default)',
                style: TextStyle(color: Colors.white70)))
            : ListView.builder(itemCount: _cameraModes.length,
                itemBuilder: (context, index) {
                  final mode = _cameraModes[index];
                  return ListTile(
                    title: Text(mode.label,
                      style: const TextStyle(color: Colors.white)),
                    trailing: _settings.resolution == mode.id
                      ? const Icon(Icons.check, color: dsTeal) : null,
                    onTap: () {
                      _settings.selectResolution(mode.id);
                      Navigator.pop(sheetContext);
                    },
                  );
                })),
        ]),
      )),
    );
  }

  Future<void> _idCardsSettings() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF121212),
      builder: (sheetContext) => SafeArea(child: AnimatedBuilder(
        animation: _settings,
        builder: (context, _) => ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
          children: [
            const Text('Settings', style: TextStyle(
              color: Colors.white, fontSize: 19,
              fontWeight: FontWeight.bold)),
            for (final item in const [
              ('Auto Capture', 'autoCapture'), ('Grid', 'grid'),
              ('Sound', 'sound'), ('Spirit Level', 'spiritLevel'),
              ('Auto Crop', 'autoCrop'),
            ])
              SwitchListTile(
                dense: true,
                title: Text(item.$1,
                  style: const TextStyle(color: Colors.white)),
                value: _settings.flag(item.$2),
                onChanged: (v) => _settings.setFlag(item.$2, v),
              ),
            TextButton(onPressed: () {
              Navigator.pop(sheetContext);
              unawaited(_openMoreSettings());
            }, child: const Text('More Settings',
              style: TextStyle(color: dsTeal))),
          ],
        ),
      )),
    );
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
                  multiPage: widget.cardMode || _batchMode,
                  maxPages: _cardLimit,
                  autoFinishAtPageLimit: widget.cardMode &&
                      _cardLimit != null,
                  referenceScanChrome: !widget.cardMode,
                  referencePickerBuilder: _showIdCards && !widget.cardMode
                      ? (context, livePreview, cycleFlash) =>
                          IdCardTemplateChooserContent(
                            selected: _idCardTemplate,
                            onSelect: (type) => setState(() => _idCardTemplate = type),
                            onClose: _returnToScan,
                            onFlash: cycleFlash,
                            onHd: _idCardsHd,
                            onSettings: _idCardsSettings,
                            onMakeItNow: _makeSelectedCard,
                            preview: livePreview,
                            nativePreview: true,
                            busy: _cameraSuspended,
                          ) : null,
                  referenceIdCardChrome: widget.cardMode,
                  // Video 382731.mp4: Front -> Back in the same live camera,
                  // then the A4 pair editor; no intermediate accept page.
                  quickCardCapture: widget.cardMode &&
                      widget.cardTemplate?.sideCount == 2,
                  // The marked Retake/Adjust-corners/Next screen is removed
                  // for Scan. Valid cropped stills go straight to preview;
                  // unsafe stills use the existing manual crop editor.
                  skipCaptureReview: true,
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
                      _settings.useSystemCamera && !widget.cardMode && !_batchMode
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
                  overlayStyle: QuadOverlayStyle.filled,
                  // Manual shutter remains the default, as in video 382016.
                  // Respect an explicit Auto Capture opt-in from Settings.
                  enableAutoCapture: !widget.cardMode && _settings.autoCapture &&
                      !_settings.useSystemCamera,
                  enablePerspectiveWarp: widget.cardMode ||
                      (_settings.autoCrop &&
                          (!_batchMode || _settings.autoAdjustBorders)),
                  captureSize: _settings.resolution == 'auto'
                      ? null : _settings.resolution,
                  enableEditCorners: true,
                  imageEnhancement: ImageEnhancement.none,
                  // Do not force 180 degrees: apply only the on-device OCR
                  // hypothesis when it confidently reads the card upright.
                  autoOrientation: widget.cardMode && _detectCardBounds
                      ? AutoOrientation.auto : AutoOrientation.none,
                  jpegQuality: 95,
                  config: _detectCardBounds
                      ? DocumentEdges.idCardScannerConfig
                      : DocumentEdges.scannerConfig,
                  onComplete: (results) {
                    if (_cameraSuspended) return;
                    if (widget.cardMode) {
                      widget.onCardSourcePaths?.call(results
                          .map((result) => result.rawImagePath).toList());
                    }
                    unawaited(_finishCapturedResults(results));
                  },
                  onCapture: (result) {
                    if (_cameraSuspended) return;
                    if (widget.cardMode) {
                      widget.onCardSourcePaths?.call([result.rawImagePath]);
                    }
                    unawaited(_finishCapturedResults([result]));
                  },
                )),
          if (_processingGallery && _reveal != null)
            Positioned.fill(
              child: ScanRevealOverlay(
                data: _reveal!,
                resultPath: _revealResult,
                onRevealed: () {
                  final done = _revealDone;
                  if (done != null && !done.isCompleted) done.complete();
                },
              ),
            )
          else if (_processingGallery)
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
