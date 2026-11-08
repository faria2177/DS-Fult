import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../services/photo_studio_operations.dart';
import '../storage/document_store.dart';
import '../theme.dart';

enum PhotoStudioMode { passport, backgroundRemover, resizer }

/// Three real, entirely offline Tools sharing one source-picker and
/// save/share flow. A processed preview is never persisted until Save.
class PhotoStudioScreen extends StatefulWidget {
  const PhotoStudioScreen({super.key, required this.mode, required this.store});

  final PhotoStudioMode mode;
  final DocumentStore store;

  @override
  State<PhotoStudioScreen> createState() => _PhotoStudioScreenState();
}

class _PhotoStudioScreenState extends State<PhotoStudioScreen> {
  final _picker = ImagePicker();
  final _width = TextEditingController();
  final _height = TextEditingController();
  Uint8List? _source;
  Uint8List? _result;
  int _sourceWidth = 0;
  int _sourceHeight = 0;
  bool _busy = false;
  bool _png = false;
  bool _lockRatio = true;
  bool _printSheet = false;
  bool _showOriginal = false;
  int _quality = 90;
  int _tolerance = 45;
  int _copies = 4;
  double _zoom = 1;
  double _horizontal = 0;
  double _vertical = 0;
  PhotoSizePreset _size = PhotoSizePreset.mm35x45;
  PhotoBackdrop _backdrop = PhotoBackdrop.original;
  String? _error;
  bool _resultPng = false;
  List<int>? _resultDimensions;

  @override
  void initState() {
    super.initState();
    if (widget.mode == PhotoStudioMode.backgroundRemover) {
      _backdrop = PhotoBackdrop.transparent;
    }
  }

  String get _title => switch (widget.mode) {
    PhotoStudioMode.passport => 'Passport Photo Maker',
    PhotoStudioMode.backgroundRemover => 'BG Remover',
    PhotoStudioMode.resizer => 'Image Resizer',
  };

  String get _subtitle => switch (widget.mode) {
    PhotoStudioMode.passport => 'Photo sizes, backgrounds and 4×6 print sheets',
    PhotoStudioMode.backgroundRemover =>
      'Remove a simple photo background entirely offline',
    PhotoStudioMode.resizer => 'Custom size, aspect ratio and image quality',
  };

  @override
  void dispose() {
    _width.dispose();
    _height.dispose();
    super.dispose();
  }

  void _invalidate() {
    setState(() {
      _result = null;
      _resultDimensions = null;
      _error = null;
    });
  }

