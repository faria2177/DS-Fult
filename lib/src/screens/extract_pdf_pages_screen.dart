import 'dart:io';

import 'package:flutter/material.dart';

import '../models.dart';
import '../storage/document_store.dart';
import '../theme.dart';
import 'document_detail_screen.dart';

/// Video 381564: select individual source pages before extracting them into
/// a separate, editable document. Source images are never removed or changed.
class ExtractPdfPagesScreen extends StatefulWidget {
  const ExtractPdfPagesScreen({
    super.key,
    required this.store,
    required this.documentId,
  });

  final DocumentStore store;
  final String documentId;

  @override
  State<ExtractPdfPagesScreen> createState() => _ExtractPdfPagesScreenState();
}

class _ExtractPdfPagesScreenState extends State<ExtractPdfPagesScreen> {
  final Set<int> _selected = {};
  bool _busy = false;
  String? _error;

  List<int> get _orderedSelection => _selected.toList()..sort();

  Future<void> _extract() async {
    final document = widget.store.byId(widget.documentId);
    if (_busy || document == null || _selected.isEmpty) return;
    final indices = _orderedSelection;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final extracted = await widget.store.duplicatePages(
        document.id, indices, '${document.name} - Extracted');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Done — pages extracted as a new document')));
      await Navigator.push<void>(context, MaterialPageRoute(
        builder: (_) => DocumentDetailScreen(
            store: widget.store, documentId: extracted.id),
      ));
    } catch (error) {
      if (mounted) setState(() => _error = 'Extraction failed: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _zoom(ScanPage page, int index) => showDialog<void>(
    context: context,
    builder: (dialog) => Dialog(child: Stack(children: [
      InteractiveViewer(minScale: .5, maxScale: 5,
        child: Image.file(File(page.path), fit: BoxFit.contain,
          errorBuilder: (_, _, _) => const Center(
            child: Text('Preview unavailable')))),
      Positioned(top: 4, right: 4,
        child: IconButton(tooltip: 'Close page ${index + 1} preview',
          onPressed: () => Navigator.pop(dialog),
          icon: const Icon(Icons.close))),
    ])),
  );

  Widget _pageTile(ScanPage page, int index) {
    final checked = _selected.contains(index);
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      color: checked ? dsTeal.withValues(alpha: .10) : null,
      child: InkWell(
        onTap: _busy ? null : () => setState(() {
          if (checked) { _selected.remove(index); }
          else { _selected.add(index); }
        }),
        child: Column(children: [
          Expanded(child: Stack(fit: StackFit.expand, children: [
            Padding(padding: const EdgeInsets.all(9),
              child: Image.file(File(page.path), fit: BoxFit.contain,
                cacheWidth: 260,
                errorBuilder: (_, _, _) =>
                    const Icon(Icons.broken_image_outlined))),
            Positioned(top: 4, left: 4, child: IgnorePointer(
              child: Checkbox(value: checked, activeColor: dsTeal,
                onChanged: (_) {}))),
            Positioned(top: 4, right: 4, child: IconButton(
              tooltip: 'Preview page ${index + 1}',
              onPressed: () => _zoom(page, index),
              icon: const Icon(Icons.zoom_in_outlined))),
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
    final document = widget.store.byId(widget.documentId);
    if (document == null) {
      return const Scaffold(body: Center(child: Text('Document not found')));
    }
    final allSelected = _selected.length == document.pages.length;
    return Scaffold(
      appBar: AppBar(title: const Text('Extract PDF Pages')),
      body: SafeArea(child: Column(children: [
        Padding(padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
          child: Row(children: [
            Expanded(child: Text(document.name, maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w700))),
            Text('${_selected.length}/${document.pages.length} selected',
              style: const TextStyle(fontSize: 12, color: dsMuted)),
          ])),
        Row(children: [
          const SizedBox(width: 16),
          const Expanded(child: Text('Choose pages to extract',
            style: TextStyle(fontSize: 13, color: dsMuted))),
          TextButton(onPressed: _busy ? null : () => setState(() {
            if (allSelected) { _selected.clear(); }
            else { _selected.addAll(List.generate(
                document.pages.length, (index) => index)); }
          }), child: Text(allSelected ? 'Deselect All' : 'Select All')),
          const SizedBox(width: 12),
        ]),
        if (_busy) const LinearProgressIndicator(color: dsTeal),
        Expanded(child: GridView.builder(
          padding: const EdgeInsets.all(14),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2, childAspectRatio: .72,
            mainAxisSpacing: 10, crossAxisSpacing: 10),
          itemCount: document.pages.length,
          itemBuilder: (_, index) => _pageTile(document.pages[index], index),
        )),
        if (_error != null)
          Padding(padding: const EdgeInsets.symmetric(
              horizontal: 16, vertical: 8),
            child: Text(_error!, style: TextStyle(
                color: Theme.of(context).colorScheme.error))),
        Padding(padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
          child: SizedBox(width: double.infinity,
            child: FilledButton.icon(
              key: const Key('extract-confirm'),
              onPressed: _selected.isEmpty || _busy ? null : _extract,
              icon: const Icon(Icons.file_copy_outlined),
              label: Text(_busy ? 'Extracting…'
                  : 'Extract as New Document (${_selected.length})'),
            ),
          ),
        ),
      ])),
    );
  }
}
