import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import '../models.dart';
import '../services/document_export.dart';
import '../services/id_card_page_composer.dart';
import '../services/docx_export.dart';
import '../services/image_processor.dart';
import '../services/image_tool_operations.dart';
import '../services/xlsx_export.dart';
import '../storage/document_store.dart';
import '../theme.dart';
import 'camera_screen.dart';
import 'compress_screen.dart';
import 'document_screen.dart';
import 'document_text_tools_screen.dart';
import 'edit_text_screen.dart';
import 'gallery_import_review_screen.dart';
import 'lock_document_screen.dart';
import 'pdf_tools_screen.dart';
import 'signature_screen.dart';

const _darkBg = Color(0xFF1B1B1D);
const _darkPanel = Color(0xFF2C2C2F);

/// Image-backed document grid modeled on the provided scan/More/editor video.
/// All document processing remains offline. There is deliberately no Ask AI.
class DocumentDetailScreen extends StatefulWidget {
  const DocumentDetailScreen({
    super.key,
    required this.store,
    required this.documentId,
    this.openEditorFirst = false,
  });

  final DocumentStore store;
  final String documentId;
  final bool openEditorFirst;

  @override
  State<DocumentDetailScreen> createState() => _DocumentDetailScreenState();
}

class _DocumentDetailScreenState extends State<DocumentDetailScreen> {
  final _picker = ImagePicker();
  final Set<String> _selected = {};
  bool _selecting = false;
  bool _busy = false;
  bool _authorized = true;

  ScanDocument? get _doc => widget.store.byId(widget.documentId);