  Future<void> _load(String path) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final bytes = await File(path).readAsBytes();
      final dimensions = await compute(PhotoStudioOperations.dimensions, bytes);
      if (!mounted) return;
      final scale = math.min(1.0,
          1024.0 / math.max(dimensions[0], dimensions[1]));
      _width.text = math.max(32, (dimensions[0] * scale).round()).toString();
      _height.text = math.max(32, (dimensions[1] * scale).round()).toString();
      setState(() {
        _source = bytes;
        _sourceWidth = dimensions[0];
        _sourceHeight = dimensions[1];
        _result = null;
        _resultDimensions = null;
      });
    } catch (error) {
      if (mounted) setState(() => _error = 'Could not open photo: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pickGallery() async {
    try {
      final image = await _picker.pickImage(
          source: ImageSource.gallery, requestFullMetadata: false);
      if (image != null) await _load(image.path);
    } catch (error) {
      if (mounted) setState(() => _error = 'Gallery is unavailable: $error');
    }
  }

  Future<void> _pickCamera() async {
    try {
      final image = await _picker.pickImage(
          source: ImageSource.camera, requestFullMetadata: false);
      if (image != null) await _load(image.path);
    } catch (error) {
      if (mounted) setState(() => _error = 'Camera is unavailable: $error');
    }
  }

  Future<void> _pickFromDocuments() async {
    final pages = <({String path, String label})>[];
    for (final document in widget.store.documents) {
      if (document.lockHash != null) continue;
      for (var i = 0; i < document.pages.length; i++) {
        pages.add((
          path: document.pages[i].path,
          label: '${document.name} • Page ${i + 1}',
        ));
      }
    }
    if (pages.isEmpty) {
      setState(() => _error = 'No unlocked document images are available.');
      return;
    }
    final path = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (sheet) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(sheet).height * .68,
          child: Column(children: [
            const Padding(padding: EdgeInsets.all(18),
              child: Text('Select an image from DocScanner',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
            Expanded(child: ListView.builder(
              itemCount: pages.length,
              itemBuilder: (_, i) => ListTile(
                leading: ClipRRect(borderRadius: BorderRadius.circular(6),
                  child: Image.file(File(pages[i].path),
                    width: 50, height: 56, fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => const Icon(Icons.image_outlined))),
                title: Text(pages[i].label, maxLines: 1,
                  overflow: TextOverflow.ellipsis),
                onTap: () => Navigator.pop(sheet, pages[i].path),
              ),
            )),
          ]),
        ),
      ),
    );
    if (path != null) await _load(path);
  }

  void _updateWidth(String text) {
    final w = int.tryParse(text);
    if (_lockRatio && w != null && _sourceWidth > 0) {
      _height.text = math.max(1, (w * _sourceHeight / _sourceWidth).round())
          .toString();
    }
    _invalidate();
  }

  void _updateHeight(String text) {
    final h = int.tryParse(text);
    if (_lockRatio && h != null && _sourceHeight > 0) {
      _width.text = math.max(1, (h * _sourceWidth / _sourceHeight).round())
          .toString();
    }
    _invalidate();
  }

  Future<Uint8List?> _ensureResult() async {
    if (_result != null) return _result;
    final source = _source;
    if (source == null || _busy) return null;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final mode = widget.mode;
      final args = <String, Object?>{
        'bytes': source,
        'mode': switch (mode) {
          PhotoStudioMode.passport => 'passport',
          PhotoStudioMode.backgroundRemover => 'remove',
          PhotoStudioMode.resizer => 'resize',
        },
        'tolerance': _tolerance,
        'background': _backdrop.argb,
        'size': _size.index,
        'zoom': _zoom,
        'horizontalShift': _horizontal,
        'verticalShift': _vertical,
        'backdrop': _backdrop.index,
        'width': int.tryParse(_width.text) ?? 0,
        'height': int.tryParse(_height.text) ?? 0,
        'quality': _quality,
        'png': _png,
      };
      var output = await compute(PhotoStudioOperations.process, args);
      if (mode == PhotoStudioMode.passport && _printSheet) {
        output = await compute(PhotoStudioOperations.makeSheet,
          <String, Object?>{'bytes': output, 'copies': _copies});
      }
      final dimensions = await compute(PhotoStudioOperations.dimensions, output);
      if (!mounted) return null;
      setState(() {
        _result = output;
        _resultDimensions = dimensions;
        _resultPng = mode == PhotoStudioMode.backgroundRemover ||
            (mode == PhotoStudioMode.resizer && _png);
        _showOriginal = false;
      });
      return output;
    } catch (error) {
      if (mounted) setState(() => _error = 'Processing failed: $error');
      return null;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<File?> _outputFile() async {
    final bytes = await _ensureResult();
    if (bytes == null) return null;
    final directory = await getTemporaryDirectory();
    final extension = _resultPng ? 'png' : 'jpg';
    final filename = 'docscanner_${widget.mode.name}_'
        '${DateTime.now().microsecondsSinceEpoch}.$extension';
    final file = File(p.join(directory.path, filename));
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  Future<void> _save() async {
    final file = await _outputFile();
    if (file == null) return;
    try {
      await widget.store.createFromPaths([file.path], name: _title);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Done — saved as a new document')));
      }
    } catch (error) {
      if (mounted) setState(() => _error = 'Could not save image: $error');
    }
  }

  Future<void> _share() async {
    final file = await _outputFile();
    if (file == null) return;
    try {
      await SharePlus.instance.share(ShareParams(
        files: [XFile(file.path,
          mimeType: _resultPng ? 'image/png' : 'image/jpeg')],
        subject: _title,
      ));
    } catch (error) {
      if (mounted) setState(() => _error = 'Could not share image: $error');
    }
  }

  Widget _section(String label, Widget child) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(padding: const EdgeInsets.only(top: 18, bottom: 9),
        child: Text(label, style: const TextStyle(
          fontSize: 15, fontWeight: FontWeight.w700))),
      child,
    ],
  );

  Widget _backdrops({required bool allowOriginal}) => Wrap(
    spacing: 8, runSpacing: 6,
    children: [
      for (final option in PhotoBackdrop.values)
        if ((option != PhotoBackdrop.original || allowOriginal) &&
            (widget.mode != PhotoStudioMode.passport ||
                option != PhotoBackdrop.transparent))
          ChoiceChip(
            label: Text(option.label),
            selected: _backdrop == option,
            onSelected: (_) {
              _backdrop = option;
              _invalidate();
            },
          ),
    ],
  );

  Widget _passportOptions() {
    final capacity = PhotoStudioOperations.sheetCapacity(_size);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _section('Official photo size (300 DPI)', DropdownButton<PhotoSizePreset>(
        value: _size, isExpanded: true,
        items: [
          for (final size in PhotoSizePreset.values)
            DropdownMenuItem(value: size, child: Text(size.label)),
        ],
        onChanged: (value) {
          if (value == null) return;
          _size = value;
          _copies = math.min(_copies, PhotoStudioOperations.sheetCapacity(value));
          _invalidate();
        },
      )),
      _section('Background', _backdrops(allowOriginal: true)),
      if (_backdrop != PhotoBackdrop.original)
        const Text('Solid backgrounds work best. Check hair and shoulder edges.',
          style: TextStyle(fontSize: 12, color: dsMuted)),
      _section('Photo framing', Column(children: [
        _slider('Zoom', _zoom, 1, 2.5, (v) {
          _zoom = v;
          _invalidate();
        }),
        _slider('Left / Right', _horizontal, -1, 1, (v) {
          _horizontal = v;
          _invalidate();
        }),
        _slider('Up / Down', _vertical, -1, 1, (v) {
          _vertical = v;
          _invalidate();
        }),
      ])),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('4×6 inch print sheet'),
        subtitle: const Text('Repeat the photo at the selected real size'),
        value: _printSheet,
        onChanged: (v) {
          _printSheet = v;
          _invalidate();
        },
      ),
      if (_printSheet)
        _section('Copies per sheet (maximum $capacity)',
          Wrap(spacing: 8, children: [
            for (final count in [1, 2, 4, 6, 8])
              if (count <= capacity)
                ChoiceChip(label: Text('$count'), selected: _copies == count,
                  onSelected: (_) {
                    _copies = count;
                    _invalidate();
                  }),
          ]),
        ),
    ]);
  }

  Widget _backgroundOptions() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _section('Output background', _backdrops(allowOriginal: false)),
      _section('Background sensitivity', _slider(
        'Color tolerance: $_tolerance', _tolerance.toDouble(), 8, 120, (value) {
          _tolerance = value.round();
          _invalidate();
        },
      )),
      const Padding(
        padding: EdgeInsets.only(top: 8),
        child: Text('Offline color-based removal works best with a uniform '
          'wall or studio background. It is not AI person segmentation.',
          style: TextStyle(fontSize: 12, color: dsMuted)),
      ),
    ],
  );

  Widget _resizeOptions() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _section('Quick resize', Wrap(spacing: 8, children: [
        for (final percentage in [25, 50, 75, 100])
          ActionChip(label: Text('$percentage%'), onPressed: () {
            _width.text = math.max(32,
                (_sourceWidth * percentage / 100).round()).toString();
            _height.text = math.max(32,
                (_sourceHeight * percentage / 100).round()).toString();
            _invalidate();
          }),
      ])),
      _section('Custom dimensions (pixels)', Row(children: [
        Expanded(child: TextField(
          key: const Key('resize-width'),
          controller: _width,
          keyboardType: TextInputType.number,
          onChanged: _updateWidth,
          decoration: const InputDecoration(labelText: 'Width',
              border: OutlineInputBorder()),
        )),
        const SizedBox(width: 12),
        Expanded(child: TextField(
          key: const Key('resize-height'),
          controller: _height,
          keyboardType: TextInputType.number,
          onChanged: _updateHeight,
          decoration: const InputDecoration(labelText: 'Height',
              border: OutlineInputBorder()),
        )),
      ])),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Lock aspect ratio'),
        value: _lockRatio,
        onChanged: (value) => setState(() => _lockRatio = value),
      ),
      _section('Output format', Wrap(spacing: 8, children: [
        for (final format in [false, true])
          ChoiceChip(
            label: Text(format ? 'PNG (lossless)' : 'JPEG (smaller file)'),
            selected: _png == format,
            onSelected: (_) {
              _png = format;
              _invalidate();
            },
          ),
      ])),
      if (!_png) _section('JPEG quality', _slider(
        '$_quality%', _quality.toDouble(), 40, 100, (value) {
          _quality = value.round();
          _invalidate();
        },
      )),
    ],
  );

  Widget _slider(String label, double value, double min, double max,
      ValueChanged<double> onChanged) => Column(
    children: [
      Align(alignment: Alignment.centerLeft,
        child: Text(label, style: const TextStyle(fontSize: 12))),
      Slider(value: value.clamp(min, max).toDouble(), min: min, max: max,
        onChanged: _busy ? null : onChanged),
    ],
  );

  Widget _preview() {
    final image = _showOriginal ? _source : (_result ?? _source);
    return Column(children: [
      Container(
        height: 295,
        width: double.infinity,
        decoration: BoxDecoration(
          color: const Color(0xFFE2E7E8),
          borderRadius: BorderRadius.circular(16),
        ),
        child: image == null
            ? const Center(child: Icon(Icons.add_photo_alternate_outlined,
                color: dsMuted, size: 82))
            : ClipRRect(borderRadius: BorderRadius.circular(16),
                child: Image.memory(image, fit: BoxFit.contain,
                  gaplessPlayback: true)),
      ),
      const SizedBox(height: 8),
      if (_source != null)
        Row(children: [
          Expanded(child: Text(
            _result != null && !_showOriginal && _resultDimensions != null
                ? 'Output: ${_resultDimensions![0]} × ${_resultDimensions![1]}'
                  '  •  ${(_result!.length / 1024).round()} KB'
                : 'Original: $_sourceWidth × $_sourceHeight',
            style: const TextStyle(fontSize: 12, color: dsMuted),
          )),
          if (_result != null)
            TextButton(
              onPressed: () => setState(() => _showOriginal = !_showOriginal),
              child: Text(_showOriginal ? 'Show Result' : 'Compare Original'),
            ),
        ]),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_title)),
      body: SafeArea(
        child: Column(children: [
          Expanded(child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 9, 16, 24),
            children: [
              Text(_subtitle, style: const TextStyle(color: dsMuted)),
              const SizedBox(height: 13),
              Row(children: [
                Expanded(child: OutlinedButton.icon(
                  onPressed: _busy ? null : _pickGallery,
                  icon: const Icon(Icons.photo_library_outlined),
                  label: const Text('Gallery'),
                )),
                const SizedBox(width: 9),
                Expanded(child: OutlinedButton.icon(
                  onPressed: _busy ? null : _pickCamera,
                  icon: const Icon(Icons.camera_alt_outlined),
                  label: const Text('Camera'),
                )),
              ]),
              const SizedBox(height: 4),
              SizedBox(width: double.infinity, child: OutlinedButton.icon(
                  onPressed: _busy ? null : _pickFromDocuments,
                  icon: const Icon(Icons.folder_copy_outlined),
                  label: const Text('My Documents'),
                )),
              const SizedBox(height: 12),
              _preview(),
              if (_source != null)
                switch (widget.mode) {
                  PhotoStudioMode.passport => _passportOptions(),
                  PhotoStudioMode.backgroundRemover => _backgroundOptions(),
                  PhotoStudioMode.resizer => _resizeOptions(),
                },
              if (_error != null)
                Padding(padding: const EdgeInsets.only(top: 12),
                  child: Text(_error!, style: TextStyle(
                    color: Theme.of(context).colorScheme.error))),
            ],
          )),
          if (_source != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Column(children: [
                if (_busy) const LinearProgressIndicator(),
                const SizedBox(height: 6),
                SizedBox(width: double.infinity,
                  child: FilledButton.icon(
                    key: const Key('studio-preview'),
                    onPressed: _busy ? null : _ensureResult,
                    icon: const Icon(Icons.auto_fix_high_outlined),
                    label: Text(_result == null ? 'Preview Result' : 'Refresh Preview'),
                  )),
                Row(children: [
                  Expanded(child: OutlinedButton.icon(
                    key: const Key('studio-save'),
                    onPressed: _busy ? null : _save,
                    icon: const Icon(Icons.save_alt_outlined),
                    label: const Text('Save as New'),
                  )),
                  const SizedBox(width: 10),
                  Expanded(child: FilledButton.icon(
                    key: const Key('studio-share'),
                    onPressed: _busy ? null : _share,
                    icon: const Icon(Icons.share_outlined),
                    label: const Text('Share'),
                  )),
                ]),
              ]),
            ),
        ]),
      ),
    );
  }
}
