import 'dart:io';

import 'package:flutter/material.dart';

import '../services/document_export.dart';
import '../storage/document_store.dart';
import '../theme.dart';
import 'compress_screen.dart';
import 'extract_pdf_pages_screen.dart';

/// Organize and export the current image-backed document as a PDF.
class PdfToolsScreen extends StatefulWidget {
  const PdfToolsScreen({super.key, required this.store, required this.documentId});

  final DocumentStore store;
  final String documentId;

  @override
  State<PdfToolsScreen> createState() => _PdfToolsScreenState();
}

class _PdfToolsScreenState extends State<PdfToolsScreen> {
  bool _busy = false;

  Future<void> _extract() async {
    final doc = widget.store.byId(widget.documentId);
    if (doc == null || doc.pages.isEmpty) return;
    await Navigator.push<void>(context, MaterialPageRoute(
      builder: (_) => ExtractPdfPagesScreen(
          store: widget.store, documentId: doc.id),
    ));
  }

  Future<void> _watermark() async {
    final doc = widget.store.byId(widget.documentId);
    if (doc == null) return;
    final controller = TextEditingController(text: 'DocScanner');
    final text = await showDialog<String>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('PDF Watermark'),
        content: TextField(controller: controller,
            decoration: const InputDecoration(hintText: 'Text watermark')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialog),
              child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dialog, controller.text),
              child: const Text('Share PDF')),
        ],
      ),
    );
    controller.dispose();
    if (text == null) return;
    await _run(() => DocumentExport.shareCustomizedPdf(doc, watermark: text));
  }

  Future<void> _compress() async {
    final doc = widget.store.byId(widget.documentId);
    if (doc == null) return;
    await Navigator.push<void>(context, MaterialPageRoute(
      builder: (_) => CompressScreen(document: doc),
    ));
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('PDF operation failed: $error')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.store,
    builder: (context, _) {
      final doc = widget.store.byId(widget.documentId);
      if (doc == null) {
        return const Scaffold(body: Center(child: Text('Document not found')));
      }
      return Scaffold(
        appBar: AppBar(title: const Text('PDF Tools')),
        body: SafeArea(child: Column(children: [
          if (_busy) const LinearProgressIndicator(),
          const ListTile(
            title: Text('Reorder pages'),
            subtitle: Text('Long-press a page and drag to change its position.'),
            leading: Icon(Icons.swap_vert, color: dsTeal),
          ),
          Expanded(child: ReorderableListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            itemCount: doc.pages.length,
            itemBuilder: (_, index) => Card(
              key: ValueKey(doc.pages[index].id),
              child: ListTile(
                leading: Image.file(File(doc.pages[index].path),
                    width: 46, height: 55, fit: BoxFit.cover),
                title: Text('Page ${index + 1}'),
                trailing: const Icon(Icons.drag_handle),
              ),
            ),
            onReorderItem: _busy ? (_, _) {} : (oldIndex, newIndex) =>
                widget.store.reorderPages(widget.documentId, oldIndex, newIndex),
          )),
          const Divider(height: 1),
          Padding(padding: const EdgeInsets.all(12), child: Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(onPressed: _busy ? null : _extract,
                  icon: const Icon(Icons.file_copy_outlined),
                  label: const Text('Extract Pages')),
              OutlinedButton.icon(onPressed: _busy ? null : _compress,
                  icon: const Icon(Icons.compress),
                  label: const Text('Compress PDF')),
              FilledButton.icon(onPressed: _busy ? null : _watermark,
                  icon: const Icon(Icons.branding_watermark_outlined),
                  label: const Text('Watermark')),
            ],
          )),
        ])),
      );
    },
  );
}

/// Multi-select two or more documents, producing a new combined document.
class MergeDocumentsScreen extends StatefulWidget {
  const MergeDocumentsScreen({super.key, required this.store});
  final DocumentStore store;

  @override
  State<MergeDocumentsScreen> createState() => _MergeDocumentsScreenState();
}

class _MergeDocumentsScreenState extends State<MergeDocumentsScreen> {
  final Set<String> _selected = {};
  bool _busy = false;

  Future<void> _merge() async {
    setState(() => _busy = true);
    try {
      final merged = await widget.store.mergeDocuments(
        _selected.toList(),
        'Merged Document ${DateTime.now().millisecondsSinceEpoch}',
      );
      if (!mounted) return;
      Navigator.pop(context, merged.id);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('$error')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Merge Documents')),
    body: SafeArea(child: Column(children: [
      Expanded(child: ListView(children: [
        for (final doc in widget.store.documents.where((doc) =>
            doc.lockHash == null))
          CheckboxListTile(
            value: _selected.contains(doc.id),
            secondary: const Icon(Icons.picture_as_pdf_outlined),
            title: Text(doc.name),
            subtitle: Text('${doc.pages.length} page(s)'),
            onChanged: (selected) => setState(() {
              if (selected == true) {
                _selected.add(doc.id);
              } else {
                _selected.remove(doc.id);
              }
            }),
          ),
      ])),
      Padding(padding: const EdgeInsets.all(16), child: SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          onPressed: _selected.length < 2 || _busy ? null : _merge,
          icon: const Icon(Icons.merge_type),
          label: Text(_busy ? 'Merging…' : 'Merge ${_selected.length} Files'),
        ),
      )),
    ])),
  );
}
