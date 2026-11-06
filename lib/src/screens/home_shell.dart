import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../models.dart';
import '../storage/document_store.dart';
import '../theme.dart';
import 'camera_screen.dart';
import 'document_screen.dart';
import 'id_card_screen.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({
    super.key,
    required this.store,
    required this.darkTheme,
    required this.onThemeChanged,
  });

  final DocumentStore store;
  final bool darkTheme;
  final ValueChanged<bool> onThemeChanged;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _tab = 0;
  String _query = '';
  final _picker = ImagePicker();

  void _message(String message) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _capture() async {
    final paths = await Navigator.push<List<String>>(context,
        MaterialPageRoute(builder: (_) => const CameraScreen()));
    if (paths == null || paths.isEmpty || !mounted) return;
    await _create(paths);
  }

  Future<void> _import() async {
    try {
      final files = await _picker.pickMultiImage(requestFullMetadata: false);
      if (files.isEmpty || !mounted) return;
      await _create(files.map((file) => file.path).toList());
    } catch (error) {
      _message('Could not import photos: $error');
    }
  }

  Future<void> _create(List<String> paths) async {
    try {
      final doc = await widget.store.createFromPaths(paths);
      if (!mounted) return;
      await _open(doc.id);
    } catch (error) {
      _message('Could not save document: $error');
    }
  }

  Future<void> _open(String id) async {
    await Navigator.push<void>(context, MaterialPageRoute(
      builder: (_) => DocumentScreen(store: widget.store, documentId: id),
    ));
  }

  Future<void> _openCard(DocumentKind kind) async {
    await Navigator.push<void>(context, MaterialPageRoute(
      builder: (_) => IdCardScreen(store: widget.store, kind: kind),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: AnimatedBuilder(
          animation: widget.store,
          builder: (_, _) => IndexedStack(
            index: _tab > 2 ? _tab - 1 : _tab,
            children: [
              _homeTab(),
              _filesTab(),
              _toolsTab(),
              _meTab(),
            ],
          ),
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        height: 72,
        indicatorColor: dsTeal.withValues(alpha: .12),
        onDestinationSelected: (index) {
          if (index == 2) {
            _capture();
          } else {
            setState(() => _tab = index);
          }
        },
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Home'),
          NavigationDestination(icon: Icon(Icons.folder_copy_outlined), label: 'Files'),
          NavigationDestination(icon: Icon(Icons.add_a_photo_outlined, color: dsTeal), label: 'Scan'),
          NavigationDestination(icon: Icon(Icons.grid_view_rounded), label: 'Tools'),
          NavigationDestination(icon: Icon(Icons.person_outline), label: 'Me'),
        ],
      ),
    );
  }

  Widget _homeTab() => ListView(
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 28),
        children: [
          Row(children: [
            const _DsMark(),
            const SizedBox(width: 10),
            const Text('DocScanner', style: TextStyle(fontSize: 23, fontWeight: FontWeight.w800)),
            const Spacer(),
            IconButton(onPressed: () => setState(() => _tab = 4), icon: const Icon(Icons.settings_outlined)),
          ]),
          const SizedBox(height: 24),
          TextField(
            onChanged: (value) => setState(() => _query = value.toLowerCase()),
            decoration: InputDecoration(
              hintText: 'Search documents',
              prefixIcon: const Icon(Icons.search),
              filled: true,
              fillColor: Theme.of(context).colorScheme.surface,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
            ),
          ),
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              gradient: const LinearGradient(colors: [Color(0xFF00BCA2), Color(0xFF007F75)]),
            ),
            child: Row(children: [
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Your documents,\nbeautifully scanned',
                    style: TextStyle(fontSize: 21, fontWeight: FontWeight.bold, color: Colors.white)),
                const SizedBox(height: 14),
                FilledButton.icon(
                  onPressed: _capture,
                  icon: const Icon(Icons.document_scanner_outlined),
                  label: const Text('Scan now'),
                  style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: const Color(0xFF007F75)),
                ),
              ])),
              const Icon(Icons.auto_awesome_rounded, size: 77, color: Color(0xBBFFFFFF)),
            ]),
          ),
          const SizedBox(height: 25),
          _sectionTitle('Quick actions'),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: _quick(Icons.photo_library_outlined, 'Import', _import)),
            Expanded(child: _quick(Icons.badge_outlined, 'ID Card', () => _openCard(DocumentKind.idCard))),
            Expanded(child: _quick(Icons.credit_card_outlined, 'Bank Card', () => _openCard(DocumentKind.bankCard))),
            Expanded(child: _quick(Icons.text_fields, 'OCR Text', () => _startOcr())),
          ]),
          const SizedBox(height: 24),
          Row(children: [
            Expanded(child: _sectionTitle('Recent documents')),
            TextButton(onPressed: () => setState(() => _tab = 1), child: const Text('View all')),
          ]),
          ..._filteredDocs.take(10).map(_documentTile),
          if (_filteredDocs.isEmpty) _emptyDocuments(),
        ],
      );

  List<ScanDocument> get _filteredDocs => widget.store.documents
      .where((doc) => doc.name.toLowerCase().contains(_query))
      .toList(growable: false);

  Widget _filesTab() => ListView(
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 20),
        children: [
          Row(children: [
            const Expanded(child: Text('Files', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold))),
            IconButton(onPressed: _createFolder, icon: const Icon(Icons.create_new_folder_outlined), tooltip: 'New folder'),
          ]),
          const SizedBox(height: 12),
          _sectionTitle('My folders'),
          const SizedBox(height: 8),
          for (final folder in widget.store.folders)
            Card(child: ListTile(
              leading: const Icon(Icons.folder_rounded, color: dsTeal, size: 32),
              title: Text(folder.name),
              subtitle: Text('${widget.store.documents.where((d) => d.folderId == folder.id).length} documents'),
              trailing: IconButton(icon: const Icon(Icons.more_vert), onPressed: () => _folderActions(folder)),
              onTap: () => _openFolder(folder),
            )),
          const SizedBox(height: 22),
          _sectionTitle('All documents'),
          ...widget.store.documents.map(_documentTile),
          if (widget.store.documents.isEmpty) _emptyDocuments(),
        ],
      );

  Widget _toolsTab() {
    final groups = <String, List<_Tool>>{
      'Scan': [
        _Tool('Scan', Icons.document_scanner_outlined, _capture),
        _Tool('ID Card', Icons.badge_outlined, () => _openCard(DocumentKind.idCard)),
        _Tool('Driver License', Icons.airport_shuttle_outlined, () => _openCard(DocumentKind.driverLicense)),
        _Tool('Bank Card', Icons.credit_card, () => _openCard(DocumentKind.bankCard)),
        _Tool('Import Images', Icons.photo_library_outlined, _import),
        _Tool('Extract Text', Icons.text_fields, _startOcr),
      ],
      'PDF & Export': [
        _Tool('To PDF', Icons.picture_as_pdf_outlined, _import),
        _Tool('Print', Icons.print_outlined, () => _openExisting('print')),
        _Tool('Sign', Icons.draw_outlined, () => _notReady('Sign')),
        _Tool('To Word', Icons.description_outlined, () => _notReady('To Word')),
        _Tool('To Excel', Icons.table_chart_outlined, () => _notReady('To Excel')),
        _Tool('To PPT', Icons.slideshow_outlined, () => _notReady('To PPT')),
      ],
      'Edit & Organize': [
        _Tool('Edit Text', Icons.edit_note_outlined, _startOcr),
        _Tool('Merge Files', Icons.merge_type, () => _notReady('Merge Files')),
        _Tool('Add Watermark', Icons.branding_watermark_outlined, () => _notReady('Add Watermark')),
        _Tool('Smart Erase', Icons.auto_fix_high_outlined, () => _notReady('Smart Erase')),
        _Tool('Compress PDF', Icons.compress, () => _notReady('Compress PDF')),
        _Tool('Reorder Pages', Icons.swap_vert, () => _notReady('Reorder Pages')),
        _Tool('Lock PDF', Icons.lock_outline, () => _notReady('Lock PDF')),
      ],
    };
    return ListView(padding: const EdgeInsets.fromLTRB(16, 18, 16, 25), children: [
      const Text('Tools', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 29)),
      const SizedBox(height: 15),
      for (final group in groups.entries) ...[
        Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: _sectionTitle(group.key)),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: group.value.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 4, mainAxisSpacing: 8, crossAxisSpacing: 8, childAspectRatio: .81,
          ),
          itemBuilder: (_, i) {
            final tool = group.value[i];
            return InkWell(
              onTap: tool.onTap,
              borderRadius: BorderRadius.circular(14),
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Container(
                  width: 49, height: 49,
                  decoration: BoxDecoration(color: dsTeal.withValues(alpha: .10), borderRadius: BorderRadius.circular(15)),
                  child: Icon(tool.icon, color: dsTeal, size: 26),
                ),
                const SizedBox(height: 7),
                Text(tool.title, textAlign: TextAlign.center, maxLines: 2,
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
              ]),
            );
          },
        ),
      ],
    ]);
  }

  Widget _meTab() => ListView(padding: const EdgeInsets.all(18), children: [
        const SizedBox(height: 15),
        const Center(child: _DsMark(big: true)),
        const SizedBox(height: 12),
        const Center(child: Text('DocScanner', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 24))),
        const Center(child: Text('Local-first document workspace')),
        const SizedBox(height: 25),
        Card(child: SwitchListTile(
          title: const Text('Dark theme'),
          secondary: const Icon(Icons.dark_mode_outlined),
          value: widget.darkTheme,
          onChanged: widget.onThemeChanged,
        )),
        const Card(child: ListTile(
          leading: Icon(Icons.shield_outlined, color: dsTeal),
          title: Text('Private, on-device storage'),
          subtitle: Text('No account, upload or cloud required'),
        )),
        const Card(child: ListTile(
          leading: Icon(Icons.info_outline),
          title: Text('About DocScanner'),
          subtitle: Text('Version 0.1.0 • Md Jahidul Islam'),
        )),
      ]);

  Widget _sectionTitle(String title) =>
      Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold));

  Widget _quick(IconData icon, String title, VoidCallback callback) =>
      InkWell(onTap: callback, borderRadius: BorderRadius.circular(15), child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Column(children: [
          CircleAvatar(radius: 26, backgroundColor: dsTeal.withValues(alpha: .13),
              child: Icon(icon, color: dsTeal)),
          const SizedBox(height: 7),
          Text(title, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
        ]),
      ));

  Widget _documentTile(ScanDocument doc) => Card(
        margin: const EdgeInsets.only(top: 9),
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          leading: ClipRRect(borderRadius: BorderRadius.circular(9), child:
              doc.pages.isNotEmpty
                  ? Image.file(File(doc.pages.first.path), width: 55, height: 68,
                      fit: BoxFit.cover, errorBuilder: (_, _, _) => const Icon(Icons.broken_image_outlined))
                  : const Icon(Icons.description_outlined)),
          title: Text(doc.name, maxLines: 1, overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text('${doc.pages.length} page(s) • ${doc.kind.label}'),
          trailing: PopupMenuButton<String>(
            onSelected: (value) => _documentAction(doc, value),
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'rename', child: Text('Rename')),
              PopupMenuItem(value: 'move', child: Text('Move to folder')),
              PopupMenuItem(value: 'delete', child: Text('Delete')),
            ],
          ),
          onTap: () => _open(doc.id),
        ),
      );

  Widget _emptyDocuments() => Padding(
        padding: const EdgeInsets.symmetric(vertical: 46),
        child: Column(children: [
          Icon(Icons.description_outlined, size: 58, color: dsMuted.withValues(alpha: .6)),
          const SizedBox(height: 10),
          const Text('No documents yet', style: TextStyle(color: dsMuted)),
          const SizedBox(height: 14),
          OutlinedButton.icon(onPressed: _import, icon: const Icon(Icons.add_photo_alternate_outlined),
              label: const Text('Import images')),
        ]),
      );

  Future<void> _startOcr() async {
    if (widget.store.documents.isEmpty) {
      _message('Scan or import a document first.');
      return;
    }
    await _open(widget.store.documents.first.id);
    if (mounted) _message('Tap Edit Text in the document toolbar.');
  }

  Future<void> _openExisting(String action) async {
    if (widget.store.documents.isEmpty) {
      _message('Import a document first.');
      return;
    }
    await _open(widget.store.documents.first.id);
  }

  void _notReady(String feature) => _message('$feature is planned; this tool is not yet implemented.');

  Future<void> _createFolder() async {
    final name = await _inputDialog('New folder', 'Folder name');
    if (name != null && name.trim().isNotEmpty) {
      await widget.store.createFolder(name);
    }
  }

  Future<String?> _inputDialog(String title, String hint, {String initial = ''}) {
    final controller = TextEditingController(text: initial);
    return showDialog<String>(context: context, builder: (dialogContext) => AlertDialog(
      title: Text(title),
      content: TextField(controller: controller, autofocus: true,
          decoration: InputDecoration(hintText: hint)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(dialogContext, controller.text), child: const Text('Save')),
      ],
    ));
  }

  Future<void> _documentAction(ScanDocument doc, String action) async {
    switch (action) {
      case 'rename':
        final name = await _inputDialog('Rename document', 'Name', initial: doc.name);
        if (name != null) await widget.store.renameDocument(doc.id, name);
      case 'move':
        final folder = await showModalBottomSheet<String>(context: context, builder: (context) => SafeArea(
          child: ListView(shrinkWrap: true, children: [
            ListTile(title: const Text('No folder'), onTap: () => Navigator.pop(context, 'root')),
            for (final folder in widget.store.folders)
              ListTile(leading: const Icon(Icons.folder), title: Text(folder.name),
                  onTap: () => Navigator.pop(context, folder.id)),
          ]),
        ));
        if (folder != null) await widget.store.moveDocument(doc.id, folder == 'root' ? null : folder);
      case 'delete':
        if (!mounted) return;
        final confirmed = await showDialog<bool>(context: context, builder: (context) => AlertDialog(
          title: const Text('Delete document?'),
          content: const Text('The document will be removed from your library.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
          ],
        ));
        if (confirmed == true) await widget.store.deleteDocument(doc.id);
    }
  }

  Future<void> _folderActions(DocumentFolder folder) async {
    final choice = await showModalBottomSheet<String>(context: context, builder: (context) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        ListTile(title: const Text('Rename folder'), onTap: () => Navigator.pop(context, 'rename')),
        ListTile(title: const Text('Remove folder'), onTap: () => Navigator.pop(context, 'delete')),
      ]),
    ));
    if (choice == 'rename') {
      final name = await _inputDialog('Rename folder', 'Name', initial: folder.name);
      if (name != null) await widget.store.renameFolder(folder.id, name);
    } else if (choice == 'delete') {
      await widget.store.deleteFolder(folder.id);
    }
  }

  Future<void> _openFolder(DocumentFolder folder) async {
    await Navigator.push<void>(context, MaterialPageRoute(builder: (_) => Scaffold(
      appBar: AppBar(title: Text(folder.name)),
      body: AnimatedBuilder(animation: widget.store, builder: (_, _) {
        final docs = widget.store.documents.where((doc) => doc.folderId == folder.id).toList();
        return docs.isEmpty
            ? const Center(child: Text('Folder is empty'))
            : ListView(padding: const EdgeInsets.all(14), children: docs.map(_documentTile).toList());
      }),
    )));
  }
}

class _Tool {
  const _Tool(this.title, this.icon, this.onTap);
  final String title;
  final IconData icon;
  final VoidCallback onTap;
}

class _DsMark extends StatelessWidget {
  const _DsMark({this.big = false});
  final bool big;

  @override
  Widget build(BuildContext context) => Container(
        width: big ? 82 : 39,
        height: big ? 82 : 39,
        decoration: BoxDecoration(
          color: dsTeal,
          borderRadius: BorderRadius.circular(big ? 24 : 12),
        ),
        alignment: Alignment.center,
        child: Text('DS', style: TextStyle(
          color: Colors.white, fontSize: big ? 30 : 15, fontWeight: FontWeight.w900)),
      );
}
