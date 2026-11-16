import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../services/gallery_asset_source.dart';
import '../services/image_processor.dart';
import '../theme.dart';
import 'gallery_import_review_screen.dart';

/// CamScanner-style "Select Photo" screen.
///
/// One screen does the whole import: the device photos are shown in a grid,
/// the top-left box of a tile selects it (numbered in pick order), tapping
/// the picture opens a full preview with its own Select box, and
/// `Import(n)` detects corners, crops, enhances and returns straight to the
/// document. There is no second confirmation or corner dialog in between.
class GalleryPickerScreen extends StatefulWidget {
  const GalleryPickerScreen({super.key, required this.source,
      this.initialAutoCrop = true,
      this.initialFilter = ScanFilter.enhance,
      this.preferIdCardBounds = false,
      this.maxSelection});

  final GalleryAssetSource source;
  final bool initialAutoCrop;
  final ScanFilter initialFilter;
  final bool preferIdCardBounds;

  /// Largest number of photos that may be imported, or null for no limit.
  final int? maxSelection;

  @override
  State<GalleryPickerScreen> createState() => _GalleryPickerScreenState();
}

class _GalleryPickerScreenState extends State<GalleryPickerScreen> {
  /// Selected photo indexes in the order they were picked.
  final List<int> _picked = [];
  final Map<int, Future<Uint8List?>> _thumbnails = {};
  bool _autoCrop = true;
  bool _busy = false;
  String _progress = '';
  ScanFilter _filter = ScanFilter.enhance;

  static const _choices = <ScanFilter>[
    ScanFilter.enhance,
    ScanFilter.original,
    ScanFilter.magicColor,
    ScanFilter.blackWhite,
  ];

  @override
  void initState() {
    super.initState();
    _autoCrop = widget.initialAutoCrop;
    _filter = _choices.contains(widget.initialFilter)
        ? widget.initialFilter : ScanFilter.enhance;
  }

  String _filterName(ScanFilter filter) => switch (filter) {
    ScanFilter.magicColor => 'Magic Pro',
    ScanFilter.blackWhite => 'B&W',
    _ => filter.label,
  };

  Future<Uint8List?> _thumbnail(int index) {
    // Keep the cache bounded while scrolling through thousands of photos.
    if (_thumbnails.length > 600) {
      for (final key in _thumbnails.keys.take(200).toList()) {
        _thumbnails.remove(key);
      }
    }
    return _thumbnails.putIfAbsent(index, () async {
      try {
        return await widget.source.thumbnail(index);
      } catch (_) {
        return null;
      }
    });
  }

