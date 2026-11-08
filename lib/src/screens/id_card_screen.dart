import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import '../models.dart';
import '../services/document_edges.dart';
import '../services/id_card_page_composer.dart';
import '../services/image_processor.dart';
import '../storage/document_store.dart';
import '../theme.dart';
import 'camera_screen.dart';
import 'crop_screen.dart';
import 'document_detail_screen.dart';
import 'id_card_templates.dart';

class IdCardScreen extends StatefulWidget {
  const IdCardScreen({super.key, required this.store, required this.kind,
      this.template, this.openCameraInitially = false});

  final DocumentStore store;
  final DocumentKind kind;
  final IdCardTemplate? template;
  final bool openCameraInitially;

  @override
  State<IdCardScreen> createState() => _IdCardScreenState();
}

class _IdCardScreenState extends State<IdCardScreen> {
  final List<String> _selected = [];
  final List<String> _originals = [];
  // Never lose the full camera still. Re-cropping an already cropped card
  // cannot bring back clipped text or the missing card corners.
  final List<String> _sourcePaths = [];
  final _picker = ImagePicker();
  bool _saving = false;
  bool _importing = false;
  bool _compact = false;
  int _activeIndex = 0;
  String _watermark = '';

  int get _sideCount => widget.template?.sideCount ?? 2;
  bool get _twoSided => widget.kind.twoSided;
  int? get _maxImages => widget.template == IdCardTemplate.general
      ? null : _sideCount;
  bool get _canSave => _twoSided ? _selected.length == 2
      : _selected.isNotEmpty;

  String _sideLabel(int index) =>
      widget.template?.sideName(index) ?? (index == 0 ? 'Front' : 'Back');

