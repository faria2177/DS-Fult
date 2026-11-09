import 'dart:io';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../models.dart';
import '../services/document_export.dart';
import '../services/pdf_image_export.dart';
import '../storage/document_store.dart';
import '../theme.dart';
import 'document_detail_screen.dart';

/// PDF or scanned-document pages are previewed and selected before export.
/// Existing page images are never overwritten by conversion.
class PdfToImagesScreen extends StatefulWidget {
  const PdfToImagesScreen({super.key, required this.document, required this.store});

  final ScanDocument document;
  final DocumentStore store;

  @override
  State<PdfToImagesScreen> createState() => _PdfToImagesScreenState();
}

class _PdfToImagesScreenState extends State<PdfToImagesScreen> {
  final Set<int> _selected = {};
  bool _png = false;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _selected.addAll(List.generate(widget.document.pages.length, (i) => i));
  }

  List<int> get _selection => _selected.toList()..sort();

  Future<void> _run(Future<void> Function(List<int>) action) async {
    if (_busy || _selected.isEmpty) return;
    final pages = _selection;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action(pages);
    } catch (error) {
      if (mounted) setState(() => _error = 'Image export failed: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _saveAsNew() => _run((pages) async {
    final images = await PdfImageExport.exportPages(widget.document, pages,
        png: _png);
    final created = await widget.store.createFromPaths(
        images.map((file) => file.path).toList(),
        name: '${widget.document.name} - Images');
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Done — images saved as a new document')));
    await Navigator.push<void>(context, MaterialPageRoute(
      builder: (_) => DocumentDetailScreen(
          store: widget.store, documentId: created.id),
    ));
  });

  Future<void> _share() => _run((pages) async {
    final images = await PdfImageExport.exportPages(widget.document, pages,
        png: _png);
    await SharePlus.instance.share(ShareParams(
      files: [for (final file in images)
        XFile(file.path, mimeType: _png ? 'image/png' : 'image/jpeg')],
      subject: '${widget.document.name} - Images',
    ));
  });

  Future<void> _gallery() => _run((pages) async {
    final images = await PdfImageExport.exportPages(widget.document, pages,
        png: _png);
    for (final file in images) {
      await DocumentExport.saveImageFileToGallery(file.path);
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Saved ${images.length} image(s) to Gallery')));
    }
  });

  Future<void> _inspectPage(int index) async {
    await showDialog<void>(context: context,
      builder: (dialog) => Dialog(child: Stack(children: [
        InteractiveViewer(
          minScale: .5,
          maxScale: 5,
          child: Image.file(File(widget.document.pages[index].path),
            fit: BoxFit.contain,
            errorBuilder: (_, _, _) =>
                const Center(child: Text('Preview unavailable')),
          ),
        ),
        Positioned(right: 4, top: 4,
          child: IconButton(tooltip: 'Close Preview',
            onPressed: () => Navigator.pop(dialog),
            icon: const Icon(Icons.close))),
      ])));
  }

  Widget _pageTile(int index) {
    final checked = _selected.contains(index);
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      color: checked ? dsTeal.withValues(alpha: .09) : null,
      child: InkWell(
        onTap: _busy ? null : () => setState(() {
          if (checked) { _selected.remove(index); }
          else { _selected.add(index); }
        }),
        child: Column(children: [
          Expanded(child: Stack(fit: StackFit.expand, children: [
            Padding(padding: const EdgeInsets.all(8),
              child: Image.file(File(widget.document.pages[index].path),
                fit: BoxFit.contain,
                errorBuilder: (_, _, _) =>
                    const Icon(Icons.broken_image_outlined))),
            Positioned(top: 5, left: 5,
              child: IgnorePointer(child: Checkbox(
                value: checked, activeColor: dsTeal, onChanged: (_) {}))),
            Positioned(top: 5, right: 5,
              child: IconButton(
                tooltip: 'Preview page ${index + 1}',
                icon: const Icon(Icons.zoom_in_outlined),
                onPressed: () => _inspectPage(index))),
          ])),
          Padding(padding: const EdgeInsets.only(bottom: 8),
            child: Text('Page ${index + 1}',
              style: const TextStyle(fontWeight: FontWeight.w600))),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final allSelected = _selected.length == widget.document.pages.length;
    final canExport = !_busy && _selected.isNotEmpty;
    return Scaffold(
      appBar: AppBar(title: const Text('PDF to Images')),
      body: SafeArea(child: Column(children: [
        Padding(padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Row(children: [
            Expanded(child: Text(widget.document.name,
                maxLines: 1, overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w700))),
            Text('${_selected.length}/${widget.document.pages.length} selected',
              style: const TextStyle(color: dsMuted, fontSize: 12)),
          ])),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(children: [
            const Expanded(child: Text('Tap to select • zoom to inspect',
                style: TextStyle(fontSize: 12, color: dsMuted))),
            TextButton(onPressed: _busy ? null : () => setState(() {
              if (allSelected) { _selected.clear(); }
              else { _selected.addAll(List.generate(
                  widget.document.pages.length, (index) => index)); }
            }), child: Text(allSelected ? 'Deselect All' : 'Select All')),
          ])),
        if (_busy) const LinearProgressIndicator(color: dsTeal),
        Expanded(child: GridView.builder(
          padding: const EdgeInsets.all(14),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2, childAspectRatio: .72,
            mainAxisSpacing: 10, crossAxisSpacing: 10),
          itemCount: widget.document.pages.length,
          itemBuilder: (_, i) => _pageTile(i),
        )),
        if (_error != null)
          Padding(padding: const EdgeInsets.symmetric(
              horizontal: 16, vertical: 8),
            child: Text(_error!, style: TextStyle(
                color: Theme.of(context).colorScheme.error))),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(children: [
            const Text('Export format:',
                style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(width: 12),
            ChoiceChip(label: const Text('JPG'), selected: !_png,
                onSelected: _busy ? null : (_) => setState(() => _png = false)),
            const SizedBox(width: 8),
            ChoiceChip(label: const Text('PNG'), selected: _png,
                onSelected: _busy ? null : (_) => setState(() => _png = true)),
          ])),
        Padding(padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Column(children: [
            Row(children: [
              Expanded(child: FilledButton.icon(
                onPressed: canExport ? _saveAsNew : null,
                icon: const Icon(Icons.save_alt_outlined),
                label: const Text('Save as New'))),
              const SizedBox(width: 8),
              Expanded(child: FilledButton.icon(
                onPressed: canExport ? _share : null,
                icon: const Icon(Icons.share_outlined),
                label: const Text('Share Images'))),
            ]),
            SizedBox(width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: canExport ? _gallery : null,
                icon: const Icon(Icons.photo_album_outlined),
                label: const Text('Save to Gallery'))),
          ])),
      ])),
    );
  }
}