  @override
  void initState() {
    super.initState();
    _authorized = _doc?.lockHash == null;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!_authorized) await _verifyPin();
      if (widget.openEditorFirst && mounted && _authorized) {
        await _edit(0, true);
      }
    });
  }

  String _pinHash(String pin) => sha256.convert(
    utf8.encode('${widget.documentId}:$pin'),
  ).toString();

  void _notice(Object message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('$message'),
    ));
  }

  Future<void> _run(Future<void> Function() operation) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await operation();
    } catch (error) {
      _notice(error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<String?> _input(String title, {String initial = '',
      String hint = '', bool secret = false}) async {
    final controller = TextEditingController(text: initial);
    final result = await showDialog<String>(context: context,
      builder: (dialog) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          obscureText: secret,
          autofocus: true,
          decoration: InputDecoration(hintText: hint),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialog),
              child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dialog, controller.text),
              child: const Text('Save')),
        ],
      ),
    );
    controller.dispose();
    return result;
  }

  Future<bool> _confirm(String title, String message) async =>
      await showDialog<bool>(context: context, builder: (dialog) => AlertDialog(
        title: Text(title), content: Text(message), actions: [
          TextButton(onPressed: () => Navigator.pop(dialog, false),
              child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dialog, true),
              child: const Text('Confirm')),
        ],
      )) ?? false;

  Future<void> _verifyPin() async {
    final expected = _doc?.lockHash;
    if (expected == null) {
      if (mounted) setState(() => _authorized = true);
      return;
    }
    final pin = await _input('Unlock document', hint: 'Enter access PIN', secret: true);
    if (!mounted) return;
    if (pin != null && _pinHash(pin) == expected) {
      setState(() => _authorized = true);
    } else {
      _notice('Incorrect or cancelled PIN.');
      Navigator.of(context).pop();
    }
  }

  Future<void> _lock() async {
    final doc = _doc;
    if (doc == null) return;
    if (doc.lockHash != null) {
      if (!await _confirm('Remove document lock?',
          'This removes the app-level access PIN.')) {
        return;
      }
      await _run(() => widget.store.setLockHash(doc.id, null));
    } else {
      await Navigator.push<bool>(context, MaterialPageRoute(
        builder: (_) => LockDocumentScreen(
          store: widget.store, documentId: doc.id),
      ));
    }
  }

  Future<void> _rename() async {
    final doc = _doc;
    if (doc == null) return;
    final result = await _input('Rename document', initial: doc.name);
    if (result != null && result.trim().isNotEmpty) {
      await _run(() => widget.store.renameDocument(doc.id, result));
    }
  }

  Future<void> _tags() async {
    final doc = _doc;
    if (doc == null) return;
    final result = await _input('Tags', initial: doc.tags.join(', '),
        hint: 'Comma-separated tags');
    if (result == null) return;
    await _run(() => widget.store.setTags(doc.id, result.split(',')
        .map((tag) => tag.trim()).where((tag) => tag.isNotEmpty).toSet().toList()));
  }

  void _info() {
    final doc = _doc;
    if (doc == null) return;
    showDialog<void>(context: context, builder: (dialog) => AlertDialog(
      title: const Text('Document Information'),
      content: Text('Name: ${doc.name}\n'
          'Created: ${doc.createdAt.toLocal()}\n'
          'Pages: ${doc.pages.length}\n'
          'Tags: ${doc.tags.join(', ')}\n'
          'Stored locally on this device.'),
      actions: [TextButton(onPressed: () => Navigator.pop(dialog),
          child: const Text('Close'))],
    ));
  }

  Future<void> _edit([int pageIndex = 0, bool preview = false]) async {
    if (!mounted) return;
    await Navigator.push<void>(context, MaterialPageRoute(
      builder: (_) => DocumentScreen(store: widget.store,
          documentId: widget.documentId, initialPage: pageIndex,
          initialPreview: preview),
    ));
  }

  Future<void> _pdfTools() async {
    await Navigator.push<void>(context, MaterialPageRoute(
      builder: (_) => PdfToolsScreen(store: widget.store,
          documentId: widget.documentId),
    ));
  }

  Future<void> _addPages() async {
    final doc = _doc;
    if (doc == null) return;
    final source = await showModalBottomSheet<bool>(context: context,
      builder: (sheet) => SafeArea(child: Column(
        mainAxisSize: MainAxisSize.min, children: [
          ListTile(leading: const Icon(Icons.camera_alt_outlined),
            title: const Text('Scan with Camera'),
            onTap: () => Navigator.pop(sheet, true)),
          ListTile(leading: const Icon(Icons.photo_library_outlined),
            title: const Text('Import from Gallery'),
            onTap: () => Navigator.pop(sheet, false)),
        ],
      )),
    );
    if (source == null || !mounted) return;
    await _run(() async {
      List<String> paths;
      if (source) {
        paths = await Navigator.push<List<String>>(context, MaterialPageRoute(
          builder: (_) => CameraScreen(cardMode: doc.kind.twoSided,
            side: doc.compositeCardPages ? 'Front' : null,
            cardCaptureLimit: doc.compositeCardPages ? 2 : null),
        )) ?? [];
      } else {
        final remaining = doc.compositeCardPages ? 2
            : (doc.kind.twoSided ? 2 - doc.pages.length : null);
        if (remaining != null && remaining <= 0) {
          throw StateError('Both sides of the card have already been added.');
        }
        final images = await _picker.pickMultiImage(limit: remaining,
            requestFullMetadata: false);
        if (images.isEmpty || !mounted) return;
        final review = await Navigator.of(context).push<GalleryImportResult>(
          MaterialPageRoute(builder: (_) => GalleryImportReviewScreen(
            imagePaths: images.map((image) => image.path).toList(),
            preferIdCardBounds: doc.kind.twoSided,
          )),
        );
        paths = review?.paths ?? [];
      }
      if (doc.compositeCardPages && paths.isNotEmpty) {
        if (paths.length != 2) {
          throw StateError('Scan both Front and Back to add a card page.');
        }
        final composite = await IdCardPageComposer.compose([
          await File(paths[0]).readAsBytes(),
          await File(paths[1]).readAsBytes(),
        ]);
        final dir = await getTemporaryDirectory();
        final file = File('${dir.path}/ds_extra_card_'
            '${DateTime.now().microsecondsSinceEpoch}.jpg');
        await file.writeAsBytes(composite, flush: true);
        paths = [file.path];
      }
      if (paths.isNotEmpty) await widget.store.appendPaths(doc.id, paths);
    });
  }

  ScanDocument? _activeDocument() {
    final doc = _doc;
    if (doc == null) return null;
    if (_selected.isEmpty) return doc;
    return doc.copyWith(pages: doc.pages
        .where((page) => _selected.contains(page.id)).toList());
  }

  Future<void> _sharePdf() async {
    final doc = _activeDocument();
    if (doc != null) await _run(() => DocumentExport.sharePdf(doc));
  }

  Future<void> _shareImages() async {
    final doc = _activeDocument();
    if (doc != null) await _run(() => DocumentExport.shareImages(doc));
  }

  Future<void> _shareLongImage() async {
    final doc = _activeDocument();
    if (doc != null) await _run(() => ImageToolOperations.shareLongImage(doc));
  }

  Future<void> _collage() async {
    final doc = _activeDocument();
    if (doc != null) await _run(() => ImageToolOperations.shareCollage(doc));
  }

  Future<void> _office(bool excel) async {
    final doc = _activeDocument();
    if (doc == null) return;
    final bengali = await showDialog<bool>(context: context,
      builder: (dialog) => SimpleDialog(
        title: Text('${excel ? 'Excel' : 'Word'} OCR language'),
        children: [
          SimpleDialogOption(onPressed: () => Navigator.pop(dialog, false),
              child: const Text('English / Latin')),
          SimpleDialogOption(onPressed: () => Navigator.pop(dialog, true),
              child: const Text('বাংলা / Bengali')),
        ],
      ),
    );
    if (bengali == null) return;
    await _run(() async {
      final file = excel
          ? await XlsxExport.createFile(doc, bengali: bengali)
          : await DocxExport.createFile(doc, bengali: bengali);
      if (excel) {
        await XlsxExport.shareFile(file, doc.name);
      } else {
        await DocxExport.shareFile(file, doc.name);
      }
    });
  }

  Future<void> _print() async {
    final doc = _activeDocument();
    if (doc != null) await _run(() => DocumentExport.printPdf(doc));
  }

  Future<void> _saveToGallery() async {
    final doc = _activeDocument();
    if (doc == null) return;
    await _run(() async {
      final count = await DocumentExport.saveImagesToGallery(doc);
      _notice('$count page(s) saved to Gallery.');
    });
  }

  Future<void> _extractText() async {
    final doc = _doc;
    if (doc == null || doc.pages.isEmpty) return;
    final page = _selected.isEmpty
        ? doc.pages.first
        : doc.pages.firstWhere((page) => _selected.contains(page.id));
    await Navigator.push<void>(context, MaterialPageRoute(
      builder: (_) => EditTextScreen(store: widget.store,
          documentId: doc.id, pageId: page.id),
    ));
  }

  Future<void> _sign() async {
    final doc = _doc;
    if (doc == null || doc.pages.isEmpty) return;
    final page = _selected.isNotEmpty
        ? doc.pages.firstWhere((p) => _selected.contains(p.id))
        : doc.pages.first;
    await Navigator.push<bool>(context, MaterialPageRoute(
      builder: (_) => SignatureScreen(store: widget.store,
          documentId: doc.id, pageId: page.id),
    ));
  }

  Future<void> _noHandwriting() async {
    final doc = _activeDocument();
    if (doc == null) return;
    await _run(() async {
      for (final page in doc.pages) {
        final original = await File(page.originalPath).readAsBytes();
        final processed = await ImageProcessor.process(original,
            filter: ScanFilter.noHandwriting);
        await widget.store.replacePageBytes(widget.documentId,
            page.id, processed, filter: ScanFilter.noHandwriting.label);
      }
      _notice('Experimental handwriting reduction applied. Review each page.');
    });
  }

  Future<void> _textTool(DocumentTextTool tool) async {
    final doc = _activeDocument();
    if (doc == null) return;
    await Navigator.push<void>(context, MaterialPageRoute(
      builder: (_) => DocumentTextToolsScreen(document: doc, tool: tool),
    ));
  }

  Future<void> _compress() async {
    final doc = _activeDocument();
    if (doc != null) {
      await Navigator.push<void>(context, MaterialPageRoute(
        builder: (_) => CompressScreen(document: doc),
      ));
    }
  }

  Future<void> _mergeFiles() async {
    final mergedId = await Navigator.push<String>(context, MaterialPageRoute(
      builder: (_) => MergeDocumentsScreen(store: widget.store),
    ));
    if (mergedId != null && mounted) {
      await Navigator.push<void>(context, MaterialPageRoute(
        builder: (_) => DocumentDetailScreen(store: widget.store,
            documentId: mergedId),
      ));
    }
  }

  Future<void> _copyMove() async {
    final doc = _doc;
    if (doc == null) return;
    final choice = await showModalBottomSheet<String>(context: context,
      builder: (sheet) => SafeArea(child: Column(
        mainAxisSize: MainAxisSize.min, children: [
          ListTile(leading: const Icon(Icons.copy_outlined),
            title: const Text('Copy pages into new document'),
            onTap: () => Navigator.pop(sheet, 'copy')),
          ListTile(leading: const Icon(Icons.drive_file_move_outlined),
            title: Text(_selected.isEmpty
                ? 'Move document to folder' : 'Move selected pages to new document'),
            onTap: () => Navigator.pop(sheet, 'move')),
        ],
      )),
    );
    if (choice == null || !mounted) return;
    if (choice == 'copy' || _selected.isNotEmpty) {
      await _run(() async {
        final pages = _activeDocument()!.pages;
        final copied = await widget.store.createFromPaths(
          pages.map((page) => page.path).toList(),
          name: '${doc.name} - ${choice == 'copy' ? 'Copy' : 'Moved pages'}',
        );
        if (choice == 'move') {
          if (pages.length == doc.pages.length) {
            await widget.store.deleteDocument(doc.id);
          } else {
            await widget.store.removePages(doc.id,
                pages.map((page) => page.id).toSet());
          }
        }
        if (!mounted) return;
        _selected.clear();
        setState(() => _selecting = false);
        if (choice == 'move' && pages.length == doc.pages.length) {
          await Navigator.pushReplacement<void, void>(context,
              MaterialPageRoute(builder: (_) => DocumentDetailScreen(
                store: widget.store, documentId: copied.id)));
          return;
        }
        await Navigator.push<void>(context, MaterialPageRoute(
          builder: (_) => DocumentDetailScreen(store: widget.store,
              documentId: copied.id),
        ));
      });
      return;
    }

    final folder = await showDialog<String>(context: context,
      builder: (dialog) => SimpleDialog(title: const Text('Move to folder'),
        children: [
          SimpleDialogOption(onPressed: () => Navigator.pop(dialog, 'root'),
            child: const Text('All documents (root)')),
          for (final item in widget.store.folders)
            SimpleDialogOption(onPressed: () => Navigator.pop(dialog, item.id),
                child: Text(item.name)),
          SimpleDialogOption(onPressed: () => Navigator.pop(dialog, 'new'),
            child: const Text('+ New folder')),
        ],
      ),
    );
    if (folder == null) return;
    if (folder == 'new') {
      final name = await _input('New folder', hint: 'Folder name');
      if (name == null || name.trim().isEmpty) return;
      await _run(() async {
        final newFolder = await widget.store.createFolder(name);
        await widget.store.moveDocument(doc.id, newFolder.id);
      });
    } else {
      await _run(() => widget.store.moveDocument(doc.id,
          folder == 'root' ? null : folder));
    }
    _notice('Document moved.');
  }

  Future<void> _delete() async {
    final doc = _doc;
    if (doc == null) return;
    final deletingPages = _selected.isNotEmpty &&
        _selected.length < doc.pages.length;
    final approved = await _confirm(
        deletingPages ? 'Delete selected pages?' : 'Delete document?',
        'This removes ${deletingPages ? 'the selected pages' : doc.name} '
        'from your document list.');
    if (!approved) return;
    if (deletingPages) {
      await _run(() => widget.store.removePages(doc.id, _selected));
      setState(() { _selected.clear(); _selecting = false; });
    } else {
      await widget.store.deleteDocument(doc.id);
      if (mounted) Navigator.pop(context);
    }
  }

  void _shareSheet() {
    final doc = _activeDocument();
    if (doc == null) return;
    var shareLink = false;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: _darkPanel,
      showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, refresh) => SafeArea(child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Row(children: [
              Text('${doc.pages.length} selected',
                  style: const TextStyle(color: Colors.white, fontSize: 19)),
              const Spacer(),
              IconButton(icon: const Icon(Icons.close, color: Colors.white),
                  onPressed: () => Navigator.pop(sheetContext)),
            ]),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: _shareTab('Share File', !shareLink, () =>
                  refresh(() => shareLink = false))),
              Expanded(child: _shareTab('Share Link', shareLink, () =>
                  refresh(() => shareLink = true))),
            ]),
            const SizedBox(height: 18),
            if (shareLink) ...[
              const Icon(Icons.cloud_off_outlined, size: 50, color: Colors.white70),
              const SizedBox(height: 12),
              const Text('DocScanner keeps files local. A hosted share link '
                  'cannot be generated without uploading the document.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white70)),
              const SizedBox(height: 14),
              FilledButton(onPressed: () => refresh(() => shareLink = false),
                  child: const Text('Share File Instead')),
            ] else ...[
              SizedBox(height: 140, child: ListView(
                scrollDirection: Axis.horizontal, children: [
                  for (final page in doc.pages)
                    Padding(padding: const EdgeInsets.only(right: 10),
                    child: Image.file(File(page.path), width: 105,
                          cacheWidth: 220, fit: BoxFit.contain)),
                ],
              )),
              const SizedBox(height: 12),
              _shareChoice(Icons.picture_as_pdf, 'Share as PDF', sheetContext, _sharePdf),
              _shareChoice(Icons.description_outlined, 'Share as Word', sheetContext,
                  () => _office(false)),
              _shareChoice(Icons.panorama_vertical_outlined,
                  'Share as Long Image', sheetContext, _shareLongImage),
              _shareChoice(Icons.image_outlined, 'Share as Images',
                  sheetContext, _shareImages),
            ],
          ]),
        )),
      ),
    );
  }

  Widget _shareTab(String title, bool active, VoidCallback tap) =>
      InkWell(onTap: tap, child: Padding(
        padding: const EdgeInsets.all(12), child: Column(children: [
          Text(title, style: TextStyle(color: active ? dsTeal : Colors.white70,
              fontWeight: FontWeight.w600)),
          const SizedBox(height: 7),
          Container(height: 2, color: active ? dsTeal : Colors.transparent),
        ]),
      ));

  Widget _shareChoice(IconData icon, String label, BuildContext sheet,
      Future<void> Function() action) => ListTile(
    leading: Icon(icon, color: dsTeal),
    title: Text(label, style: const TextStyle(color: Colors.white)),
    trailing: const Icon(Icons.chevron_right, color: Colors.white54),
    onTap: () { Navigator.pop(sheet); action(); },
  );

  Widget _menuItem(IconData icon, String title,
      Future<void> Function() callback, {Color color = Colors.white70}) =>
      InkWell(onTap: () { Navigator.of(context).pop(); callback(); },
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          CircleAvatar(radius: 26, backgroundColor: const Color(0xFF414144),
            child: Icon(icon, color: color, size: 25)),
          const SizedBox(height: 8),
          Text(title, maxLines: 2, textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70, fontSize: 11)),
        ]),
      );

  Widget _menuSection(String title, List<Widget> items) => Column(
    crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(padding: const EdgeInsets.fromLTRB(18, 22, 18, 12),
        child: Text(title, style: const TextStyle(color: Colors.white,
            fontSize: 16))),
      GridView.count(crossAxisCount: 4, childAspectRatio: .85,
        shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 8), children: items),
    ],
  );

  void _moreSheet() {
    final doc = _doc;
    if (doc == null) return;
    showModalBottomSheet<void>(
      context: context, isScrollControlled: true, backgroundColor: _darkPanel,
      builder: (sheetContext) => SizedBox(
        height: MediaQuery.sizeOf(context).height * .90,
        child: SafeArea(child: Column(children: [
          Padding(padding: const EdgeInsets.fromLTRB(18, 12, 12, 8),
            child: Row(children: [
              const Text('More', style: TextStyle(color: Colors.white, fontSize: 21)),
              const Spacer(),
              IconButton(onPressed: () => Navigator.pop(sheetContext),
                  icon: const Icon(Icons.close, color: Colors.white70)),
            ])),
          const Divider(color: Colors.white12),
          Expanded(child: ListView(children: [
            ListTile(
              leading: doc.pages.isEmpty ? const Icon(Icons.description) :
                Image.file(File(doc.pages.first.path), width: 56, height: 65,
                    fit: BoxFit.cover),
              title: Text(doc.name, maxLines: 1,
                  style: const TextStyle(color: Colors.white)),
              subtitle: Align(alignment: Alignment.centerLeft,
                child: InkWell(onTap: () {
                  Navigator.pop(sheetContext); _tags();
                }, child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Text(doc.tags.isEmpty ? 'Tags +' : doc.tags.join(', '),
                      style: const TextStyle(color: Colors.white54)),
                )),
              ),
              trailing: IconButton(icon: const Icon(Icons.info_outline,
                      color: Colors.white70), onPressed: () {
                    Navigator.pop(sheetContext); _info();
                  }),
              onTap: () { Navigator.pop(sheetContext); _rename(); },
            ),
            GridView.count(crossAxisCount: 4, childAspectRatio: .85,
              shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 8),
              children: [
                _menuItem(Icons.edit_document, 'Edit PDF', () => _edit(),
                    color: const Color(0xFFFF692D)),
                _menuItem(Icons.computer_outlined, 'Send to PC', _sharePdf,
                    color: const Color(0xFF51A4FF)),
                _menuItem(Icons.save_alt, 'Save to Gallery', _saveToGallery,
                    color: dsTeal),
                _menuItem(Icons.print_outlined, 'Print', _print, color: dsTeal),
              ],
            ),
            const Divider(color: Colors.white12),
            _menuSection('Convert', [
              _menuItem(Icons.description_outlined, 'To Word', () => _office(false)),
              _menuItem(Icons.table_chart_outlined, 'To Excel', () => _office(true)),
            ]),
            _menuSection('Smart Tools', [
              _menuItem(Icons.text_fields, 'Extract Text', _extractText),
              _menuItem(Icons.grid_view_outlined, 'Collage', _collage),
              _menuItem(Icons.translate, 'Translate',
                  () => _textTool(DocumentTextTool.translate)),
              _menuItem(Icons.compress, 'Compress', _compress),
              _menuItem(Icons.auto_fix_off_outlined, 'No Handwriting', _noHandwriting),
              _menuItem(Icons.quiz_outlined, 'Create Quiz',
                  () => _textTool(DocumentTextTool.quiz)),
              _menuItem(Icons.functions, 'Extract Formulas',
                  () => _textTool(DocumentTextTool.formulas)),
              _menuItem(Icons.menu_book_outlined, 'Read Mode',
                  () => _textTool(DocumentTextTool.read)),
            ]),
            _menuSection('Manage', [
              _menuItem(Icons.view_list_outlined, 'Manage Pages', _pdfTools),
              _menuItem(Icons.lock_outline, 'Lock', _lock),
              _menuItem(Icons.merge_type, 'Merge Files', _mergeFiles),
              _menuItem(Icons.drive_file_move_outline, 'Copy/Move', _copyMove),
            ]),
            TextButton(onPressed: () { Navigator.pop(sheetContext); _delete(); },
              child: const Text('Delete',
                  style: TextStyle(color: Color(0xFFFF684C), fontSize: 17))),
            const SizedBox(height: 25),
          ])),
        ])),
      ),
    );
  }

  void _toggleSelection(String id) {
    setState(() {
      if (!_selected.add(id)) _selected.remove(id);
      if (_selected.isEmpty) _selecting = false;
    });
  }

  Widget _pageTile(ScanDocument doc, int index) {
    final page = doc.pages[index];
    final checked = _selected.contains(page.id);
    return GestureDetector(
      key: ValueKey(page.id),
      onLongPress: () {
        setState(() => _selecting = true);
        _toggleSelection(page.id);
      },
      onTap: () {
        if (_selecting) {
          _toggleSelection(page.id);
        } else {
          _edit(index);
        }
      },
      child: Column(children: [
        Expanded(child: Stack(fit: StackFit.expand, children: [
          Container(color: Colors.white,
            child: Image.file(File(page.path), cacheWidth: 450,
              fit: BoxFit.contain,
              errorBuilder: (_, _, _) => const Icon(Icons.broken_image_outlined))),
          if (_selecting)
            Positioned(top: 8, right: 8, child: CircleAvatar(radius: 14,
              backgroundColor: checked ? dsTeal : Colors.black54,
              child: Icon(checked ? Icons.check : Icons.circle_outlined,
                color: Colors.white, size: 20))),
        ])),
        const SizedBox(height: 7),
        Text(page.title.isNotEmpty ? page.title : '${index + 1}'.padLeft(2, '0'),
          maxLines: 1, style: const TextStyle(color: Colors.white)),
      ]),
    );
  }

  Widget _addTile() => InkWell(
    onTap: _busy ? null : _addPages,
    child: Column(children: [
      Expanded(child: Container(color: _darkPanel, child: Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.add_a_photo_outlined, color: Colors.white54, size: 53),
          const SizedBox(height: 11),
          Container(padding: const EdgeInsets.symmetric(
              horizontal: 13, vertical: 6), color: Colors.white10,
            child: const Text('Add Pages',
                style: TextStyle(color: Colors.white70))),
        ]),
      ))),
      const SizedBox(height: 25),
    ]),
  );

  Widget _bottomAction(IconData icon, String label, VoidCallback tap) =>
      Expanded(child: InkWell(onTap: _busy ? null : tap,
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, color: Colors.white, size: 23),
          const SizedBox(height: 5),
          Text(label, maxLines: 1, style: const TextStyle(
              color: Colors.white, fontSize: 11)),
        ]),
      ));

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.store,
    builder: (context, _) {
      final doc = _doc;
      if (doc == null) {
        return const Scaffold(body: Center(child: Text('Document not found')));
      }
      return Scaffold(
        backgroundColor: _darkBg,
        appBar: AppBar(
          backgroundColor: _darkPanel,
          foregroundColor: Colors.white,
          titleSpacing: 0,
          title: !_authorized
              ? const Text('Locked document')
              : _selecting
              ? Text('${_selected.length} selected',
                  style: const TextStyle(fontSize: 19))
              : InkWell(onTap: _rename,
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Flexible(child: Text(doc.name,
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 17))),
                    const SizedBox(width: 4),
                    const Icon(Icons.edit_outlined, size: 17),
                  ])),
          actions: !_authorized
              ? []
              : _selecting
              ? [TextButton(onPressed: () => setState(() {
                    _selecting = false; _selected.clear();
                  }), child: const Text('Deselect All',
                      style: TextStyle(color: dsTeal, fontSize: 12)))]
              : [
                  TextButton(onPressed: _tags,
                    child: const Text('Tags +',
                      style: TextStyle(color: Colors.white70, fontSize: 11))),
                  IconButton(onPressed: _info, icon: const Icon(Icons.info_outline),
                    tooltip: 'Info', iconSize: 20),
                  IconButton(onPressed: _moreSheet,
                    icon: const Icon(Icons.more_vert), tooltip: 'More'),
                ],
        ),
        body: !_authorized
            ? const Center(child: Icon(Icons.lock_outline,
                size: 64, color: Colors.white54))
            : SafeArea(child: Column(children: [
                if (_busy) const LinearProgressIndicator(color: dsTeal),
                if (_selecting)
                  Container(width: double.infinity, color: _darkPanel,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 9),
                    child: const Text('Select pages • Use Manage Pages to drag and reorder',
                      style: TextStyle(color: Colors.white60, fontSize: 12))),
                Expanded(child: GridView.builder(
                  padding: const EdgeInsets.fromLTRB(15, 15, 15, 14),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2, crossAxisSpacing: 12,
                    mainAxisSpacing: 15, childAspectRatio: .69,
                  ),
                  itemCount: doc.pages.length + (doc.kind.twoSided &&
                      !doc.compositeCardPages &&
                      doc.pages.length == 2 ? 0 : 1),
                  itemBuilder: (context, index) => index == doc.pages.length
                      ? _addTile() : _pageTile(doc, index),
                )),
                Container(height: 78, color: _darkPanel,
                  child: Row(children: _selecting
                      ? [
                          _bottomAction(Icons.share_outlined, 'Share', _shareSheet),
                          _bottomAction(Icons.save_alt, 'Save to Gallery', _saveToGallery),
                          _bottomAction(Icons.drive_file_move_outline,
                              'Move/Copy', _copyMove),
                          _bottomAction(Icons.grid_view_outlined, 'Collage', _collage),
                          _bottomAction(Icons.delete_outline, 'Delete', _delete),
                        ]
                      : [
                          _bottomAction(Icons.add_a_photo_outlined, 'Add', _addPages),
                          _bottomAction(Icons.edit_outlined, 'Edit', () => _edit()),
                          _bottomAction(Icons.share_outlined, 'Share', _shareSheet),
                          _bottomAction(Icons.description_outlined,
                              'To Word', () => _office(false)),
                          _bottomAction(Icons.draw_outlined, 'Sign', _sign),
                        ])),
              ])),
      );
    },
  );
}
