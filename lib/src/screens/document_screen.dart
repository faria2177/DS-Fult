import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../models.dart';
import '../services/document_export.dart';
import '../services/image_processor.dart';
import '../storage/document_store.dart';
import '../theme.dart';
import 'camera_screen.dart';
import 'crop_screen.dart';
import 'edit_text_screen.dart';
import 'pdf_tools_screen.dart';

class DocumentScreen extends StatefulWidget {
  const DocumentScreen({super.key, required this.store, required this.documentId});
  final DocumentStore store;
  final String documentId;

  @override
  State<DocumentScreen> createState() => _DocumentScreenState();
}

class _DocumentScreenState extends State<DocumentScreen> {
  final PageController _pages = PageController();
  int _index = 0;
  bool _busy = false;
  final _picker = ImagePicker();

  ScanDocument? get _document => widget.store.byId(widget.documentId);

  void _message(Object error) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$error')));
  }

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  Future<void> _process(ScanFilter filter, {int rotation = 0}) async {
    final doc = _document;
    if (doc == null || _busy || _index >= doc.pages.length) return;
    final page = doc.pages[_index];
    setState(() => _busy = true);
    try {
      final source = await File(
        filter == ScanFilter.original && rotation == 0 ? page.originalPath : page.path,
      ).readAsBytes();
      final bytes = await ImageProcessor.process(source,
          filter: filter, rotateDegrees: rotation);
      await widget.store.replacePageBytes(doc.id, page.id, bytes, filter: filter.label);
    } catch (error) {
      _message('Image processing failed: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _crop() async {
    final doc = _document;
    if (doc == null || _busy) return;
    final page = doc.pages[_index];
    final result = await Navigator.push<Uint8List>(context,
      MaterialPageRoute(builder: (_) => CropScreen(imagePath: page.path)));
    if (result == null) return;
    setState(() => _busy = true);
    try {
      await widget.store.replacePageBytes(doc.id, page.id, result, filter: page.filter);
    } catch (error) {
      _message(error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _ocr() async {
    final doc = _document;
    if (doc == null || doc.pages.isEmpty) return;
    await Navigator.push<void>(context, MaterialPageRoute(
      builder: (_) => EditTextScreen(
        store: widget.store,
        documentId: doc.id,
        pageId: doc.pages[_index].id,
      ),
    ));
  }

  Future<void> _pdfTools() async {
    final doc = _document;
    if (doc == null) return;
    await Navigator.push<void>(context, MaterialPageRoute(
      builder: (_) => PdfToolsScreen(
        store: widget.store,
        documentId: doc.id,
      ),
    ));
    if (mounted) setState(() => _index = 0);
    if (_pages.hasClients) _pages.jumpToPage(0);
  }

  Future<void> _addImages({required bool fromCamera}) async {
    final doc = _document;
    if (doc == null) return;
    final remaining = doc.kind.twoSided ? 2 - doc.pages.length : null;
    if (remaining != null && remaining <= 0) {
      _message('Front and back are already selected (maximum 2 images).');
      return;
    }
    List<String> paths = [];
    try {
      if (fromCamera) {
        paths = await Navigator.push<List<String>>(context, MaterialPageRoute(
          builder: (_) => CameraScreen(cardMode: doc.kind.twoSided),
        )) ?? [];
      } else if (remaining == 1) {
        final photo = await _picker.pickImage(source: ImageSource.gallery);
        if (photo != null) paths = [photo.path];
      } else {
        final picked = await _picker.pickMultiImage(
          limit: remaining,
          requestFullMetadata: false,
        );
        paths = picked.map((photo) => photo.path).toList();
      }
      if (paths.isEmpty) return;
      if (remaining != null && paths.length > remaining) {
        _message('Only $remaining more image(s) allowed.');
        return;
      }
      await widget.store.appendPaths(doc.id, paths);
      if (mounted) setState(() {});
    } catch (error) {
      _message(error);
    }
  }

  Future<void> _rename() async {
    final doc = _document;
    if (doc == null) return;
    final controller = TextEditingController(text: doc.name);
    final result = await showDialog<String>(context: context, builder: (dialogContext) => AlertDialog(
      title: const Text('Rename document'),
      content: TextField(controller: controller, autofocus: true),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(dialogContext, controller.text),
            child: const Text('Save')),
      ],
    ));
    if (result != null) await widget.store.renameDocument(doc.id, result);
    controller.dispose();
  }

  Future<void> _export(String type) async {
    final doc = _document;
    if (doc == null) return;
    setState(() => _busy = true);
    try {
      switch (type) {
        case 'pdf':
          await DocumentExport.sharePdf(doc);
        case 'image':
          await DocumentExport.shareImages(doc);
        case 'print':
          await DocumentExport.printPdf(doc);
      }
    } catch (error) {
      _message('Export failed: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _exportSheet() {
    showModalBottomSheet<void>(context: context, showDragHandle: true, builder: (sheetContext) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        ListTile(
          leading: const Icon(Icons.picture_as_pdf_outlined), title: const Text('Share as PDF'),
          onTap: () { Navigator.pop(sheetContext); _export('pdf'); },
        ),
        ListTile(
          leading: const Icon(Icons.image_outlined), title: const Text('Share as Images'),
          onTap: () { Navigator.pop(sheetContext); _export('image'); },
        ),
        ListTile(
          leading: const Icon(Icons.print_outlined), title: const Text('Print'),
          onTap: () { Navigator.pop(sheetContext); _export('print'); },
        ),
      ]),
    ));
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.store,
    builder: (_, _) {
      final doc = _document;
      if (doc == null) return Scaffold(appBar: AppBar(title: const Text('Document not found')));
      return Scaffold(
        appBar: AppBar(
          title: InkWell(onTap: _rename, child: Row(mainAxisSize: MainAxisSize.min, children: [
            Flexible(child: Text(doc.name, overflow: TextOverflow.ellipsis)),
            const SizedBox(width: 6), const Icon(Icons.edit_outlined, size: 16),
          ])),
          actions: [
            IconButton(onPressed: _exportSheet, icon: const Icon(Icons.ios_share_outlined), tooltip: 'Export'),
          ],
        ),
        body: SafeArea(child: Column(children: [
          if (_busy) const LinearProgressIndicator(color: dsTeal),
          Expanded(child: PageView.builder(
            controller: _pages,
            itemCount: doc.pages.length,
            onPageChanged: (page) => setState(() => _index = page),
            itemBuilder: (_, pageIndex) => Padding(
              padding: const EdgeInsets.all(12),
              child: Card(child: Padding(
                padding: const EdgeInsets.all(8),
                child: InteractiveViewer(
                  minScale: .8,
                  maxScale: 5,
                  child: Image.file(
                    File(doc.pages[pageIndex].path),
                    key: ValueKey(doc.pages[pageIndex].path),
                    width: double.infinity,
                    fit: BoxFit.contain,
                    errorBuilder: (_, _, _) => const Center(child: Icon(Icons.broken_image_outlined)),
                  ),
                ),
              )),
            ),
          )),
          Text('${_index + 1} / ${doc.pages.length}',
              style: const TextStyle(fontWeight: FontWeight.w600, color: dsMuted)),
          SizedBox(height: 60, child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            children: [
              for (final filter in ScanFilter.values)
                Padding(padding: const EdgeInsets.only(right: 7),
                    child: ChoiceChip(
                      label: Text(filter.label),
                      selected: doc.pages[_index].filter == filter.label,
                      onSelected: _busy ? null : (_) => _process(filter),
                    )),
            ],
          )),
          const Divider(height: 1),
          SizedBox(height: 83, child: Row(children: [
            _action(Icons.crop_rotate, 'Crop', _crop),
            _action(Icons.rotate_right, 'Rotate', () => _process(ScanFilter.original, rotation: 90)),
            _action(Icons.text_fields, 'Edit Text', _ocr),
            _action(Icons.add_photo_alternate_outlined, 'Add Page', () => _addImages(fromCamera: false)),
            _action(Icons.picture_as_pdf_outlined, 'PDF Tools', _pdfTools),
            _action(Icons.ios_share, 'Share', _exportSheet),
          ])),
        ])),
      );
    },
  );

  Widget _action(IconData icon, String label, VoidCallback callback) =>
      Expanded(child: InkWell(
        onTap: _busy ? null : callback,
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, color: dsTeal),
          const SizedBox(height: 5),
          Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
        ]),
      ));
}
