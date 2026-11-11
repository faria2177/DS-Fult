import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import '../models.dart';
import '../services/document_export.dart';
import '../services/id_card_page_composer.dart';
import '../services/docx_export.dart';
import '../services/image_processor.dart';
import '../services/image_tool_operations.dart';
import '../storage/document_store.dart';
import '../theme.dart';
import 'camera_screen.dart';
import 'batch_crop_screen.dart';
import 'crop_screen.dart';
import 'edit_text_screen.dart';
import 'gallery_import_review_screen.dart';
import 'image_text_editor_screen.dart';
import 'mosaic_screen.dart';
import 'pdf_tools_screen.dart';
import 'signature_screen.dart';
import 'watermark_screen.dart';

class DocumentScreen extends StatefulWidget {
  const DocumentScreen({super.key, required this.store, required this.documentId,
      this.initialPage = 0, this.initialPreview = false});
  final DocumentStore store;
  final String documentId;
  final int initialPage;
  final bool initialPreview;

  @override
  State<DocumentScreen> createState() => _DocumentScreenState();
}

class _DocumentScreenState extends State<DocumentScreen> {
  late final PageController _pages = PageController(initialPage: widget.initialPage);
  int _index = 0;
  bool _busy = false;
  bool _compare = false;
  int _editTab = 0;
  final _picker = ImagePicker();

  ScanDocument? get _document => widget.store.byId(widget.documentId);

  @override
  void initState() {
    super.initState();
    _index = widget.initialPage;
  }

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
        rotation != 0 ? page.path : page.originalPath,
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
    if (doc.pages.length > 1) {
      final edits = await Navigator.push<Map<int, Uint8List>>(context,
        MaterialPageRoute(builder: (_) => BatchCropScreen(
          imagePaths: doc.pages.map((page) => page.path).toList(),
          initialIndex: _index,
        )),
      );
      if (edits == null || edits.isEmpty || !mounted) return;
      setState(() => _busy = true);
      try {
        for (final entry in edits.entries) {
          if (entry.key < 0 || entry.key >= doc.pages.length) continue;
          final page = doc.pages[entry.key];
          await widget.store.replacePageBytes(doc.id, page.id, entry.value,
              filter: page.filter);
        }
      } catch (error) {
        _message('Batch crop failed: $error');
      } finally {
        if (mounted) setState(() => _busy = false);
      }
      return;
    }
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

  Future<void> _editOnImage({bool erase = false}) async {
    final doc = _document;
    if (doc == null || doc.pages.isEmpty) return;
    await Navigator.push<void>(context, MaterialPageRoute(
      builder: (_) => ImageTextEditorScreen(store: widget.store,
        documentId: doc.id, pageId: doc.pages[_index].id,
        regions: const [], startInEraseMode: erase),
    ));
  }

  Future<void> _sign() async {
    final doc = _document;
    if (doc == null || doc.pages.isEmpty) return;
    await Navigator.push<bool>(context, MaterialPageRoute(
      builder: (_) => SignatureScreen(store: widget.store,
          documentId: doc.id, pageId: doc.pages[_index].id),
    ));
  }

  Future<void> _brush() async {
    final doc = _document;
    if (doc == null || doc.pages.isEmpty) return;
    await Navigator.push<bool>(context, MaterialPageRoute(
      builder: (_) => SignatureScreen(store: widget.store,
          documentId: doc.id, pageId: doc.pages[_index].id,
          brushMode: true),
    ));
  }

  Future<void> _watermark() async {
    final doc = _document;
    if (doc == null || doc.pages.isEmpty) return;
    await Navigator.push<bool>(context, MaterialPageRoute(
      builder: (_) => WatermarkScreen(store: widget.store,
          documentId: doc.id, pageId: doc.pages[_index].id),
    ));
  }

