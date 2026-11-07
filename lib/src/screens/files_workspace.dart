import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../models.dart';
import '../services/document_export.dart';
import '../services/docx_export.dart';
import '../services/image_tool_operations.dart';
import '../storage/document_store.dart';
import '../theme.dart';
import 'files_merge_screen.dart';

/// Files library and its video-reference multi-document action flow.
/// Every action uses the on-device DocumentStore, never a hosted API.
class FilesWorkspace extends StatefulWidget {
  const FilesWorkspace({super.key, required this.store, required this.onOpen,
      required this.onImport, required this.onScan,
      required this.onSelectionChanged});

  final DocumentStore store;
  final Future<void> Function(String) onOpen;
  final VoidCallback onImport;
  final VoidCallback onScan;
  final ValueChanged<bool> onSelectionChanged;

  @override
  State<FilesWorkspace> createState() => _FilesWorkspaceState();
}

class _FilesWorkspaceState extends State<FilesWorkspace> {
  static const _platform = MethodChannel('doclens/methods');
  final Set<String> _selected = {};
  bool _selecting = false;
  bool _busy = false;
  bool _grid = false;
  String _folderId = 'all';
  String _sort = 'Newest first';
  String _search = '';

  bool get _dark => Theme.of(context).brightness == Brightness.dark;
  Color get _accent => dsTeal;
  Color get _panel => _dark ? const Color(0xFF29292C) : Colors.white;

  List<ScanDocument> get _visible {
    final docs = widget.store.documents.where((d) {
      final inFolder = _folderId == 'all' ||
          (_folderId == 'root' ? d.folderId == null : d.folderId == _folderId);
      return inFolder && (d.name.toLowerCase().contains(_search.toLowerCase()) ||
          d.tags.any((t) => t.toLowerCase().contains(_search.toLowerCase())));
    }).toList();
    switch (_sort) {
      case 'Oldest first':
        docs.sort((a, b) => a.createdAt.compareTo(b.createdAt));
      case 'Name A–Z':
        docs.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      case 'Name Z–A':
        docs.sort((a, b) => b.name.toLowerCase().compareTo(a.name.toLowerCase()));
      case 'Most pages':
        docs.sort((a, b) => b.pages.length.compareTo(a.pages.length));
      default:
        docs.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    }
    return docs;
  }

  List<ScanDocument> get _chosen => _visible
      .where((doc) => _selected.contains(doc.id)).toList(growable: false);

  void _setSelecting(bool value) {
    setState(() {
      _selecting = value;
      if (!value) _selected.clear();
    });
    widget.onSelectionChanged(value);
  }

  void _toggle(String id) {
    if (!_selecting) _setSelecting(true);
    setState(() {
      if (!_selected.add(id)) _selected.remove(id);
    });
  }

  void _selectAll() => setState(() {
    final ids = _visible.map((d) => d.id).toSet();
    if (_selected.containsAll(ids)) {
      _selected.removeAll(ids);
    } else {
      _selected.addAll(ids);
    }
  });

