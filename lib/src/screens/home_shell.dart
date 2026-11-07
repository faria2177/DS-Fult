import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../models.dart';
import '../services/document_edges.dart';
import '../services/document_export.dart';
import '../services/docx_export.dart';
import '../services/image_tool_operations.dart';
import '../services/scan_settings_store.dart';
import '../services/xlsx_export.dart';
import '../storage/document_store.dart';
import '../theme.dart';
import 'camera_screen.dart';
import 'document_detail_screen.dart';
import 'files_workspace.dart';
import 'id_card_screen.dart';
import 'id_card_template_screen.dart';
import 'image_text_editor_screen.dart';
import 'pdf_tools_screen.dart';
import 'qr_code_screen.dart';
import 'scan_more_settings_screen.dart';
import 'signature_screen.dart';
import 'text_to_pdf_screen.dart';

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
  static const _doclensChannel = MethodChannel('doclens/methods');
  int _tab = 0;
  String _query = '';
  String _toolQuery = '';
  bool _filesSelecting = false;
  final _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _doclensChannel.setMethodCallHandler((call) async {
      if (call.method == 'openPinnedDocument' && mounted &&
          call.arguments is String) {
        final id = call.arguments as String;
        if (widget.store.byId(id) != null) await _open(id);
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        final pinnedId = await _doclensChannel.invokeMethod<String>(
            'consumeLaunchDocumentShortcut');
        if (pinnedId != null && widget.store.byId(pinnedId) != null && mounted) {
          await _open(pinnedId);
          return;
        }
      } catch (_) {
        // The shortcut bridge is optional on non-Android platforms.
      }
      final settings = await ScanSettingsStore.load();
      final startCamera = settings.startWithCamera;
      settings.dispose();
      if (startCamera && mounted) await _capture();
    });
  }

  @override
  void dispose() {
    _doclensChannel.setMethodCallHandler(null);
    super.dispose();
  }

  void _message(String message) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _capture() async {
    final paths = await Navigator.push<List<String>>(context,
        MaterialPageRoute(builder: (_) => CameraScreen(
          onOpenIdCards: (scannerContext, template) =>
              Navigator.of(scannerContext).push<void>(
            MaterialPageRoute(builder: (_) => IdCardScreen(
              store: widget.store,
              kind: template.documentKind,
              template: template,
              openCameraInitially: true,
            )),
          ),
        )));
    if (paths == null || paths.isEmpty || !mounted) return;
    await _create(paths);
  }

  Future<void> _import() async {
    try {
      final files = await _picker.pickMultiImage(requestFullMetadata: false);
      if (files.isEmpty || !mounted) return;
      final autoCrop = await DocumentEdges.autoCropFiles(
        files.map((file) => file.path).toList(),
      );
      if (!mounted) return;
      if (autoCrop.needsReview > 0) {
        _message('${autoCrop.needsReview} photo(s) had no reliable edges. '
            'Use Crop to adjust them manually.');
      }
      await _create(autoCrop.paths);
    } catch (error) {
      _message('Could not import photos: $error');
    }
  }

  Future<void> _create(List<String> paths) async {
    try {
      final doc = await widget.store.createFromPaths(paths);
      if (!mounted) return;
      await _open(doc.id, openEditorFirst: true);
    } catch (error) {
      _message('Could not save document: $error');
    }
  }

  Future<void> _open(String id, {bool openEditorFirst = false}) async {
    await Navigator.push<void>(context, MaterialPageRoute(
      builder: (_) => DocumentDetailScreen(store: widget.store,
          documentId: id, openEditorFirst: openEditorFirst),
    ));
  }

  Future<void> _openCard(DocumentKind kind) async {
    await Navigator.push<void>(context, MaterialPageRoute(
      builder: (_) => kind == DocumentKind.idCard
          ? IdCardTemplateScreen(store: widget.store)
          : IdCardScreen(store: widget.store, kind: kind),
    ));
  }

  Future<void> _openScanSettings() async {
    final settings = await ScanSettingsStore.load();
    if (!mounted) {
      settings.dispose();
      return;
    }
    void persist() => unawaited(ScanSettingsStore.save(settings));
    settings.addListener(persist);
    try {
      await Navigator.push<void>(context, MaterialPageRoute(
        builder: (_) => ScanMoreSettingsScreen(settings: settings),
      ));
      // Flush the final state before returning to Me. The camera loads these
      // same persisted values the next time it is opened.
      await ScanSettingsStore.save(settings);
    } finally {
      settings.removeListener(persist);
      settings.dispose();
    }
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
      bottomNavigationBar: _tab == 1 && _filesSelecting ? null : NavigationBar(
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

  Widget _filesTab() => FilesWorkspace(
        store: widget.store,
        onOpen: (id) => _open(id),
        onImport: () => _import(),
        onScan: () => _capture(),
        onSelectionChanged: (selected) {
          if (mounted && _filesSelecting != selected) {
            setState(() => _filesSelecting = selected);
          }
        },
      );

  Widget _toolsTab() {
    final groups = <String, List<_Tool>>{
      'Scan': [
        _Tool('Scan', Icons.document_scanner_outlined, _capture),
        _Tool('ID Cards', Icons.badge_outlined, () => _openCard(DocumentKind.idCard)),
        _Tool('Import Images', Icons.photo_library_outlined, _import),
        _Tool('Import File', Icons.upload_file_outlined, () => _notReady('Import File')),
        _Tool('Extract Text', Icons.text_fields, _startOcr),
        _Tool('Passport Photo Maker', Icons.portrait_outlined,
            () => _notReady('Passport Photo Maker')),
      ],
      'Convert': [
        _Tool('Merge PDF', Icons.merge_type, _mergeDocuments),
        _Tool('Image to PDF', Icons.picture_as_pdf_outlined, _import),
        _Tool('Text to PDF', Icons.text_snippet_outlined, _textToPdf),
        _Tool('To Word', Icons.description_outlined, _exportWord),
        _Tool('To Excel', Icons.table_chart_outlined, _exportExcel),
        _Tool('PDF to Images', Icons.collections_outlined, _shareDocumentImages),
        _Tool('PDF to Long Image', Icons.panorama_vertical_outlined, _shareLongImage),
      ],
      'Edit': [
        _Tool('Edit PDF', Icons.edit_document, () => _openExisting('pdf')),
        _Tool('Edit Text', Icons.edit_note_outlined, _startOcr),
        _Tool('BG Remover', Icons.wallpaper_outlined, () => _notReady('BG Remover')),
        _Tool('Image Resizer', Icons.photo_size_select_large_outlined, _resizeImage),
        _Tool('Split PDF', Icons.call_split_outlined, () => _openExisting('pdf')),
        _Tool('Sign', Icons.draw_outlined, _startSign),
        _Tool('Add Watermark', Icons.branding_watermark_outlined, () => _openExisting('pdf')),
        _Tool('Smart Erase', Icons.auto_fix_high_outlined, _startErase),
        _Tool('Reorder Pages', Icons.swap_vert, () => _openExisting('pdf')),
        _Tool('Extract PDF Pages', Icons.content_copy_outlined, () => _openExisting('pdf')),
        _Tool('Rotate PDF', Icons.rotate_90_degrees_ccw_outlined,
            () => _openExisting('document')),
        _Tool('Lock PDF', Icons.lock_outline, () => _notReady('Lock PDF')),
        _Tool('Compress PDF', Icons.compress, () => _openExisting('pdf')),
      ],
      'Utilities': [
        _Tool('AI Chat', Icons.smart_toy_outlined, () => _notReady('AI Chat')),
        _Tool('Print', Icons.print_outlined, () => _openExisting('print')),
        _Tool('Create QR Code', Icons.qr_code_2_outlined, _createQrCode),
      ],
    };
    return ListView(padding: const EdgeInsets.fromLTRB(16, 18, 16, 25), children: [
      const Text('Tools', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 29)),
      const SizedBox(height: 6),
      const Text('Scan • Convert • Edit • Utilities', style: TextStyle(color: dsMuted)),
      const SizedBox(height: 18),
      TextField(
        onChanged: (value) => setState(() => _toolQuery = value.trim().toLowerCase()),
        decoration: InputDecoration(
          hintText: 'Search all tools',
          prefixIcon: const Icon(Icons.search),
          filled: true,
          fillColor: Theme.of(context).colorScheme.surface,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(15),
              borderSide: BorderSide.none),
        ),
      ),
      for (final group in groups.entries) ...[
        if (group.value.any((tool) => tool.title.toLowerCase().contains(_toolQuery)))
          Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: _sectionTitle(group.key)),
        if (group.value.any((tool) => tool.title.toLowerCase().contains(_toolQuery)))
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: group.value.where((tool) => tool.title.toLowerCase()
              .contains(_toolQuery)).length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 4, mainAxisSpacing: 8, crossAxisSpacing: 8, childAspectRatio: .81,
          ),
          itemBuilder: (_, i) {
            final tool = group.value.where((item) => item.title.toLowerCase()
                .contains(_toolQuery)).elementAt(i);
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
        Card(child: ListTile(
          key: const Key('me-scan-settings'),
          leading: const Icon(Icons.document_scanner_outlined, color: dsTeal),
          title: const Text('Scan'),
          subtitle: const Text('Camera and document scan preferences'),
          trailing: const Icon(Icons.chevron_right),
          onTap: _openScanSettings,
        )),
        const Card(child: ListTile(
          leading: Icon(Icons.shield_outlined, color: dsTeal),
          title: Text('Private, on-device storage'),
          subtitle: Text('No account, upload or cloud required'),
        )),
        const Card(child: ListTile(
          leading: Icon(Icons.info_outline),
          title: Text('About DocScanner'),
              subtitle: Text('Version 0.5.2 • Md Jahidul Islam'),
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
    final doc = await _chooseDocument();
    if (doc == null || !mounted) return;
    await _open(doc.id);
    if (mounted) _message('Tap Edit, then Edit Text or Extract Text.');
  }

  Future<ScanDocument?> _chooseDocument() async {
    final unlocked = widget.store.documents.where((doc) =>
        doc.lockHash == null).toList();
    if (unlocked.isEmpty) {
      _message('No unlocked documents. Open a document to manage its lock.');
      return null;
    }
    return showDialog<ScanDocument>(context: context, builder: (dialog) =>
      SimpleDialog(
        title: const Text('Choose a document'),
        children: [
          for (final doc in unlocked)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(dialog, doc),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Text('${doc.name}  ·  ${doc.pages.length} page(s)'),
              ),
            ),
        ],
      ));
  }

  Future<void> _startErase() async {
    final document = await _chooseDocument();
    if (document == null || !mounted || document.pages.isEmpty) return;
    final page = await _choosePage(document, 'Choose a page to erase');
    if (page == null || !mounted) return;
    await Navigator.push<void>(context, MaterialPageRoute(
      builder: (_) => ImageTextEditorScreen(
        store: widget.store,
        documentId: document.id,
        pageId: page.id,
        regions: const [],
        startInEraseMode: true,
      ),
    ));
  }

  Future<ScanPage?> _choosePage(ScanDocument doc, String title) async {
    if (doc.pages.isEmpty) {
      _message('Document has no pages.');
      return null;
    }
    if (doc.pages.length == 1) return doc.pages.first;
    return showDialog<ScanPage>(context: context,
      builder: (dialog) => SimpleDialog(
        title: Text(title),
        children: [
          for (var i = 0; i < doc.pages.length; i++)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(dialog, doc.pages[i]),
              child: Text('Page ${i + 1}'),
            ),
        ],
      ),
    );
  }

  Future<void> _startSign() async {
    final document = await _chooseDocument();
    if (document == null || !mounted) return;
    final page = await _choosePage(document, 'Choose a page to sign');
    if (page == null || !mounted) return;
    await Navigator.push<bool>(context, MaterialPageRoute(
      builder: (_) => SignatureScreen(
        store: widget.store,
        documentId: document.id,
        pageId: page.id,
      ),
    ));
  }

  Future<void> _exportWord() => _exportOffice(toExcel: false);

  Future<void> _exportExcel() => _exportOffice(toExcel: true);

  Future<void> _exportOffice({required bool toExcel}) async {
    final document = await _chooseDocument();
    if (document == null || !mounted) return;
    final bengali = await showDialog<bool>(context: context,
      builder: (dialog) => SimpleDialog(
        title: Text('${toExcel ? 'Excel' : 'Word'} OCR language'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(dialog, false),
            child: const Text('English / Latin'),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(dialog, true),
            child: const Text('বাংলা / Bengali'),
          ),
        ],
      ),
    );
    if (bengali == null || !mounted) return;
    showDialog<void>(context: context, barrierDismissible: false,
      builder: (_) => const PopScope(canPop: false, child: AlertDialog(
        title: Text('Converting document'),
        content: Row(children: [
          CircularProgressIndicator(),
          SizedBox(width: 18),
          Expanded(child: Text('Recognizing text on your device…')),
        ]),
      )),
    );
    File? result;
    Object? failure;
    try {
      result = toExcel
          ? await XlsxExport.createFile(document, bengali: bengali)
          : await DocxExport.createFile(document, bengali: bengali);
    } catch (error) {
      failure = error;
    } finally {
      if (mounted) Navigator.of(context, rootNavigator: true).pop();
    }
    if (!mounted) return;
    if (failure != null) {
      _message('To ${toExcel ? 'Excel' : 'Word'} failed: $failure');
    } else if (result != null) {
      try {
        if (toExcel) {
          await XlsxExport.shareFile(result, document.name);
        } else {
          await DocxExport.shareFile(result, document.name);
        }
      } catch (error) {
        _message('Could not share converted document: $error');
      }
    }
  }

  Future<void> _textToPdf() async {
    await Navigator.push<void>(context, MaterialPageRoute(
      builder: (_) => const TextToPdfScreen(),
    ));
  }

  Future<void> _createQrCode() async {
    await Navigator.push<void>(context, MaterialPageRoute(
      builder: (_) => const QrCodeScreen(),
    ));
  }

  Future<void> _shareDocumentImages() async {
    final doc = await _chooseDocument();
    if (doc == null) return;
    try {
      await DocumentExport.shareImages(doc);
    } catch (error) {
      _message('Could not export images: $error');
    }
  }

  Future<void> _shareLongImage() async {
    final doc = await _chooseDocument();
    if (doc == null) return;
    try {
      await ImageToolOperations.shareLongImage(doc);
    } catch (error) {
      _message('Could not create long image: $error');
    }
  }

  Future<void> _resizeImage() async {
    try {
      final image = await _picker.pickImage(source: ImageSource.gallery,
          requestFullMetadata: false);
      if (!mounted || image == null) return;
      final size = await showDialog<int>(context: context,
        builder: (dialog) => SimpleDialog(
          title: const Text('Maximum image dimension'),
          children: [
            for (final dimension in [640, 1024, 1600, 2048])
              SimpleDialogOption(
                onPressed: () => Navigator.pop(dialog, dimension),
                child: Text('$dimension pixels'),
              ),
          ],
        ));
      if (size == null) return;
      await ImageToolOperations.shareResizedImage(image.path, size);
    } catch (error) {
      _message('Could not resize image: $error');
    }
  }

  Future<void> _openExisting(String action) async {
    final doc = await _chooseDocument();
    if (doc == null || !mounted) return;
    final id = doc.id;
    if (action == 'pdf') {
      await Navigator.push<void>(context, MaterialPageRoute(
        builder: (_) => PdfToolsScreen(store: widget.store, documentId: id),
      ));
    } else if (action == 'print') {
      try {
        await DocumentExport.printPdf(doc);
      } catch (error) {
        _message('Could not print PDF: $error');
      }
    } else {
      await _open(id);
    }
  }

  Future<void> _mergeDocuments() async {
    final id = await Navigator.push<String>(context, MaterialPageRoute(
      builder: (_) => MergeDocumentsScreen(store: widget.store),
    ));
    if (id != null && mounted) await _open(id);
  }

  void _notReady(String feature) => _message('$feature is planned; this tool is not yet implemented.');

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
    if (doc.lockHash != null) {
      _message('This document has an access PIN. Open it to unlock first.');
      return;
    }
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
  Widget build(BuildContext context) => SizedBox(
        width: big ? 82 : 39,
        height: big ? 82 : 39,
        child: Image.asset(
          'assets/branding/ds_logo.png',
          fit: BoxFit.contain,
          filterQuality: FilterQuality.medium,
        ),
      );
}