  Future<void> _retake() async {
    final doc = _document;
    if (doc == null || _busy || doc.pages.isEmpty) return;
    final paths = await Navigator.push<List<String>>(context,
      MaterialPageRoute(builder: (_) => CameraScreen(cardMode: doc.kind.twoSided)),
    );
    if (paths == null || paths.isEmpty) return;
    setState(() => _busy = true);
    try {
      final bytes = doc.compositeCardPages
          ? await _composeExtraCard(paths)
          : await File(paths.first).readAsBytes();
      await widget.store.replacePageBytes(doc.id, doc.pages[_index].id, bytes,
          replaceOriginal: true);
    } catch (error) {
      _message(error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _renamePage() async {
    final doc = _document;
    if (doc == null || doc.pages.isEmpty) return;
    final page = doc.pages[_index];
    final controller = TextEditingController(text: page.title);
    final title = await showDialog<String>(context: context,
      builder: (dialog) => AlertDialog(title: const Text('Page Title'),
        content: TextField(controller: controller, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialog),
              child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dialog, controller.text),
              child: const Text('Save')),
        ],
      ),
    );
    controller.dispose();
    if (title != null) await widget.store.renamePage(doc.id, page.id, title);
  }

  Future<void> _deletePage() async {
    final doc = _document;
    if (doc == null || doc.pages.length < 2) {
      _message('Delete the document from More to remove its final page.');
      return;
    }
    final page = doc.pages[_index];
    await widget.store.removePages(doc.id, {page.id});
    if (mounted) {
      setState(() => _index = 0);
      if (_pages.hasClients) _pages.jumpToPage(0);
    }
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
    final remaining = doc.compositeCardPages ? 2
        : (doc.kind.twoSided ? 2 - doc.pages.length : null);
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
      if (!fromCamera) {
        if (!mounted) return;
        final review = await Navigator.of(context).push<GalleryImportResult>(
          MaterialPageRoute(builder: (_) => GalleryImportReviewScreen(
            imagePaths: paths,
            preferIdCardBounds: doc.kind.twoSided,
          )),
        );
        if (review == null || !mounted) return;
        paths = review.paths;
        // GalleryImportReviewScreen already offers a four-handle correction
        // route before these pages are appended to the document.
      }
      if (doc.compositeCardPages) {
        final combined = await _composeExtraCard(paths);
        final directory = await getTemporaryDirectory();
        final file = File('${directory.path}/ds_card_extra_'
            '${DateTime.now().microsecondsSinceEpoch}.jpg');
        await file.writeAsBytes(combined, flush: true);
        paths = [file.path];
      }
      await widget.store.appendPaths(doc.id, paths);
      if (mounted) setState(() {});
    } catch (error) {
      _message(error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<Uint8List> _composeExtraCard(List<String> paths) async {
    if (paths.length != 2) {
      throw StateError('Both Front and Back are required for one ID page.');
    }
    return IdCardPageComposer.compose([
      await File(paths[0]).readAsBytes(),
      await File(paths[1]).readAsBytes(),
    ]);
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
        case 'long':
          await ImageToolOperations.shareLongImage(doc);
        case 'word':
          final file = await DocxExport.createFile(doc);
          await DocxExport.shareFile(file, doc.name);
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
          leading: const Icon(Icons.description_outlined), title: const Text('Share as Word'),
          onTap: () { Navigator.pop(sheetContext); _export('word'); },
        ),
        ListTile(
          leading: const Icon(Icons.panorama_vertical_outlined),
          title: const Text('Share as Long Image'),
          onTap: () { Navigator.pop(sheetContext); _export('long'); },
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

  Widget _editorTool(IconData icon, String label, VoidCallback action) =>
      SizedBox(width: 77, child: InkWell(onTap: _busy ? null : action,
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, color: Colors.white, size: 24),
          const SizedBox(height: 5),
          Text(label, style: const TextStyle(color: Colors.white,
              fontSize: 11), maxLines: 2, textAlign: TextAlign.center),
        ]),
      ));

