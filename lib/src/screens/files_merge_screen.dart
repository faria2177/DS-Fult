import 'dart:io';

import 'package:flutter/material.dart';

import '../models.dart';
import '../storage/document_store.dart';
import '../theme.dart';

/// Reorder and preview selected documents before a non-destructive merge.
class FilesMergeScreen extends StatefulWidget {
  const FilesMergeScreen({super.key, required this.store, required this.initialIds});

  final DocumentStore store;
  final List<String> initialIds;

  @override
  State<FilesMergeScreen> createState() => _FilesMergeScreenState();
}

class _FilesMergeScreenState extends State<FilesMergeScreen> {
  late final List<String> _ids;
  bool _keepOriginals = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _ids = [...widget.initialIds];
  }

  List<ScanDocument> get _documents => [
    for (final id in _ids)
      if (widget.store.byId(id) case final ScanDocument doc) doc,
  ];

  List<ScanPage> get _pages => [
    for (final doc in _documents) ...doc.pages,
  ];

  Future<void> _addFile() async {
    final chosen = <String>{..._ids};
    final options = widget.store.documents.where((d) => d.lockHash == null).toList();
    final result = await showDialog<List<String>>(context: context,
      builder: (dialog) => StatefulBuilder(builder: (dialog, refresh) => AlertDialog(
        title: const Text('Select Document'),
        content: SizedBox(width: 360, height: 360, child: ListView(
          children: [for (final doc in options)
            CheckboxListTile(value: chosen.contains(doc.id),
              title: Text(doc.name, maxLines: 2),
              subtitle: Text('${doc.pages.length} page(s)'),
              onChanged: (yes) => refresh(() {
                if (yes == true) { chosen.add(doc.id); }
                else { chosen.remove(doc.id); }
              }),
            )],
        )),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialog),
              child: const Text('Cancel')),
          FilledButton(onPressed: chosen.length < 2 ? null :
              () => Navigator.pop(dialog, chosen.toList()),
              child: const Text('Done')),
        ],
      )),
    );
    if (result != null) {
      setState(() {
        _ids..clear()..addAll(result);
      });
    }
  }

  Future<String?> _save() async {
    if (_ids.length < 2 || _busy) return null;
    final nameController = TextEditingController(text:
        'Merged Document ${DateTime.now().year}-${DateTime.now().month}-${DateTime.now().day}');
    final name = await showDialog<String>(context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Save merged document'),
        content: TextField(controller: nameController,
            decoration: const InputDecoration(labelText: 'Document title')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialog),
              child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dialog, nameController.text),
              child: const Text('Save')),
        ],
      ),
    );
    nameController.dispose();
    if (name == null || name.trim().isEmpty || !mounted) return null;
    setState(() => _busy = true);
    try {
      final merged = await widget.store.mergeDocuments(_ids, name.trim(),
          keepOriginals: _keepOriginals);
      return merged.id;
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Merge failed: $error')));
      }
      return null;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _preview() async {
    final pages = _pages;
    final id = await Navigator.push<String>(context, MaterialPageRoute(
      builder: (previewContext) => Scaffold(
        appBar: AppBar(title: const Text('Merge Preview')),
        body: Column(children: [
          Expanded(child: PageView.builder(itemCount: pages.length,
            itemBuilder: (_, index) => Stack(children: [
              Center(child: Image.file(File(pages[index].path),
                  fit: BoxFit.contain,
                  errorBuilder: (_, _, _) => const Icon(Icons.broken_image_outlined))),
              Positioned(left: 8, top: 10, child: Chip(
                  label: Text('${index + 1}/${pages.length}'))),
            ]))),
          SafeArea(top: false, child: Padding(padding: const EdgeInsets.all(12),
            child: SizedBox(width: double.infinity,
              child: FilledButton(onPressed: () async {
                final result = await _save();
                if (result != null && previewContext.mounted) {
                  Navigator.pop(previewContext, result);
                }
              }, child: const Text('Save')),
            ))),
        ]),
      ),
    ));
    if (id != null && mounted) Navigator.pop(context, id);
  }

  @override
  Widget build(BuildContext context) {
    final docs = _documents;
    return Scaffold(
      appBar: AppBar(title: const Text('Merge Documents'), actions: [
        IconButton(onPressed: docs.length < 2 || _busy ? null : _preview,
            tooltip: 'Preview merged pages', icon: const Icon(Icons.preview_outlined)),
      ]),
      body: SafeArea(child: Column(children: [
        if (_busy) const LinearProgressIndicator(),
        const ListTile(dense: true, leading: Icon(Icons.info_outline, size: 18),
          title: Text('Press and drag to sort. Pages follow this order.'),
          titleTextStyle: TextStyle(fontSize: 12, color: dsMuted)),
        Expanded(child: ReorderableListView.builder(
          itemCount: docs.length,
          buildDefaultDragHandles: false,
          onReorderItem: (oldIndex, newIndex) {
            setState(() {
              _ids.insert(newIndex, _ids.removeAt(oldIndex));
            });
          },
          itemBuilder: (_, index) {
            final doc = docs[index];
            return Card(key: ValueKey(doc.id), margin: const EdgeInsets.fromLTRB(8, 3, 8, 3),
              child: ListTile(
                leading: doc.pages.isEmpty
                  ? const Icon(Icons.description_outlined)
                  : Image.file(File(doc.pages.first.path), width: 45, height: 52,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => const Icon(Icons.broken_image_outlined)),
                title: Text(doc.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text('${doc.pages.length} page(s)'),
                trailing: ReorderableDragStartListener(index: index,
                  child: const Padding(padding: EdgeInsets.all(8),
                      child: Icon(Icons.drag_handle))),
              ),
            );
          },
        )),
        CheckboxListTile(dense: true, value: _keepOriginals,
            title: const Text('Keep originals'),
            onChanged: _busy ? null : (yes) => setState(() => _keepOriginals = yes ?? true)),
        Padding(padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          child: Row(children: [
            Expanded(child: OutlinedButton(onPressed: _busy ? null : _addFile,
              child: const Text('Add File'))),
            const SizedBox(width: 10),
            Expanded(child: FilledButton(onPressed: docs.length < 2 || _busy ? null : () async {
              final id = await _save();
              if (id != null && context.mounted) {
                Navigator.pop(context, id);
              }
            }, child: Text(_busy ? 'Merging…' : 'Merge Documents'))),
          ]),
        ),
      ])),
    );
  }
}
