import 'dart:io';

import 'package:flutter/material.dart';

import '../models.dart';
import '../services/document_export.dart';
import '../storage/document_store.dart';
import 'compress_screen.dart';
import 'extract_pdf_pages_screen.dart';
import 'rotate_pages_screen.dart';
import 'document_detail_screen.dart';
import 'document_screen.dart';
import 'reorder_pages_screen.dart';
import 'signature_screen.dart';
import 'video_tool_style.dart';
import 'watermark_screen.dart';

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
  int _activePageIndex = 0;

  ScanPage? get _activePage {
    final pages = widget.store.byId(widget.documentId)?.pages;
    if (pages == null || pages.isEmpty) return null;
    return pages[_activePageIndex.clamp(0, pages.length - 1).toInt()];
  }

  Future<void> _editPage() async {
    if (_activePage == null || !mounted) return;
    await Navigator.push<void>(context, MaterialPageRoute(
      builder: (_) => DocumentScreen(store: widget.store,
        documentId: widget.documentId,
        initialPage: _activePageIndex,
        initialPreview: true),
    ));
  }

  Future<void> _signPage() async {
    final page = _activePage;
    if (page == null || !mounted) return;
    await Navigator.push<bool>(context, MaterialPageRoute(
      builder: (_) => SignatureScreen(store: widget.store,
        documentId: widget.documentId, pageId: page.id),
    ));
  }

  Future<void> _watermarkPage() async {
    final page = _activePage;
    if (page == null || !mounted) return;
    await Navigator.push<bool>(context, MaterialPageRoute(
      builder: (_) => WatermarkScreen(store: widget.store,
        documentId: widget.documentId, pageId: page.id),
    ));
  }

  Future<void> _reorder() async {
    await Navigator.push<bool>(context, MaterialPageRoute(
      builder: (_) => ReorderPagesScreen(store: widget.store,
        documentId: widget.documentId),
    ));
    if (mounted) setState(() => _activePageIndex = 0);
  }

  Future<void> _extract() async {
    final doc = widget.store.byId(widget.documentId);
    if (doc == null || doc.pages.isEmpty) return;
    await Navigator.push<void>(context, MaterialPageRoute(
      builder: (_) => ExtractPdfPagesScreen(
          store: widget.store, documentId: doc.id),
    ));
  }

  Future<void> _rotate() async {
    final doc = widget.store.byId(widget.documentId);
    if (doc == null || doc.pages.isEmpty) return;
    final saved = await Navigator.push<bool>(context, MaterialPageRoute(
      builder: (_) => RotatePagesScreen(
        store: widget.store, documentId: doc.id,
      ),
    ));
    if (saved == true && mounted) setState(() {});
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

  Future<void> _openDocument() async {
    await Navigator.push<void>(context, MaterialPageRoute(
      builder: (_) => DocumentDetailScreen(store: widget.store,
        documentId: widget.documentId),
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

  Widget _action(IconData icon, String name, String hint,
      Future<void> Function() action, Color tint) => InkWell(
    onTap: _busy ? null : action,
    borderRadius: BorderRadius.circular(16),
    child: Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: VideoToolStyle.tile,
        borderRadius: BorderRadius.circular(16)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center, children: [
        CircleAvatar(backgroundColor: tint.withValues(alpha: .15),
          child: Icon(icon, color: tint, size: 23)),
        const SizedBox(height: 8),
        Text(name, maxLines: 1, overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 13,
              fontWeight: FontWeight.w700)),
        const SizedBox(height: 3),
        Text(hint, maxLines: 2, overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: VideoToolStyle.muted,
              fontSize: 11)),
      ]),
    ),
  );

  @override
  Widget build(BuildContext context) => Theme(
    data: VideoToolStyle.dark,
    child: AnimatedBuilder(animation: widget.store, builder: (context, _) {
      final doc = widget.store.byId(widget.documentId);
      if (doc == null) {
        return const Scaffold(body: Center(child: Text('Document not found')));
      }
      return Scaffold(
        appBar: AppBar(title: const Text('Edit PDF'), actions: [
          IconButton(tooltip: 'Share PDF',
            onPressed: _busy ? null : () => _run(() =>
                DocumentExport.sharePdf(doc)),
            icon: const Icon(Icons.ios_share)),
        ]),
        body: SafeArea(child: Column(children: [
          if (_busy) const LinearProgressIndicator(
              color: VideoToolStyle.teal),
          Expanded(child: ListView(padding: const EdgeInsets.only(bottom: 20),
            children: [
              Container(color: VideoToolStyle.header,
                padding: const EdgeInsets.fromLTRB(18, 18, 18, 22),
                child: Row(children: [
                  Container(width: 64, height: 64,
                    decoration: BoxDecoration(color: VideoToolStyle.teal
                        .withValues(alpha: .14),
                      borderRadius: BorderRadius.circular(18)),
                    child: const Icon(Icons.picture_as_pdf_outlined,
                      size: 33, color: VideoToolStyle.teal)),
                  const SizedBox(width: 14),
                  Expanded(child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(doc.name, maxLines: 2,
                      style: const TextStyle(fontSize: 19,
                        fontWeight: FontWeight.w700)),
                    const SizedBox(height: 5),
                    Text('${doc.pages.length} page(s) · On-device editing',
                      style: const TextStyle(color: VideoToolStyle.muted,
                        fontSize: 12)),
                  ])),
                ]),
              ),
              const Padding(padding: EdgeInsets.fromLTRB(18, 22, 18, 12),
                child: Text('Choose a page', style: TextStyle(
                  fontSize: 17, fontWeight: FontWeight.w700))),
              SizedBox(height: 157, child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 18),
                itemCount: doc.pages.length,
                separatorBuilder: (_, _) => const SizedBox(width: 12),
                itemBuilder: (context, index) {
                  final page = doc.pages[index];
                  final selected = index == _activePageIndex;
                  return InkWell(
                    key: Key('pdf-page-${page.id}'),
                    onTap: () => setState(() => _activePageIndex = index),
                    child: Container(width: 108, padding: const EdgeInsets.all(5),
                      decoration: BoxDecoration(color: VideoToolStyle.tile,
                        borderRadius: BorderRadius.circular(13),
                        border: Border.all(color: selected
                            ? VideoToolStyle.teal : Colors.transparent,
                            width: 2)),
                      child: Column(children: [
                        Expanded(child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.file(File(page.path),
                            fit: BoxFit.cover, width: double.infinity,
                            errorBuilder: (_, _, _) => const Icon(
                              Icons.broken_image_outlined, size: 34)))),
                        const SizedBox(height: 5),
                        Text('Page ${index + 1}',
                          style: const TextStyle(fontSize: 12)),
                      ]),
                    ),
                  );
                },
              )),
              const Padding(padding: EdgeInsets.fromLTRB(18, 24, 18, 13),
                child: Text('Edit & annotate', style: TextStyle(
                  fontSize: 17, fontWeight: FontWeight.w700))),
              Padding(padding: const EdgeInsets.symmetric(horizontal: 18),
                child: GridView.count(shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisCount: 2, mainAxisExtent: 132,
                  mainAxisSpacing: 10, crossAxisSpacing: 10,
                  children: [
                    _action(Icons.edit_outlined, 'Edit Page',
                      'Crop, filters, text & more', _editPage,
                      VideoToolStyle.teal),
                    _action(Icons.draw_outlined, 'Sign',
                      'Draw a signature', _signPage,
                      const Color(0xFFEEB75F)),
                    _action(Icons.branding_watermark_outlined, 'Watermark',
                      'Add text to selected page', _watermarkPage,
                      const Color(0xFF8DABFF)),
                    _action(Icons.rotate_right, 'Rotate Pages',
                      'Rotate one or more pages', _rotate,
                      const Color(0xFFCD9BFE)),
                  ],
                )),
              const Padding(padding: EdgeInsets.fromLTRB(18, 23, 18, 13),
                child: Text('Organize & export', style: TextStyle(
                  fontSize: 17, fontWeight: FontWeight.w700))),
              Padding(padding: const EdgeInsets.symmetric(horizontal: 18),
                child: GridView.count(shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisCount: 2, mainAxisExtent: 132,
                  mainAxisSpacing: 10, crossAxisSpacing: 10,
                  children: [
                    _action(Icons.swap_vert, 'Reorder',
                      'Change page sequence', _reorder,
                      const Color(0xFF72D6C2)),
                    _action(Icons.file_copy_outlined, 'Extract Pages',
                      'Create a separate document', _extract,
                      const Color(0xFFEDA2A6)),
                    _action(Icons.compress, 'Compress PDF',
                      'Reduce output size', _compress,
                      const Color(0xFFF1BB67)),
                    _action(Icons.print_outlined, 'Print',
                      'Print the PDF pages', () => _run(() =>
                          DocumentExport.printPdf(doc)),
                      const Color(0xFF9CA3FF)),
                    _action(Icons.ios_share, 'Share PDF',
                      'Send a PDF copy', () => _run(() =>
                          DocumentExport.sharePdf(doc)),
                      VideoToolStyle.teal),
                    _action(Icons.text_format, 'Share with Stamp',
                      'Export with text watermark', _watermark,
                      const Color(0xFF8DABFF)),
                  ],
                )),
              const Padding(padding: EdgeInsets.fromLTRB(18, 18, 18, 0),
                child: Text('Imported PDFs are image-backed. Editing does '
                    'not preserve the original vector text layer.',
                  style: TextStyle(color: VideoToolStyle.muted,
                    fontSize: 12))),
            ],
          )),
          Container(color: VideoToolStyle.header,
            padding: const EdgeInsets.fromLTRB(18, 10, 18, 14),
            child: SafeArea(top: false, child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _busy ? null : _openDocument,
                style: VideoToolStyle.tealButton,
                icon: const Icon(Icons.visibility_outlined),
                label: const Text('View Document'),
              ),
            )),
          ),
        ])),
      );
    }),
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