  void _toggle(int index) {
    if (_busy) return;
    if (_picked.contains(index)) {
      setState(() => _picked.remove(index));
      return;
    }
    final limit = widget.maxSelection;
    if (limit != null && _picked.length >= limit) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
            content: Text('Only $limit photo(s) can be selected here.')));
      return;
    }
    setState(() => _picked.add(index));
  }

  Future<void> _openPreview(int index) async {
    if (_busy) return;
    await Navigator.of(context).push<void>(MaterialPageRoute(
      builder: (_) => _GalleryPreview(
        source: widget.source,
        initialIndex: index,
        isPicked: _picked.contains,
        onToggle: _toggle,
      ),
    ));
    if (mounted) setState(() {});
  }

  Future<void> _import() async {
    if (_busy || _picked.isEmpty) return;
    setState(() { _busy = true; _progress = 'Loading selected photos…'; });
    try {
      final sourcePaths = <String>[];
      for (final index in List<int>.of(_picked)) {
        final path = await widget.source.filePath(index);
        if (path != null) sourcePaths.add(path);
      }
      if (sourcePaths.isEmpty) {
        throw const FileSystemException('The selected photos are unreadable');
      }
      final result = await processGalleryImport(
        sourcePaths: sourcePaths,
        autoCrop: _autoCrop,
        filter: _filter,
        preferIdCardBounds: widget.preferIdCardBounds,
        onProgress: (message) {
          if (mounted) setState(() => _progress = message);
        },
      );
      if (mounted) Navigator.pop(context, result);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Could not import selected photos: $error')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _tile(int index) {
    final order = _picked.indexOf(index);
    final picked = order >= 0;
    return GestureDetector(
      key: Key('gallery-photo-$index'),
      onTap: () => _openPreview(index),
      child: Stack(fit: StackFit.expand, children: [
        FutureBuilder<Uint8List?>(
          future: _thumbnail(index),
          builder: (context, snapshot) {
            final bytes = snapshot.data;
            if (bytes == null) {
              return ColoredBox(
                color: const Color(0xFF2A2C30),
                child: snapshot.connectionState == ConnectionState.done
                    ? const Icon(Icons.image_not_supported_outlined,
                        color: Colors.white38)
                    : null,
              );
            }
            return Image.memory(bytes, fit: BoxFit.cover,
                gaplessPlayback: true,
                errorBuilder: (_, _, _) => const ColoredBox(
                    color: Color(0xFF2A2C30)));
          },
        ),
        if (picked) const ColoredBox(color: Color(0x80000000)),
        // A generous touch area around the small corner box.
        Positioned(top: 0, left: 0, child: GestureDetector(
          key: Key('gallery-select-$index'),
          behavior: HitTestBehavior.opaque,
          onTap: () => _toggle(index),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(6, 6, 18, 18),
            child: Container(
              width: 24, height: 24, alignment: Alignment.center,
              decoration: BoxDecoration(
                color: picked ? dsTeal : const Color(0x33000000),
                border: picked ? null
                    : Border.all(color: Colors.white, width: 1.6),
                borderRadius: BorderRadius.circular(5)),
              child: picked
                  ? Text('${order + 1}', style: const TextStyle(
                      color: Colors.white, fontSize: 13,
                      fontWeight: FontWeight.bold))
                  : null,
            ),
          ),
        )),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final count = widget.source.count;
    return PopScope(canPop: !_busy, child: Scaffold(
      backgroundColor: const Color(0xFF181A1D),
      appBar: AppBar(
        backgroundColor: const Color(0xFF24262A),
        foregroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.close),
          tooltip: 'Close',
          onPressed: _busy ? null : () => Navigator.maybePop(context)),
        title: const Text('Select Photo', style: TextStyle(fontSize: 17)),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 10),
            child: Center(child: FilledButton(
              key: const Key('gallery-import'),
              style: FilledButton.styleFrom(
                backgroundColor: dsTeal,
                disabledBackgroundColor: const Color(0xFF3A3C40),
                disabledForegroundColor: Colors.white38,
                minimumSize: const Size(0, 32),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(6))),
              onPressed: _busy || _picked.isEmpty ? null : _import,
              child: Text('Import(${_picked.length})'),
            )),
          ),
        ],
      ),
      body: SafeArea(child: Stack(children: [
        Column(children: [
          Expanded(child: GridView.builder(
            padding: const EdgeInsets.all(4),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3, crossAxisSpacing: 4, mainAxisSpacing: 4),
            itemCount: count,
            itemBuilder: (context, index) => _tile(index),
          )),
          Container(color: const Color(0xFF24262A),
            padding: const EdgeInsets.fromLTRB(12, 2, 8, 2),
            child: Row(children: [
              DropdownButton<ScanFilter>(
                key: const Key('gallery-enhance'),
                value: _filter, dropdownColor: const Color(0xFF2C2C2F),
                underline: const SizedBox.shrink(),
                iconEnabledColor: dsTeal,
                style: const TextStyle(color: dsTeal),
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
                key: const Key('gallery-auto-crop'),
                value: _autoCrop, activeColor: dsTeal,
                onChanged: _busy ? null : (value) =>
                    setState(() => _autoCrop = value ?? false)),
              const Text('Auto Crop', style: TextStyle(color: dsTeal)),
              const SizedBox(width: 6),
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

/// Full-screen, swipeable preview with a "Select" box, titled `n/total`.
class _GalleryPreview extends StatefulWidget {
  const _GalleryPreview({required this.source, required this.initialIndex,
      required this.isPicked, required this.onToggle});

  final GalleryAssetSource source;
  final int initialIndex;
  final bool Function(int index) isPicked;
  final void Function(int index) onToggle;

  @override
  State<_GalleryPreview> createState() => _GalleryPreviewState();
}

class _GalleryPreviewState extends State<_GalleryPreview> {
  late final PageController _controller =
      PageController(initialPage: widget.initialIndex);
  late int _index = widget.initialIndex;
  final Map<int, Future<String?>> _files = {};

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<String?> _file(int index) => _files.putIfAbsent(index, () async {
    try {
      return await widget.source.filePath(index);
    } catch (_) {
      return null;
    }
  });

  @override
  Widget build(BuildContext context) {
    final picked = widget.isPicked(_index);
    return Scaffold(
      backgroundColor: const Color(0xFF181A1D),
      appBar: AppBar(
        backgroundColor: const Color(0xFF24262A),
        foregroundColor: Colors.white,
        title: Text('${_index + 1}/${widget.source.count}',
            style: const TextStyle(fontSize: 17)),
      ),
      body: SafeArea(child: Column(children: [
        Expanded(child: PageView.builder(
          controller: _controller,
          itemCount: widget.source.count,
          onPageChanged: (index) => setState(() => _index = index),
          itemBuilder: (context, index) => FutureBuilder<String?>(
            future: _file(index),
            builder: (context, snapshot) {
              final path = snapshot.data;
              if (path == null) {
                return Center(
                  child: snapshot.connectionState == ConnectionState.done
                      ? const Icon(Icons.image_not_supported_outlined,
                          color: Colors.white38, size: 48)
                      : const CircularProgressIndicator(color: dsTeal));
              }
              return InteractiveViewer(minScale: 1, maxScale: 5,
                child: Image.file(File(path), fit: BoxFit.contain,
                  cacheWidth: 1440,
                  errorBuilder: (_, _, _) => const Center(child: Icon(
                      Icons.image_not_supported_outlined,
                      color: Colors.white38, size: 48))));
            },
          ),
        )),
        Container(color: const Color(0xFF24262A),
          padding: const EdgeInsets.fromLTRB(12, 2, 12, 2),
          child: Row(children: [
            const Spacer(),
            Checkbox(
              key: const Key('gallery-preview-select'),
              value: picked, activeColor: dsTeal,
              onChanged: (_) {
                widget.onToggle(_index);
                setState(() {});
              }),
            const Text('Select', style: TextStyle(color: dsTeal)),
          ])),
      ])),
    );
  }
}
