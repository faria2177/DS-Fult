import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../services/document_edges.dart';
import '../services/image_processor.dart';
import '../theme.dart';
import 'crop_screen.dart';

/// The user confirms their gallery selection, effect and auto-crop policy
/// *before* any files are transformed. All processing is on-device.
class GalleryImportResult {
  const GalleryImportResult({required this.paths, required this.sourcePaths,
      required this.needsReview, this.failedIndexes = const <int>[]});

  final List<String> paths;
  final List<String> sourcePaths;
  final int needsReview;
  /// Indexes into [paths] still needing manual correction after import.
  final List<int> failedIndexes;
}

class GalleryImportReviewScreen extends StatefulWidget {
  const GalleryImportReviewScreen({super.key, required this.imagePaths,
      this.initialAutoCrop = true,
      this.initialFilter = ScanFilter.enhance,
      this.preferIdCardBounds = false});

  final List<String> imagePaths;
  final bool initialAutoCrop;
  final ScanFilter initialFilter;
  final bool preferIdCardBounds;

  @override
  State<GalleryImportReviewScreen> createState() =>
      _GalleryImportReviewScreenState();
}

class _GalleryImportReviewScreenState extends State<GalleryImportReviewScreen> {
  final Set<int> _selected = {};
  bool _showSelectedOnly = false;
  bool _autoCrop = true;
  bool _busy = false;
  String _progress = '';
  ScanFilter _filter = ScanFilter.enhance;

  @override
  void initState() {
    super.initState();
    _selected.addAll(List<int>.generate(widget.imagePaths.length, (i) => i));
    _autoCrop = widget.initialAutoCrop;
    // Camera presets include effects not shown in this compact import menu.
    // Always choose a visible option rather than passing an unknown value to
    // DropdownButton (which asserts when its value has no matching item).
    _filter = _choices.contains(widget.initialFilter)
        ? widget.initialFilter : ScanFilter.enhance;
  }

  List<int> get _orderedSelection => [
    for (var i = 0; i < widget.imagePaths.length; i++)
      if (_selected.contains(i)) i,
  ];

  static const _choices = <ScanFilter>[
    ScanFilter.enhance,
    ScanFilter.original,
    ScanFilter.magicColor,
    ScanFilter.blackWhite,
  ];

  String _filterName(ScanFilter filter) => switch (filter) {
    ScanFilter.magicColor => 'Magic Pro',
    ScanFilter.blackWhite => 'B&W',
    _ => filter.label,
  };

  void _toggle(int index) {
    if (_busy) return;
    setState(() {
      if (!_selected.remove(index)) _selected.add(index);
    });
  }