  void _notice(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _run(Future<void> Function() action, {bool clear = false}) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      if (clear && mounted) _setSelecting(false);
    } catch (error) {
      _notice('Operation failed: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  bool _requireUnlocked() {
    if (_selected.isEmpty) return false;
    if (_chosen.any((doc) => doc.lockHash != null)) {
      _notice('Open locked documents and enter their PIN before using these actions.');
      return false;
    }
    return true;
  }

  Future<String?> _input(String title, {String initial = '',
      String hint = '', bool secret = false}) async {
    final controller = TextEditingController(text: initial);
    final value = await showDialog<String>(context: context,
        builder: (dialog) => AlertDialog(
          title: Text(title),
          content: TextField(controller: controller, autofocus: true,
              obscureText: secret, decoration: InputDecoration(hintText: hint)),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialog),
                child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(dialog, controller.text),
                child: const Text('OK')),
          ],
        ));
    controller.dispose();
    return value;
  }

  Future<String?> _menu(String title, List<({String key, String label,
      IconData icon})> entries) => showModalBottomSheet<String>(
    context: context, showDragHandle: true,
    builder: (sheet) => SafeArea(child: Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          Padding(padding: const EdgeInsets.all(12), child: Text(title,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600))),
          const Spacer(),
          IconButton(onPressed: () => Navigator.pop(sheet),
              icon: const Icon(Icons.close)),
        ]),
        for (final e in entries)
          ListTile(leading: Icon(e.icon), title: Text(e.label),
              onTap: () => Navigator.pop(sheet, e.key)),
      ]),
    )),
  );

  Future<void> _createFolder() async {
    final name = await _input('New folder', hint: 'Folder name');
    if (name == null || name.trim().isEmpty) return;
    await _run(() => widget.store.createFolder(name));
  }

  Future<void> _renameFolder(DocumentFolder folder) async {
    final choice = await _menu(folder.name, [
      (key: 'rename', label: 'Rename folder', icon: Icons.edit_outlined),
      (key: 'delete', label: 'Remove folder', icon: Icons.delete_outline),
    ]);
    if (!mounted || choice == null) return;
    if (choice == 'rename') {
      final name = await _input('Rename folder', initial: folder.name);
      if (name != null && name.trim().isNotEmpty) {
        await _run(() => widget.store.renameFolder(folder.id, name));
      }
    } else {
      final ok = await _confirm('Remove folder?',
          'The documents will remain in All files.');
      if (ok) {
        await _run(() => widget.store.deleteFolder(folder.id));
        if (mounted && _folderId == folder.id) setState(() => _folderId = 'all');
      }
    }
  }

  Future<bool> _confirm(String title, String message) async =>
      await showDialog<bool>(context: context, builder: (dialog) => AlertDialog(
        title: Text(title), content: Text(message),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialog, false),
              child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dialog, true),
              child: const Text('Confirm')),
        ],
      )) ?? false;

  Future<void> _rename() async {
    if (_chosen.length != 1 || !_requireUnlocked()) return;
    final doc = _chosen.single;
    final value = await _input('Title', initial: doc.name, hint: 'Document title');
    if (value == null || value.trim().isEmpty) return;
    await _run(() => widget.store.renameDocument(doc.id, value), clear: true);
  }

  Future<void> _delete() async {
    if (!_requireUnlocked()) return;
    final ids = _chosen.map((e) => e.id).toList(growable: false);
    final confirmed = await _confirm('Delete ${ids.length} document(s)?',
        'The selected files will be removed from Files. Original image data '
        'is retained for recovery, but there is no in-app Trash yet.');
    if (!confirmed) {
      return;
    }
    await _run(() async {
      for (final id in ids) {
        await widget.store.deleteDocument(id);
      }
    }, clear: true);
  }

  Future<String?> _pickFolder() => _menu('Choose destination', [
    (key: 'root', label: 'All files (no folder)', icon: Icons.home_outlined),
    for (final folder in widget.store.folders)
      (key: folder.id, label: folder.name, icon: Icons.folder_outlined),
    (key: 'new', label: 'Create new folder', icon: Icons.create_new_folder_outlined),
  ]);

  Future<void> _moveCopy() async {
    if (!_requireUnlocked()) return;
    final docs = List<ScanDocument>.from(_chosen);
    final choice = await _menu('Move/Copy', [
      (key: 'move', label: 'Move', icon: Icons.drive_file_move_outline),
      (key: 'copy', label: 'Copy', icon: Icons.copy_all_outlined),
    ]);
    if (choice == null || !mounted) return;
    var destination = await _pickFolder();
    if (!mounted || destination == null) return;
    if (destination == 'new') {
      final name = await _input('New folder', hint: 'Folder name');
      if (name == null || name.trim().isEmpty) return;
      DocumentFolder? created;
      await _run(() async { created = await widget.store.createFolder(name); });
      destination = created?.id;
      if (destination == null) return;
    }
    final folderId = destination == 'root' ? null : destination;
    await _run(() async {
      for (final doc in docs) {
        if (choice == 'move') {
          await widget.store.moveDocument(doc.id, folderId);
        } else {
          await widget.store.copyDocument(doc.id, folderId: folderId);
        }
      }
      _notice('${docs.length} document(s) ${choice == 'move' ? 'moved' : 'copied'}.');
    }, clear: true);
  }

  Future<void> _merge() async {
    if (_chosen.length < 2 || !_requireUnlocked()) return;
    final id = await Navigator.push<String>(context, MaterialPageRoute(
      builder: (_) => FilesMergeScreen(store: widget.store,
          initialIds: _chosen.map((d) => d.id).toList()),
    ));
    if (!mounted || id == null) return;
    _setSelecting(false);
    await widget.onOpen(id);
  }

  Future<void> _shareWord(ScanDocument doc) async {
    final language = await _menu('Word OCR language', [
      (key: 'en', label: 'English / Latin', icon: Icons.language),
      (key: 'bn', label: 'বাংলা / Bengali', icon: Icons.translate),
    ]);
    if (language == null) return;
    await _run(() async {
      final file = await DocxExport.createFile(doc, bengali: language == 'bn');
      await DocxExport.shareFile(file, doc.name);
    });
  }

  Future<void> _share() async {
    if (!_requireUnlocked()) return;
    final docs = List<ScanDocument>.from(_chosen);
    final single = docs.length == 1;
    final choice = await _menu('Share', [
      (key: 'pdf', label: single ? 'Share as PDF' : 'Share ${docs.length} PDFs',
          icon: Icons.picture_as_pdf_outlined),
      if (single) (key: 'word', label: 'Share as Word', icon: Icons.description_outlined),
      if (single) (key: 'long', label: 'Share as Long Image', icon: Icons.panorama_vertical_outlined),
      (key: 'images', label: 'Share as Images', icon: Icons.image_outlined),
      (key: 'gallery', label: 'Save to Gallery', icon: Icons.save_alt_outlined),
      (key: 'link', label: 'Share as Link', icon: Icons.link_outlined),
    ]);
    if (!mounted || choice == null) return;
    if (choice == 'word') { await _shareWord(docs.single); return; }
    if (choice == 'link') {
      await showDialog<void>(context: context, builder: (dialog) => AlertDialog(
        title: const Text('Share as Link'),
        content: const Text('DocScanner stores documents only on this device. '
            'Creating a public download link would require uploading the document. '
            'Use Share as PDF or Images to send files directly instead.'),
        actions: [TextButton(onPressed: () => Navigator.pop(dialog),
            child: const Text('OK'))],
      ));
      return;
    }
    await _run(() async {
      switch (choice) {
        case 'pdf':
          final files = <XFile>[];
          for (final doc in docs) {
            files.add(XFile((await DocumentExport.savePdf(doc)).path,
                mimeType: 'application/pdf'));
          }
          await SharePlus.instance.share(ShareParams(
              files: files, subject: single ? docs.first.name : 'DocScanner documents'));
        case 'long':
          await ImageToolOperations.shareLongImage(docs.single);
        case 'images':
          await SharePlus.instance.share(ShareParams(
            files: [for (final doc in docs)
              for (final page in doc.pages) XFile(page.path)],
            subject: single ? docs.first.name : 'DocScanner images',
          ));
        case 'gallery':
          var count = 0;
          for (final doc in docs) {
            count += await DocumentExport.saveImagesToGallery(doc);
          }
          _notice('$count page(s) saved to Gallery.');
      }
    });
  }

  Future<void> _tags() async {
    if (!_requireUnlocked()) return;
    final docs = List<ScanDocument>.from(_chosen);
    final value = await _input('Tags', hint: 'Comma-separated tags',
        initial: docs.length == 1 ? docs.single.tags.join(', ') : '');
    if (value == null) return;
    final tags = value.split(',').map((s) => s.trim())
        .where((s) => s.isNotEmpty).toSet().toList();
    await _run(() async {
      for (final doc in docs) {
        await widget.store.setTags(doc.id, tags);
      }
    });
  }

  Future<void> _lock() async {
    if (!_requireUnlocked()) return;
    final docs = List<ScanDocument>.from(_chosen);
    final pin = await _input('Lock ${docs.length} document(s)',
        hint: 'PIN (6 or more characters)', secret: true);
    if (pin == null) return;
    if (pin.length < 6) { _notice('PIN must have at least 6 characters.'); return; }
    await _run(() async {
      for (final doc in docs) {
        final hash = sha256.convert(utf8.encode('${doc.id}:$pin'));
        await widget.store.setLockHash(doc.id, hash.toString());
      }
      _notice('App-level PIN set. Exported files are not encrypted.');
    }, clear: true);
  }

  Future<void> _pinShortcut(ScanDocument doc) async {
    await _run(() async {
      final supported = await _platform.invokeMethod<bool>('pinDocumentShortcut',
          {'documentId': doc.id, 'title': doc.name});
      if (supported != true) {
        _notice('This launcher does not support pinned shortcuts.');
      } else {
        _notice('Confirm the document shortcut on your Home screen.');
      }
    });
  }

  Future<void> _more() async {
    if (!_requireUnlocked()) return;
    final docs = List<ScanDocument>.from(_chosen);
    final single = docs.length == 1;
    final choice = await _menu('More', [
      if (single) ...[
        (key: 'send', label: 'Send to PC', icon: Icons.computer_outlined),
        (key: 'print', label: 'Print', icon: Icons.print_outlined),
        (key: 'images', label: 'PDF to Images', icon: Icons.collections_outlined),
        (key: 'home', label: 'Add to Home Screen', icon: Icons.add_to_home_screen),
      ],
      (key: 'tags', label: 'Tags', icon: Icons.local_offer_outlined),
      (key: 'lock', label: 'Lock', icon: Icons.lock_outline),
    ]);
    if (choice == null || !mounted) return;
    switch (choice) {
      case 'send':
        await _run(() => DocumentExport.sharePdf(docs.single));
      case 'print':
        await _run(() => DocumentExport.printPdf(docs.single));
      case 'images':
        await _run(() => DocumentExport.shareImages(docs.single));
      case 'home':
        await _pinShortcut(docs.single);
      case 'tags':
        await _tags();
      case 'lock':
        await _lock();
    }
  }

  Future<void> _chooseFolder() async {
    final selected = await _menu('All files and folders', [
      (key: 'all', label: 'All (${widget.store.documents.length})',
          icon: Icons.article_outlined),
      (key: 'root', label: 'No folder', icon: Icons.folder_open_outlined),
      for (final folder in widget.store.folders)
        (key: folder.id, label: folder.name, icon: Icons.folder_rounded),
    ]);
    if (selected == null) return;
    _setSelecting(false);
    setState(() => _folderId = selected);
  }

  Future<void> _sortFiles() async {
    final selected = await _menu('Sort documents', [
      for (final sort in ['Newest first', 'Oldest first', 'Name A–Z',
          'Name Z–A', 'Most pages'])
        (key: sort, label: sort, icon: Icons.sort),
    ]);
    if (selected != null) setState(() => _sort = selected);
  }

  String _folderLabel() {
    if (_folderId == 'all') return 'All (${widget.store.documents.length})';
    if (_folderId == 'root') return 'No folder';
    for (final folder in widget.store.folders) {
      if (folder.id == _folderId) return folder.name;
    }
    return 'All';
  }

  String _date(ScanDocument doc) {
    final d = doc.createdAt.toLocal();
    String p(int n) => n.toString().padLeft(2, '0');
    return '${p(d.day)}/${p(d.month)}/${d.year} ${p(d.hour)}:${p(d.minute)}';
  }

  Widget _fileTile(ScanDocument doc, {bool grid = false}) {
    final checked = _selected.contains(doc.id);
    final thumb = doc.pages.isEmpty
        ? const Icon(Icons.description_outlined, size: 32)
        : Image.file(File(doc.pages.first.path),
            width: grid ? double.infinity : 48, height: grid ? 120 : 57,
            cacheWidth: 240, fit: BoxFit.cover,
            errorBuilder: (_, _, _) => const Icon(Icons.broken_image_outlined));
    final highlighted = checked ? _accent.withValues(alpha: .18) : Colors.transparent;
    if (grid) {
      return InkWell(
        onLongPress: () => _toggle(doc.id),
        onTap: () => _selecting ? _toggle(doc.id) : widget.onOpen(doc.id),
        child: Card(color: checked ? highlighted : _panel,
          child: Padding(padding: const EdgeInsets.all(8), child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: Stack(fit: StackFit.expand, children: [
                thumb,
                if (_selecting) Positioned(top: 2, right: 2,
                  child: Icon(checked ? Icons.check_box : Icons.check_box_outline_blank,
                    color: checked ? _accent : null)),
              ])),
              const SizedBox(height: 7),
              Text(doc.name, maxLines: 1, overflow: TextOverflow.ellipsis),
              Text('${doc.pages.length} pages • ${_date(doc)}', maxLines: 1,
                style: const TextStyle(color: dsMuted, fontSize: 10)),
            ])),
        ),
      );
    }
    return Material(color: highlighted, child: InkWell(
      onLongPress: () => _toggle(doc.id),
      onTap: () => _selecting ? _toggle(doc.id) : widget.onOpen(doc.id),
      child: Padding(padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
        child: Row(children: [
          ClipRRect(borderRadius: BorderRadius.circular(4), child: SizedBox(
              width: 48, height: 57, child: thumb)),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(doc.name, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
              const SizedBox(height: 4),
              Text('${_date(doc)}   ▫ ${doc.pages.length}',
                  style: const TextStyle(color: dsMuted, fontSize: 11)),
              if (doc.lockHash != null) const Text('Locked',
                  style: TextStyle(color: dsMuted, fontSize: 10)),
            ])),
          if (_selecting)
            Icon(checked ? Icons.check_box : Icons.check_box_outline_blank,
                size: 20, color: checked ? _accent : dsMuted)
          else
            IconButton(icon: const Icon(Icons.more_vert, size: 20),
                onPressed: () { _setSelecting(true); _toggle(doc.id); }),
        ])),
    ));
  }

  Widget _action(IconData icon, String label, VoidCallback onTap,
      {bool enabled = true}) => Expanded(child: InkWell(
    onTap: enabled && !_busy ? onTap : null,
    child: Padding(padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 23, color: enabled ? null : dsMuted),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(fontSize: 10),
            overflow: TextOverflow.ellipsis),
      ])),
  ));

  @override
  Widget build(BuildContext context) {
    final docs = _visible;
    final chosen = _chosen.length;
    return Column(children: [
      if (_busy) const LinearProgressIndicator(minHeight: 2),
      Padding(padding: const EdgeInsets.fromLTRB(12, 10, 8, 4),
        child: _selecting
          ? Row(children: [
              IconButton(onPressed: () => _setSelecting(false),
                  icon: const Icon(Icons.close)),
              Expanded(child: Text('$chosen selected',
                  style: const TextStyle(fontWeight: FontWeight.w600))),
              TextButton(onPressed: _selectAll,
                  child: Text(chosen == docs.length && docs.isNotEmpty
                      ? 'Deselect All' : 'Select All')),
            ])
          : Row(children: [
              const Expanded(child: Text('Files',
                  style: TextStyle(fontSize: 25, fontWeight: FontWeight.bold))),
              IconButton(icon: const Icon(Icons.create_new_folder_outlined),
                  tooltip: 'New folder', onPressed: _createFolder),
              IconButton(icon: const Icon(Icons.search), tooltip: 'Search',
                  onPressed: () async {
                    final value = await _input('Search files', initial: _search);
                    if (value != null) setState(() => _search = value.trim());
                  }),
              IconButton(icon: const Icon(Icons.checklist_rounded),
                  tooltip: 'Select files', onPressed: () => _setSelecting(true)),
            ]),
      ),
      if (!_selecting) Padding(
        padding: const EdgeInsets.fromLTRB(14, 4, 10, 7),
        child: Row(children: [
          InkWell(onTap: _chooseFolder, child: Row(children: [
            Text(_folderLabel(), style: const TextStyle(fontWeight: FontWeight.w500)),
            const Icon(Icons.arrow_drop_down),
          ])),
          const Spacer(),
          IconButton(onPressed: _sortFiles, tooltip: 'Sort',
              icon: const Icon(Icons.sort, size: 21)),
          IconButton(onPressed: () => setState(() => _grid = !_grid),
              tooltip: _grid ? 'List view' : 'Grid view',
              icon: Icon(_grid ? Icons.view_list : Icons.grid_view, size: 21)),
          IconButton(onPressed: () => _setSelecting(true),
              tooltip: 'Select', icon: const Icon(Icons.check_box_outlined, size: 21)),
        ]),
      ),
      if (_search.isNotEmpty) Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: InputChip(label: Text('Search: $_search'),
            onDeleted: () => setState(() => _search = '')),
      ),
      Expanded(child: docs.isEmpty
        ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.folder_open_outlined, size: 60, color: dsMuted),
            const SizedBox(height: 12),
            const Text('No documents here'),
            TextButton.icon(onPressed: widget.onImport,
                icon: const Icon(Icons.add_photo_alternate_outlined),
                label: const Text('Import images')),
          ]))
        : _grid
          ? GridView.builder(padding: const EdgeInsets.all(8), itemCount: docs.length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3, childAspectRatio: .73,
                crossAxisSpacing: 4, mainAxisSpacing: 5),
              itemBuilder: (_, i) => _fileTile(docs[i], grid: true))
          : ListView.builder(itemCount: docs.length,
              itemBuilder: (_, i) => _fileTile(docs[i]))),
      if (!_selecting && widget.store.folders.isNotEmpty && _folderId == 'all')
        SizedBox(height: 56, child: ListView(scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12), children: [
            for (final folder in widget.store.folders)
              Padding(padding: const EdgeInsets.only(right: 8),
                child: InputChip(avatar: const Icon(Icons.folder_outlined, size: 18),
                  label: Text(folder.name),
                  onPressed: () => setState(() => _folderId = folder.id),
                  onDeleted: () => _renameFolder(folder),
                  deleteIcon: const Icon(Icons.more_vert, size: 18))),
          ])),
      if (_selecting) SafeArea(top: false, child: Container(
        color: _panel, child: Row(children: [
          _action(Icons.share_outlined, 'Share', _share, enabled: chosen > 0),
          _action(Icons.drive_file_move_outline, 'Move/Copy', _moveCopy, enabled: chosen > 0),
          _action(Icons.merge_type, 'Merge', _merge, enabled: chosen > 1),
          if (chosen == 1)
            _action(Icons.edit_outlined, 'Rename', _rename)
          else
            _action(Icons.delete_outline, 'Delete', _delete, enabled: chosen > 0),
          if (chosen == 1)
            _action(Icons.delete_outline, 'Delete', _delete),
          _action(Icons.more_vert, 'More', _more, enabled: chosen > 0),
        ]))),
      if (!_selecting && docs.isEmpty)
        Padding(padding: const EdgeInsets.only(bottom: 12),
          child: FilledButton.icon(onPressed: widget.onScan,
              icon: const Icon(Icons.camera_alt_outlined), label: const Text('Scan'))),
    ]);
  }
}
