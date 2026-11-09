import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:printing/printing.dart';

import '../models.dart';
import '../services/document_export.dart';
import '../services/pdf_file_delivery.dart';
import '../theme.dart';

typedef ImagePdfBuilder = Future<Uint8List> Function(ScanDocument document);
typedef ImagePdfSaver = Future<bool> Function(Uint8List bytes, String fileName);
typedef ImagePdfSharer = Future<void> Function(Uint8List bytes, String fileName);

/// Convert an existing/imported image collection into a real, multi-page PDF.
/// Selecting, reordering and previewing never modify the source document.
class ImageToPdfScreen extends StatefulWidget {
  const ImageToPdfScreen({
    super.key,
    required this.document,
    this.pdfBuilder,
    this.pdfSaver,
    this.pdfSharer,
  });

  final ScanDocument document;
  final ImagePdfBuilder? pdfBuilder;
  final ImagePdfSaver? pdfSaver;
  final ImagePdfSharer? pdfSharer;

  @override
  State<ImageToPdfScreen> createState() => _ImageToPdfScreenState();
}

class _ImageToPdfScreenState extends State<ImageToPdfScreen> {
  late final List<String> _order;
  late final Set<String> _selected;
  late final TextEditingController _filename;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _order = widget.document.pages.map((page) => page.id).toList();
    _selected = _order.toSet();
    _filename = TextEditingController(text: widget.document.name);
  }

  @override
  void dispose() {
    _filename.dispose();
    super.dispose();
  }

  ScanDocument get _exportDocument {
    final byId = {for (final page in widget.document.pages) page.id: page};
    return ScanDocument(
      id: widget.document.id,
      name: _filename.text.trim().isEmpty ? 'DocScanner' : _filename.text.trim(),
      createdAt: widget.document.createdAt,
      // All input pictures become separate PDF pages, including ID photos.
      pages: [for (final id in _order) if (_selected.contains(id)) byId[id]!],
    );
  }

  void _move(int from, int to) {
    if (_busy || from == to || from < 0 || to < 0 ||
        from >= _order.length || to >= _order.length) {
      return;
    }
    setState(() {
      final id = _order.removeAt(from);
      _order.insert(to, id);
    });
  }

  Future<void> _run(Future<void> Function(Uint8List, String) operation) async {
    if (_busy || _selected.isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final document = _exportDocument;
      final bytes = await (widget.pdfBuilder?.call(document) ??
          DocumentExport.toPdf(document));
      if (!mounted) return;
      await operation(bytes, PdfFileDelivery.filenameFor(document.name));
    } catch (error) {
      if (mounted) setState(() => _error = 'PDF creation failed: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() => _run((bytes, filename) async {
    final saved = await (widget.pdfSaver?.call(bytes, filename) ??
        PdfFileDelivery.saveToDevice(bytes, filename));
    if (saved && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('$filename saved to the selected folder'),
      ));
    }
  });

  Future<void> _share() => _run((bytes, filename) async {
    await (widget.pdfSharer?.call(bytes, filename) ??
        PdfFileDelivery.share(bytes, filename));
  });

  Future<void> _previewPdf() => _run((bytes, filename) async {
    await Navigator.push<void>(context, MaterialPageRoute(
      builder: (_) => Scaffold(
        appBar: AppBar(title: Text(filename)),
        body: SafeArea(child: PdfPreview(
          build: (_) async => bytes,
          allowPrinting: false,
          allowSharing: false,
          canChangeOrientation: false,
          canChangePageFormat: false,
          canDebug: false,
        )),
      ),
    ));
  });

  Future<void> _zoom(ScanPage page, int index) => showDialog<void>(
    context: context,
    builder: (dialog) => Dialog(child: Stack(children: [
      InteractiveViewer(minScale: .5, maxScale: 5,
        child: Image.file(File(page.path), fit: BoxFit.contain,
          errorBuilder: (_, _, _) => const Center(
            child: Text('Preview unavailable')))),
      Positioned(top: 4, right: 4, child: IconButton(
        tooltip: 'Close page ${index + 1} preview',
        onPressed: () => Navigator.pop(dialog),
        icon: const Icon(Icons.close))),
    ])),
  );

  Widget _pageTile(ScanPage page, int index) {
    final included = _selected.contains(page.id);
    return Card(
      key: ValueKey(page.id),
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      color: included ? dsTeal.withValues(alpha: .08) : null,
      child: Padding(padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(children: [
          Checkbox(
            key: Key('image-pdf-include-${page.id}'),
            activeColor: dsTeal,
            value: included,
            onChanged: _busy ? null : (checked) => setState(() {
              if (checked == true) { _selected.add(page.id); }
              else { _selected.remove(page.id); }
            }),
          ),
          SizedBox(width: 56, height: 71, child: InkWell(
            onTap: () => _zoom(page, index),
            child: Image.file(File(page.path), fit: BoxFit.contain,
              cacheWidth: 240,
              errorBuilder: (_, _, _) => const Icon(
                Icons.broken_image_outlined)),
          )),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Page ${index + 1}',
                style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 5),
              Text(included ? 'Included in PDF' : 'Not included',
                style: const TextStyle(fontSize: 12, color: dsMuted)),
            ],
          )),
          Column(mainAxisSize: MainAxisSize.min, children: [
            IconButton(
              tooltip: 'Move page ${index + 1} up',
              onPressed: _busy || index == 0 ? null : () => _move(index, index - 1),
              icon: const Icon(Icons.keyboard_arrow_up),
              constraints: const BoxConstraints(minHeight: 36, minWidth: 36)),
            IconButton(
              tooltip: 'Move page ${index + 1} down',
              onPressed: _busy || index == _order.length - 1
                  ? null : () => _move(index, index + 1),
              icon: const Icon(Icons.keyboard_arrow_down),
              constraints: const BoxConstraints(minHeight: 36, minWidth: 36)),
          ]),
          ReorderableDragStartListener(index: index,
            child: const Padding(padding: EdgeInsets.all(12),
              child: Icon(Icons.drag_handle, color: dsMuted))),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final byId = {for (final page in widget.document.pages) page.id: page};
    final allSelected = _selected.length == _order.length;
    final canExport = !_busy && _selected.isNotEmpty;
    return Scaffold(
      appBar: AppBar(title: const Text('Image to PDF')),
      body: SafeArea(child: Column(children: [
        Padding(padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Row(children: [
            const Expanded(child: Text('Select and arrange pages',
              style: TextStyle(fontWeight: FontWeight.w600))),
            Text('${_selected.length}/${_order.length} selected',
              style: const TextStyle(fontSize: 12, color: dsMuted)),
          ]),
        ),
        Row(children: [
          const SizedBox(width: 16),
          const Expanded(child: Text('Drag or use arrows to reorder',
            style: TextStyle(fontSize: 12, color: dsMuted))),
          TextButton(onPressed: _busy ? null : () => setState(() {
            if (allSelected) { _selected.clear(); }
            else { _selected.addAll(_order); }
          }), child: Text(allSelected ? 'Deselect All' : 'Select All')),
          const SizedBox(width: 8),
        ]),
        if (_busy) const LinearProgressIndicator(color: dsTeal),
        Expanded(child: ReorderableListView.builder(
          buildDefaultDragHandles: false,
          padding: const EdgeInsets.only(bottom: 6),
          itemCount: _order.length,
          onReorderItem: _busy ? (_, _) {} : _move,
          itemBuilder: (_, index) => _pageTile(byId[_order[index]]!, index),
        )),
        if (_error != null) Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
          child: Text(_error!, style: TextStyle(
            color: Theme.of(context).colorScheme.error)),
        ),
        Padding(padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Column(children: [
            TextField(
              controller: _filename,
              enabled: !_busy,
              maxLength: 80,
              decoration: const InputDecoration(
                isDense: true,
                labelText: 'PDF file name',
                border: OutlineInputBorder(),
                counterText: '',
              ),
            ),
            const SizedBox(height: 9),
            SizedBox(width: double.infinity,
              child: OutlinedButton.icon(
                key: const Key('image-pdf-preview'),
                onPressed: canExport ? _previewPdf : null,
                icon: const Icon(Icons.preview_outlined),
                label: const Text('Preview PDF')),
            ),
            Row(children: [
              Expanded(child: FilledButton.icon(
                key: const Key('image-pdf-save'),
                onPressed: canExport ? _save : null,
                icon: const Icon(Icons.save_alt_outlined),
                label: Text(_busy ? 'Creating…' : 'Save PDF'))),
              const SizedBox(width: 8),
              Expanded(child: OutlinedButton.icon(
                key: const Key('image-pdf-share'),
                onPressed: canExport ? _share : null,
                icon: const Icon(Icons.share_outlined),
                label: const Text('Share PDF'))),
            ]),
          ]),
        ),
      ])),
    );
  }
}