  Future<void> _preview(int index) async {
    await showDialog<void>(context: context,
      builder: (dialog) => Dialog(
        backgroundColor: const Color(0xFF17191B),
        insetPadding: const EdgeInsets.all(12),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          SizedBox(height: MediaQuery.sizeOf(dialog).height * .73,
            child: InteractiveViewer(minScale: .75, maxScale: 5,
              child: Image.file(File(widget.imagePaths[index]),
                fit: BoxFit.contain))),
          TextButton(onPressed: () => Navigator.pop(dialog),
              child: const Text('Close')),
        ]),
      ));
  }

  Future<void> _import() async {
    if (_busy || _selected.isEmpty) return;
    final sourcePaths = [for (final i in _orderedSelection) widget.imagePaths[i]];
    setState(() { _busy = true; _progress = 'Detecting document edges…'; });
    try {
      final crop = _autoCrop
          ? await DocumentEdges.autoCropFiles(sourcePaths,
              preferIdCardBounds: widget.preferIdCardBounds)
          : AutoCropBatch(sourcePaths, 0);
      final adjustedPaths = List<String>.of(crop.paths);
      final needsManualReview = <int>{...crop.failedIndexes};
      if (_autoCrop && needsManualReview.isNotEmpty && mounted) {
        // Show an actionable review before returning to the camera or the
        // document editor. A snackbar on CameraScreen disappears when that
        // route pops and can obscure the destination toolbar.
        final reviewNow = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (dialog) => AlertDialog(
            title: const Text('Check document corners'),
            content: Text('${needsManualReview.length} photo(s) have no '
                'reliable outer border. You can drag the four corners now, '
                'or keep the original photos and crop them later.'),
            actions: [
              TextButton(
                key: const Key('import-keep-originals'),
                onPressed: () => Navigator.pop(dialog, false),
                child: const Text('Keep originals'),
              ),
              FilledButton(
                key: const Key('import-review-corners'),
                onPressed: () => Navigator.pop(dialog, true),
                child: const Text('Review corners'),
              ),
            ],
          ),
        );
        if (!mounted) return;
        if (reviewNow == true) {
          final directory = await getTemporaryDirectory();
          for (final index in needsManualReview.toList()..sort()) {
            if (!mounted) return;
            final corrected = await Navigator.of(context).push<Uint8List>(
              MaterialPageRoute(builder: (_) => CropScreen(
                imagePath: sourcePaths[index],
                preferIdCardBounds: widget.preferIdCardBounds,
              )),
            );
            if (corrected == null) continue;
            // Done without moving a handle intentionally retains the original
            // bytes; never treat that as a confirmed document crop.
            final sourceBytes = await File(sourcePaths[index]).readAsBytes();
            if (listEquals(corrected, sourceBytes)) continue;
            final file = File(p.join(directory.path,
                'ds_manual_crop_${DateTime.now().microsecondsSinceEpoch}_$index.jpg'));
            await file.writeAsBytes(corrected, flush: true);
            adjustedPaths[index] = file.path;
            needsManualReview.remove(index);
          }
        }
      }
      final paths = <String>[];
      final folder = _filter == ScanFilter.original
          ? null : await getTemporaryDirectory();
      for (var index = 0; index < adjustedPaths.length; index++) {
        if (mounted) {
          setState(() => _progress =
              'Processing image ${index + 1} of ${adjustedPaths.length}…');
        }
        var result = adjustedPaths[index];
        if (folder != null) {
          try {
            final enhanced = await ImageProcessor.process(
              await File(result).readAsBytes(), filter: _filter,
              // Manual corner corrections receive the same full document
              // enhancement as automatically perspective-cropped pages.
              documentMode: adjustedPaths[index] != sourcePaths[index]);
            final target = File(p.join(folder.path,
                'ds_import_${DateTime.now().microsecondsSinceEpoch}_$index.jpg'));
            await target.writeAsBytes(enhanced, flush: true);
            result = target.path;
          } catch (_) {
            // A failed effect must not discard this page or its source.
          }
        }
        paths.add(result);
      }
      if (mounted) {
        Navigator.pop(context, GalleryImportResult(
          paths: paths,
          sourcePaths: sourcePaths,
          needsReview: needsManualReview.length,
          failedIndexes: needsManualReview.toList()..sort(),
        ));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Could not import selected photos: $error')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final visible = _showSelectedOnly ? _orderedSelection
        : List<int>.generate(widget.imagePaths.length, (i) => i);
    return PopScope(canPop: !_busy, child: Scaffold(
      backgroundColor: const Color(0xFF181A1D),
      appBar: AppBar(
        backgroundColor: const Color(0xFF24262A),
        foregroundColor: Colors.white,
        title: const Text('Select Photo', style: TextStyle(fontSize: 17)),
        actions: [
          TextButton(onPressed: _busy || _selected.isEmpty ? null : _import,
            child: Text('Import (${_selected.length})',
                style: const TextStyle(color: dsTeal))),
        ],
      ),
      body: SafeArea(child: Stack(children: [
        Column(children: [
          Expanded(child: GridView.builder(
            padding: const EdgeInsets.all(6),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3, crossAxisSpacing: 5, mainAxisSpacing: 5),
            itemCount: visible.length,
            itemBuilder: (context, i) {
              final index = visible[i];
              final selected = _selected.contains(index);
              return InkWell(
                key: Key('import-photo-$index'),
                onTap: () => _toggle(index),
                onLongPress: () => _preview(index),
                child: Stack(fit: StackFit.expand, children: [
                  Image.file(File(widget.imagePaths[index]),
                    cacheWidth: 270, fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => const ColoredBox(
                      color: Color(0xFF35363A),
                      child: Icon(Icons.image_not_supported_outlined,
                          color: Colors.white54))),
                  Positioned(top: 5, left: 5, child: Container(
                    decoration: BoxDecoration(
                      color: selected ? dsTeal : const Color(0x88000000),
                      border: Border.all(color: Colors.white70),
                      borderRadius: BorderRadius.circular(4)),
                    child: Icon(selected ? Icons.check : Icons.check_box_outline_blank,
                      color: Colors.white, size: 20))),
                  Positioned(bottom: 3, left: 3, child: IconButton(
                    key: Key('preview-photo-$index'),
                    tooltip: 'Preview photo',
                    onPressed: _busy ? null : () => _preview(index),
                    icon: const Icon(Icons.zoom_out_map,
                        color: Colors.white, size: 20))),
                  if (selected) Positioned(bottom: 4, right: 5,
                    child: Text('${_orderedSelection.indexOf(index) + 1}',
                      style: const TextStyle(color: Colors.white,
                          fontWeight: FontWeight.bold,
                          shadows: [Shadow(color: Colors.black, blurRadius: 5)]))),
                ]),
              );
            },
          )),
          Container(color: const Color(0xFF27292C),
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            child: Row(children: [
              TextButton.icon(
                onPressed: _busy ? null : () => setState(() =>
                    _showSelectedOnly = !_showSelectedOnly),
                icon: Icon(_showSelectedOnly ? Icons.grid_view :
                    Icons.collections_outlined, color: Colors.white70),
                label: Text(_showSelectedOnly ? 'View all' : 'View selected',
                    style: const TextStyle(color: Colors.white70))),
              const Spacer(),
              Text('${_selected.length} selected',
                  style: const TextStyle(color: Colors.white70)),
            ])),
          Container(color: const Color(0xFF181A1D),
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
            child: Row(children: [
              const Text('Enhance', style: TextStyle(color: Colors.white70)),
              const SizedBox(width: 8),
              DropdownButton<ScanFilter>(
                key: const Key('import-enhance'),
                value: _filter, dropdownColor: const Color(0xFF2C2C2F),
                style: const TextStyle(color: Colors.white),
                onChanged: _busy ? null : (filter) {
                  if (filter != null) setState(() => _filter = filter);
                },
                items: [for (final filter in _choices)
                  DropdownMenuItem(value: filter,
                    child: Text(_filterName(filter))),
                ],
              ),
              const Spacer(),
              Checkbox(
                key: const Key('import-auto-crop'),
                value: _autoCrop, activeColor: dsTeal,
                onChanged: _busy ? null : (value) =>
                    setState(() => _autoCrop = value ?? false)),
              const Text('Auto Crop', style: TextStyle(color: Colors.white)),
            ])),
        ]),
        if (_busy) Positioned.fill(child: ColoredBox(
          color: const Color(0xD9000000),
          child: Center(child: Column(mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(color: dsTeal),
              const SizedBox(height: 16),
              Text(_progress, style: const TextStyle(color: Colors.white)),
              const SizedBox(height: 6),
              const Text('Please do not quit the app.',
                  style: TextStyle(color: Colors.white70)),
            ])),
        )),
      ])),
    ));
  }
}