  @override
  void initState() {
    super.initState();
    if (widget.openCameraInitially) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_capture());
      });
    }
  }

  void _warn(String message) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _import() async {
    if (_importing) return;
    final remaining = _maxImages == null ? null : _maxImages! - _selected.length;
    if (remaining != null && remaining <= 0) {
      _warn('Only $_maxImages image(s) are allowed for this template.');
      return;
    }
    try {
      List<String> paths;
      if (remaining == 1) {
        final single = await _picker.pickImage(source: ImageSource.gallery);
        paths = single == null ? [] : [single.path];
      } else {
        final photos = await _picker.pickMultiImage(
          limit: remaining,
          requestFullMetadata: false,
        );
        paths = photos.map((photo) => photo.path).toList();
      }
      if (!mounted) return;
      if (remaining != null && paths.length > remaining) {
        _warn('Please select a maximum of $remaining image(s).');
        return;
      }
      setState(() => _importing = true);
      final cropped = await DocumentEdges.autoCropFiles(paths,
          preferIdCardBounds: _twoSided);
      if (!mounted) return;
      if (cropped.needsReview > 0) {
        _warn('Please check corners for ${cropped.needsReview} card image(s).');
      }
      setState(() {
        _selected.addAll(cropped.paths);
        _originals.addAll(cropped.paths);
        _sourcePaths.addAll(paths);
        _activeIndex = _selected.length - 1;
      });
    } catch (error) {
      _warn('Import failed: $error');
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  Future<void> _capture() async {
    if (_maxImages != null && _selected.length >= _maxImages!) {
      _warn('This template already has all required photos.');
      return;
    }
    final remainingForCamera = _maxImages == null
        ? null : _maxImages! - _selected.length;
    var capturedRaw = <String>[];
    final paths = await Navigator.push<List<String>>(context, MaterialPageRoute(
      builder: (_) => CameraScreen(
        cardMode: true,
        cardTemplate: widget.template,
        side: _sideLabel(_selected.length),
        cardCaptureLimit: remainingForCamera,
        onCardSourcePaths: (paths) => capturedRaw = List<String>.from(paths),
      ),
    ));
    if (!mounted) return;
    if (paths == null) {
      if (widget.openCameraInitially && _selected.isEmpty) {
        Navigator.pop(context);
      }
      return;
    }
    final remaining = _maxImages == null ? null : _maxImages! - _selected.length;
    if (remaining != null && paths.length > remaining) {
      _warn('Only $remaining more image(s) allowed.');
      return;
    }
    setState(() {
      _selected.addAll(paths);
      _originals.addAll(paths);
      _sourcePaths.addAll(List<String>.generate(paths.length, (index) =>
          index < capturedRaw.length ? capturedRaw[index] : paths[index]));
      _activeIndex = _selected.length - 1;
    });
  }

  Future<void> _adjustSide(int index) async {
    if (_saving || _importing || index >= _selected.length) return;
    final result = await Navigator.push<Uint8List>(context, MaterialPageRoute(
      builder: (_) => CropScreen(
        imagePath: _sourcePaths[index],
        preferIdCardBounds: _twoSided,
      ),
    ));
    if (!mounted || result == null) return;
    try {
      final temporaryDirectory = await getTemporaryDirectory();
      final file = File('${temporaryDirectory.path}/ds_card_'
          '${DateTime.now().microsecondsSinceEpoch}_$index.jpg');
      await file.writeAsBytes(result, flush: true);
      if (mounted) setState(() {
        _selected[index] = file.path;
        _originals[index] = file.path;
      });
    } catch (error) {
      _warn('Could not save adjusted card: $error');
    }
  }

  Future<void> _replaceActive() async {
    if (_selected.isEmpty || _saving || _importing) return;
    final photo = await _picker.pickImage(source: ImageSource.gallery);
    if (photo == null || !mounted) return;
    setState(() => _importing = true);
    try {
      final cropped = await DocumentEdges.autoCropFiles([photo.path],
          preferIdCardBounds: _twoSided);
      if (!mounted) return;
      setState(() {
        _selected[_activeIndex] = cropped.paths.first;
        _originals[_activeIndex] = cropped.paths.first;
        _sourcePaths[_activeIndex] = photo.path;
      });
    } catch (error) {
      _warn('Could not replace side: $error');
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  Future<void> _transform({int rotation = 0,
      ScanFilter filter = ScanFilter.original}) async {
    if (_selected.isEmpty || _saving || _importing) return;
    final index = _activeIndex;
    setState(() => _importing = true);
    try {
      final bytes = await ImageProcessor.process(
        await File(_selected[index]).readAsBytes(),
        rotateDegrees: rotation, filter: filter,
      );
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/ds_card_edit_'
          '${DateTime.now().microsecondsSinceEpoch}_$index.jpg');
      await file.writeAsBytes(bytes, flush: true);
      if (mounted) setState(() => _selected[index] = file.path);
    } catch (error) {
      _warn('Could not edit card: $error');
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  Future<void> _chooseFilter() async {
    if (_selected.isEmpty) return;
    final filter = await showModalBottomSheet<ScanFilter>(context: context,
      backgroundColor: const Color(0xFF242426),
      builder: (sheet) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min,
        children: [
          const Padding(padding: EdgeInsets.all(17), child: Text('Filter',
            style: TextStyle(color: Colors.white, fontSize: 18))),
          for (final filter in const [ScanFilter.original,
            ScanFilter.enhance, ScanFilter.magicColor,
            ScanFilter.grayscale, ScanFilter.blackWhite])
            ListTile(title: Text(filter.label, style: const TextStyle(
              color: Colors.white)),
              onTap: () => Navigator.pop(sheet, filter)),
        ],
      )),
    );
    if (filter != null && filter != ScanFilter.original && mounted) {
      await _transform(filter: filter);
    } else if (filter == ScanFilter.original && mounted) {
      setState(() => _selected[_activeIndex] = _originals[_activeIndex]);
    }
  }

  Future<void> _compare() async {
    if (_selected.isEmpty) return;
    final index = _activeIndex;
    await showDialog<void>(context: context, builder: (dialog) => Dialog(
      backgroundColor: const Color(0xFF222224),
      child: Padding(padding: const EdgeInsets.all(12), child: Column(
        mainAxisSize: MainAxisSize.min, children: [
          const Text('Compare', style: TextStyle(color: Colors.white,
            fontSize: 18)),
          const SizedBox(height: 12),
          Row(children: [
            for (final entry in [
              ('Original', _originals[index]), ('Edited', _selected[index])
            ]) Expanded(child: Column(children: [
              Text(entry.$1, style: const TextStyle(color: Colors.white70)),
              const SizedBox(height: 8),
              SizedBox(height: 190, child: Image.file(File(entry.$2),
                fit: BoxFit.contain)),
            ])),
          ]),
          TextButton(onPressed: () => Navigator.pop(dialog),
            child: const Text('Close', style: TextStyle(color: dsTeal))),
        ],
      )),
    ));
  }

  Future<void> _templates() async {
    if (!_twoSided) return;
    final choice = await showModalBottomSheet<bool>(context: context,
      backgroundColor: const Color(0xFF242426),
      builder: (sheet) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min,
        children: [
          const Padding(padding: EdgeInsets.all(18), child: Text('Page Templates',
            style: TextStyle(color: Colors.white, fontSize: 18))),
          for (final item in const [(false, 'A4 General Copy'),
            (true, 'A4 Compact Copy')])
            ListTile(leading: Icon(item.$1 == _compact ? Icons.check_circle
                : Icons.circle_outlined, color: dsTeal),
              title: Text(item.$2,
                style: const TextStyle(color: Colors.white)),
              onTap: () => Navigator.pop(sheet, item.$1)),
        ],
      )),
    );
    if (choice != null && mounted) setState(() => _compact = choice);
  }

  Future<void> _addWatermark() async {
    final controller = TextEditingController(text: _watermark);
    final value = await showDialog<String>(context: context,
      builder: (dialog) => AlertDialog(title: const Text('Add Watermark'),
        content: TextField(controller: controller,
          maxLength: 45,
          decoration: const InputDecoration(hintText: 'Watermark text')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialog),
            child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(dialog, ''),
            child: const Text('Remove')),
          FilledButton(onPressed: () => Navigator.pop(dialog,
              controller.text.trim()), child: const Text('Apply')),
        ],
      ));
    controller.dispose();
    if (value != null && mounted) setState(() => _watermark = value);
  }

  Future<void> _finish() async {
    if (!_canSave || _saving) return;
    setState(() => _saving = true);
    try {
      var paths = List<String>.from(_selected);
      if (_twoSided) {
        var bytes = await IdCardPageComposer.compose([
          await File(paths[0]).readAsBytes(),
          await File(paths[1]).readAsBytes(),
        ], compact: _compact);
        if (_watermark.isNotEmpty) {
          bytes = await IdCardPageComposer.withWatermark(bytes, _watermark);
        }
        final tmp = await getTemporaryDirectory();
        final page = File('${tmp.path}/ds_card_a4_'
            '${DateTime.now().microsecondsSinceEpoch}.jpg');
        await page.writeAsBytes(bytes, flush: true);
        paths = [page.path];
      } else if (_watermark.isNotEmpty) {
        final tmp = await getTemporaryDirectory();
        final marked = <String>[];
        for (var i = 0; i < paths.length; i++) {
          final bytes = await IdCardPageComposer.withWatermark(
              await File(paths[i]).readAsBytes(), _watermark);
          final file = File('${tmp.path}/ds_card_marked_'
              '${DateTime.now().microsecondsSinceEpoch}_$i.jpg');
          await file.writeAsBytes(bytes, flush: true);
          marked.add(file.path);
        }
        paths = marked;
      }
      final document = await widget.store.createFromPaths(
        paths, kind: widget.kind, compositeCardPages: _twoSided,
      );
      if (!mounted) return;
      await Navigator.push<void>(context, MaterialPageRoute(
        builder: (_) => DocumentDetailScreen(store: widget.store,
            documentId: document.id),
      ));
      if (mounted) Navigator.pop(context);
    } catch (error) {
      _warn('Could not save card: $error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFF151517),
    appBar: AppBar(
      backgroundColor: Colors.black,
      foregroundColor: Colors.white,
      title: Text(widget.template?.label ?? widget.kind.label),
      actions: [
        TextButton(onPressed: _canSave && !_saving && !_importing
            ? _finish : null,
          child: Text('Done', style: TextStyle(
            color: _canSave ? dsTeal : Colors.white38,
            fontWeight: FontWeight.bold))),
      ],
    ),
    body: SafeArea(child: Column(children: [
      Padding(padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: Row(children: [
          Text(_twoSided ? 'Page 01 / 01' :
              '${_selected.length} page${_selected.length == 1 ? '' : 's'}',
            style: const TextStyle(color: Colors.white70, fontSize: 14)),
          const Spacer(),
          if (_twoSided)
            Text('${_selected.length}/2 sides',
              style: const TextStyle(color: dsTeal)),
          if (!_twoSided && _selected.isNotEmpty)
            const Text('Swipe to review',
              style: TextStyle(color: Colors.white54, fontSize: 12)),
        ]),
      ),
      Expanded(child: _twoSided ? _a4Page() : _generalPages()),
      if (_selected.isNotEmpty)
        Container(color: const Color(0xFF242427),
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _action(Icons.compare_outlined, 'Compare', _compare),
              if (_twoSided) _action(Icons.dashboard_customize_outlined,
                  'Templates', _templates),
              _action(Icons.crop_rotate_outlined, 'Crop',
                  () => _adjustSide(_activeIndex)),
              _action(Icons.rotate_right_outlined, 'Rotate',
                  () => _transform(rotation: 90)),
              _action(Icons.filter_alt_outlined, 'Filter', _chooseFilter),
              _action(Icons.water_drop_outlined, 'Watermark', _addWatermark),
            ],
          ),
        ),
      if (_saving || _importing)
        const LinearProgressIndicator(color: dsTeal),
      Container(color: Colors.black,
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (_watermark.isNotEmpty)
            Text('Watermark: $_watermark', maxLines: 1,
              style: const TextStyle(color: Colors.white70, fontSize: 11)),
          Row(children: [
            Expanded(child: OutlinedButton.icon(
              onPressed: _saving || _importing ||
                  (_maxImages != null && _selected.length >= _maxImages!)
                  ? (_twoSided && _selected.isNotEmpty ? _replaceActive : null)
                  : _import,
              icon: const Icon(Icons.photo_library_outlined),
              label: Text(_twoSided && _selected.length == 2
                  ? 'Replace side' : 'Gallery'),
              style: OutlinedButton.styleFrom(foregroundColor: Colors.white),
            )),
            const SizedBox(width: 10),
            Expanded(child: OutlinedButton.icon(
              onPressed: _saving || _importing ||
                  (_maxImages != null && _selected.length >= _maxImages!)
                  ? null : _capture,
              icon: const Icon(Icons.camera_alt_outlined),
              label: const Text('Scan'),
              style: OutlinedButton.styleFrom(foregroundColor: Colors.white),
            )),
            const SizedBox(width: 10),
            Expanded(child: FilledButton.icon(
              onPressed: _canSave && !_saving && !_importing ? _finish : null,
              style: FilledButton.styleFrom(backgroundColor: dsTeal,
                foregroundColor: Colors.white),
              icon: const Icon(Icons.check), label: const Text('Done'),
            )),
          ]),
        ]),
      ),
    ])),
  );

  Widget _action(IconData icon, String title, VoidCallback tap) =>
      Expanded(child: InkWell(
        onTap: _saving || _importing ? null : tap,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, color: Colors.white, size: 23),
          const SizedBox(height: 5),
          Text(title, maxLines: 1, style: const TextStyle(
            color: Colors.white, fontSize: 10)),
        ]),
      ));

  Widget _a4Page() => Center(child: SingleChildScrollView(
    padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
    child: Center(child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 385),
      child: AspectRatio(aspectRatio: IdCardPageComposer.pageWidth /
          IdCardPageComposer.pageHeight,
        child: LayoutBuilder(builder: (context, constraints) {
          final width = constraints.maxWidth;
          final height = constraints.maxHeight;
          // Real ID-1 cards are about 86 mm wide on a 210 mm A4 sheet.
          // The former 85%-wide slot made both sides look oversized.
          final cardWidth = width * (_compact ? .456 : .484);
          final cardHeight = height * (_compact ? .202 : .217);
          final centers = _compact ? const [.388, .616] : const [.322, .679];
          return Container(color: Colors.white,
            child: Stack(children: [
              for (var i = 0; i < 2; i++)
                Positioned(left: (width - cardWidth) / 2,
                  top: height * centers[i] - cardHeight / 2,
                  width: cardWidth, height: cardHeight,
                  child: InkWell(
                    key: Key('id-card-side-$i'),
                    onTap: () => i < _selected.length
                        ? setState(() => _activeIndex = i)
                        : _capture(),
                    child: Container(
                      decoration: BoxDecoration(
                        border: Border.all(color: i == _activeIndex
                            ? dsTeal : const Color(0xFFDDDDDD),
                          width: i == _activeIndex ? 2 : 1)),
                      child: i < _selected.length
                          ? Image.file(File(_selected[i]),
                              fit: BoxFit.contain,
                              key: ValueKey(_selected[i]))
                          : Center(child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.add_a_photo_outlined,
                                  color: Colors.grey),
                                Text(_sideLabel(i), style:
                                  const TextStyle(color: Colors.black54)),
                              ],
                            )),
                    ),
                  ),
                ),
              if (_watermark.isNotEmpty)
                Positioned(bottom: 10, left: 8, right: 8,
                  child: Text(_watermark, textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.grey))),
            ]),
          );
        }),
      ),
    )),
  ));

  Widget _generalPages() => _selected.isEmpty
      ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.document_scanner_outlined,
            color: Colors.white54, size: 76),
          const SizedBox(height: 12),
          Text('Scan or import ${widget.template?.label ?? 'documents'}',
            style: const TextStyle(color: Colors.white70)),
        ]))
      : ListView.separated(
          padding: const EdgeInsets.fromLTRB(26, 10, 26, 16),
          itemCount: _selected.length,
          separatorBuilder: (_, _) => const SizedBox(height: 20),
          itemBuilder: (context, index) => Center(child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 345),
            child: Column(children: [
              InkWell(onTap: () => setState(() => _activeIndex = index),
                child: Container(
                  key: Key('general-page-$index'),
                  height: 385,
                  decoration: BoxDecoration(color: Colors.white,
                    border: Border.all(color: index == _activeIndex
                        ? dsTeal : Colors.white24, width: 2)),
                  padding: const EdgeInsets.all(14),
                  child: Center(child: Image.file(File(_selected[index]),
                    fit: BoxFit.contain, key: ValueKey(_selected[index]))),
                ),
              ),
              const SizedBox(height: 7),
              Row(children: [
                Text('${index + 1}'.padLeft(2, '0'),
                  style: const TextStyle(color: Colors.white)),
                const Spacer(),
                TextButton.icon(onPressed: () async {
                    setState(() => _activeIndex = index);
                    await _adjustSide(index);
                  },
                  icon: const Icon(Icons.crop, size: 16),
                  label: const Text('Adjust'),
                ),
                IconButton(tooltip: 'Remove page',
                  onPressed: () => setState(() {
                    _selected.removeAt(index);
                    _originals.removeAt(index);
                    _sourcePaths.removeAt(index);
                    if (_selected.isEmpty) {
                      _activeIndex = 0;
                    } else if (_activeIndex >= _selected.length) {
                      _activeIndex = _selected.length - 1;
                    }
                  }),
                  icon: const Icon(Icons.delete_outline,
                    color: Colors.white70)),
              ]),
            ]),
          )),
        );
}