  Widget _filterBar(ScanDocument doc) => SizedBox(height: 86,
    child: ListView(scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      children: [
        for (final filter in _referenceFilters)
          Padding(padding: const EdgeInsets.only(right: 8),
            child: InkWell(onTap: _busy ? null : () => _process(filter),
              child: Container(width: 84, padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(7),
                  border: Border.all(color: doc.pages[_index].filter == filter.label
                      ? dsTeal : Colors.white12, width: 2),
                  color: const Color(0xFF343438),
                ),
                child: Column(children: [
                  Expanded(child: Image.file(File(doc.pages[_index].path),
                      cacheWidth: 190,
                      fit: BoxFit.cover, width: double.infinity)),
                  Text(_filterTitle(filter), maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white, fontSize: 10)),
                ]),
              ),
            ),
          ),
      ],
    ),
  );

  Widget _editorTools() {
    final tools = switch (_editTab) {
      0 => <Widget>[
        _editorTool(Icons.picture_as_pdf_outlined, 'DS PDF', _pdfTools),
        _editorTool(Icons.crop_rotate, 'Crop', _crop),
        _editorTool(Icons.tune, 'Filter', () => setState(() => _editTab = 3)),
        _editorTool(Icons.text_fields, 'Edit Text', _ocr),
        _editorTool(Icons.auto_fix_high, 'Smart Erase', () => _editOnImage(erase: true)),
        _editorTool(Icons.camera_alt_outlined, 'Retake', _retake),
        _editorTool(Icons.draw_outlined, 'Sign', _sign),
        _editorTool(Icons.title, 'Add Text', _editOnImage),
        _editorTool(Icons.brush_outlined, 'Brush', _brush),
        _editorTool(Icons.blur_on_outlined, 'Mosaic', _mosaic),
        _editorTool(Icons.branding_watermark_outlined, 'Add Watermark', _watermark),
      ],
      1 => <Widget>[
        _editorTool(Icons.grid_view_outlined, 'Collage', _shareCollage),
        _editorTool(Icons.title, 'Page Title', _renamePage),
      ],
      2 => <Widget>[
        _editorTool(Icons.swap_vert, 'Manage Pages', _pdfTools),
        _editorTool(Icons.rotate_left, 'Rotate Left', () =>
            _process(ScanFilter.original, rotation: -90)),
        _editorTool(Icons.rotate_right, 'Rotate Right', () =>
            _process(ScanFilter.original, rotation: 90)),
        _editorTool(Icons.add_photo_alternate_outlined, 'Add Page', () =>
            _addImages(fromCamera: false)),
        _editorTool(Icons.delete_outline, 'Delete Page', _deletePage),
      ],
      _ => <Widget>[],
    };
    return SizedBox(height: 79, child: ListView(scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 5), children: tools));
  }

  Future<void> _shareCollage() async {
    final doc = _document;
    if (doc == null) return;
    await ImageToolOperations.shareCollage(doc);
  }

  static const _referenceFilters = <ScanFilter>[
    // Keep the post-import editor in the same order as the supplied
    // CamScanner video: the automatic Enhance result is the first preset.
    ScanFilter.enhance,
    ScanFilter.magicColor,
    ScanFilter.noWatermark,
    ScanFilter.shadowFree,
    ScanFilter.noHandwriting,
    ScanFilter.blackWhite,
    ScanFilter.original,
    ScanFilter.lighten,
    ScanFilter.auto,
    ScanFilter.grayscale,
    ScanFilter.eco,
    ScanFilter.invert,
  ];

  String _filterTitle(ScanFilter filter) => switch (filter) {
    ScanFilter.magicColor => 'Magic Pro',
    ScanFilter.shadowFree => 'No Shadow',
    ScanFilter.noWatermark => 'No Watermark',
    ScanFilter.noHandwriting => 'No Handwriting',
    _ => filter.label,
  };

  Future<void> _mosaic() async {
    final doc = _document;
    if (doc == null || doc.pages.isEmpty) return;
    await Navigator.push<bool>(context, MaterialPageRoute(
      builder: (_) => MosaicScreen(store: widget.store,
        documentId: doc.id, pageId: doc.pages[_index].id),
    ));
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.store,
    builder: (_, _) {
      final doc = _document;
      if (doc == null || doc.pages.isEmpty) {
        return const Scaffold(body: Center(child: Text('Document not found')));
      }
      return Scaffold(
        backgroundColor: const Color(0xFF1B1B1D),
        appBar: AppBar(
          backgroundColor: const Color(0xFF2C2C2F),
          foregroundColor: Colors.white,
          title: widget.initialPreview
              ? InkWell(onTap: _rename,
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Flexible(child: Text(doc.name, overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 16))),
                    const SizedBox(width: 4), const Icon(Icons.edit, size: 16),
                  ]))
              : null,
          actions: widget.initialPreview
              ? [TextButton(onPressed: () => _addImages(fromCamera: false),
                  child: const Text('Add', style: TextStyle(color: dsTeal)))]
              : [
                  TextButton(onPressed: _exportSheet,
                      child: const Text('Share',
                          style: TextStyle(color: Colors.white))),
                  Padding(padding: const EdgeInsets.only(right: 8),
                    child: FilledButton(onPressed: () => Navigator.pop(context),
                      style: FilledButton.styleFrom(backgroundColor: dsTeal),
                      child: const Text('Done'))),
                ],
        ),
        body: SafeArea(child: Column(children: [
          if (_busy) const LinearProgressIndicator(color: dsTeal),
          Expanded(child: PageView.builder(
            controller: _pages,
            itemCount: doc.pages.length,
            onPageChanged: (page) => setState(() { _index = page; _compare = false; }),
            itemBuilder: (_, pageIndex) => Padding(
              padding: const EdgeInsets.all(15),
              child: InteractiveViewer(minScale: .8, maxScale: 5,
                child: Image.file(File(_compare
                    ? doc.pages[pageIndex].originalPath
                    : doc.pages[pageIndex].path),
                  fit: BoxFit.contain,
                  errorBuilder: (_, _, _) => const Center(child: Icon(
                      Icons.broken_image_outlined, color: Colors.white70)),
                ),
              ),
            ),
          )),
          if (widget.initialPreview) ...[
            Padding(padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Row(children: [
                const Spacer(),
                Text('${_index + 1} / ${doc.pages.length}',
                  style: const TextStyle(color: Colors.white)),
                const Spacer(),
                TextButton.icon(onPressed: () => setState(() => _compare = !_compare),
                  icon: const Icon(Icons.compare, color: Colors.white70, size: 16),
                  label: Text(_compare ? 'Processed' : 'Compare',
                    style: const TextStyle(color: Colors.white70))),
              ])),
            _filterBar(doc),
            Container(height: 75, color: const Color(0xFF2C2C2F),
              child: Row(children: [
                Expanded(child: _editorTool(Icons.camera_alt_outlined, 'Retake', _retake)),
                Expanded(child: _editorTool(Icons.rotate_left, 'Left', () =>
                    _process(ScanFilter.original, rotation: -90))),
                Expanded(child: _editorTool(Icons.crop_rotate, 'Crop', _crop)),
                Expanded(child: _editorTool(Icons.text_fields, 'Extract Text', _ocr)),
                Expanded(child: IconButton(onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.check_box, color: dsTeal, size: 37),
                  tooltip: 'Done')),
              ])),
          ] else ...[
            Container(color: const Color(0xFF2C2C2F),
              child: Row(children: [
                for (final entry in const ['Images', 'Markup', 'Page'].indexed)
                  TextButton(onPressed: () => setState(() => _editTab = entry.$1),
                    child: Text(entry.$2, style: TextStyle(
                      color: _editTab == entry.$1 ? dsTeal : Colors.white70))),
                if (_editTab == 3)
                  TextButton(onPressed: () => setState(() => _editTab = 0),
                      child: const Text('Back to Tools',
                          style: TextStyle(color: dsTeal))),
              ])),
            if (_editTab == 3) _filterBar(doc) else _editorTools(),
          ],
        ])),
      );
    },
  );
}
