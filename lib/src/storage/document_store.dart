import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../models.dart';

/// Local-only storage: the image files and index never leave the device.
class DocumentStore extends ChangeNotifier {
  static const _uuid = Uuid();
  late Directory _root;
  late Directory _images;
  late File _index;

  final List<ScanDocument> _documents = [];
  final List<DocumentFolder> _folders = [];

  List<ScanDocument> get documents => List.unmodifiable(_documents);
  List<DocumentFolder> get folders => List.unmodifiable(_folders);

  Future<void> initialize() async {
    final directory = await getApplicationSupportDirectory();
    _root = Directory(p.join(directory.path, 'docscanner'));
    _images = Directory(p.join(_root.path, 'images'));
    await _images.create(recursive: true);
    _index = File(p.join(_root.path, 'index.json'));
    if (!await _index.exists()) return;
    try {
      final data = jsonDecode(await _index.readAsString()) as Map<String, dynamic>;
      _documents.addAll((data['documents'] as List<dynamic>? ?? [])
          .map((value) => ScanDocument.fromJson(value as Map<String, dynamic>)));
      _folders.addAll((data['folders'] as List<dynamic>? ?? [])
          .map((value) => DocumentFolder.fromJson(value as Map<String, dynamic>)));
    } catch (error) {
      debugPrint('Document index could not be read: $error');
      // Preserve the unreadable index for recovery rather than overwriting it.
      await _index.copy('${_index.path}.recovery');
    }
    notifyListeners();
  }

  ScanDocument? byId(String id) {
    for (final document in _documents) {
      if (document.id == id) return document;
    }
    return null;
  }

  Future<ScanDocument> createFromPaths(
    List<String> paths, {
    String? name,
    String? folderId,
    DocumentKind kind = DocumentKind.document,
    bool compositeCardPages = false,
  }) async {
    if (paths.isEmpty ||
        (kind.twoSided && !compositeCardPages && paths.length > 2)) {
      throw ArgumentError('Invalid image count for ${kind.label}');
    }
    final pages = <ScanPage>[];
    for (final path in paths) {
      final copied = await _copyInput(path);
      pages.add(ScanPage(id: _uuid.v4(), path: copied, originalPath: copied));
    }
    final now = DateTime.now();
    final document = ScanDocument(
      id: _uuid.v4(),
      name: name ?? '${kind.label} ${now.year}-${_two(now.month)}-${_two(now.day)}',
      createdAt: now,
      pages: pages,
      folderId: folderId,
      kind: kind,
      compositeCardPages: compositeCardPages,
    );
    _documents.insert(0, document);
    await _persist();
    return document;
  }

  Future<void> appendPaths(String documentId, List<String> paths) async {
    final doc = byId(documentId);
    if (doc == null) return;
    if (doc.kind.twoSided && !doc.compositeCardPages &&
        doc.pages.length + paths.length > 2) {
      throw ArgumentError('Only the front and back may be imported.');
    }
    final newPages = <ScanPage>[];
    for (final path in paths) {
      final copied = await _copyInput(path);
      newPages.add(ScanPage(id: _uuid.v4(), path: copied, originalPath: copied));
    }
    await _replace(doc.copyWith(pages: [...doc.pages, ...newPages]));
  }

  Future<void> replacePageBytes(
    String documentId,
    String pageId,
    Uint8List jpegBytes, {
    String filter = 'Original',
    String extension = '.jpg',
    bool replaceOriginal = false,
    bool asWatermark = false,
  }) async {
    final doc = byId(documentId);
    if (doc == null) return;
    if (extension != '.jpg' && extension != '.png') {
      throw ArgumentError.value(extension, 'extension', 'Unsupported image format');
    }
    final imagePath = p.join(_images.path, '${_uuid.v4()}$extension');
    await File(imagePath).writeAsBytes(jpegBytes, flush: true);
    final pages = doc.pages.map((page) {
      if (page.id != pageId) return page;
      return page.copyWith(path: imagePath,
          originalPath: replaceOriginal ? imagePath : null, filter: filter,
          watermarkBackupPath: asWatermark ? page.path : null,
          clearWatermark: !asWatermark);
    }).toList(growable: false);
    await _replace(doc.copyWith(pages: pages));
  }

  /// Restore the image from just before the last watermark. Other edits clear
  /// this backup pointer, preventing removal from silently erasing later edits.
  Future<void> removeLastWatermark(String documentId, String pageId) async {
    final doc = byId(documentId);
    if (doc == null) throw StateError('Document not found');
    final page = doc.pages.where((item) => item.id == pageId).firstOrNull;
    final backup = page?.watermarkBackupPath;
    if (backup == null || !await File(backup).exists()) {
      throw StateError('No removable watermark found on this page');
    }
    await _replace(doc.copyWith(pages: [
      for (final item in doc.pages)
        item.id == pageId ? item.copyWith(path: backup, clearWatermark: true) : item,
    ]));
  }

  Future<void> updatePageText(String documentId, String pageId, String text) async {
    final doc = byId(documentId);
    if (doc == null) return;
    final pages = doc.pages.map((page) => page.id == pageId
        ? page.copyWith(recognizedText: text)
        : page).toList(growable: false);
    await _replace(doc.copyWith(pages: pages));
  }

  Future<void> renamePage(String documentId, String pageId, String title) async {
    final doc = byId(documentId);
    if (doc == null) return;
    await _replace(doc.copyWith(pages: [
      for (final page in doc.pages)
        page.id == pageId ? page.copyWith(title: title.trim()) : page,
    ]));
  }

  Future<void> setTags(String documentId, List<String> tags) async {
    final doc = byId(documentId);
    if (doc != null) await _replace(doc.copyWith(tags: tags));
  }

  Future<void> setLockHash(String documentId, String? hash) async {
    final doc = byId(documentId);
    if (doc != null) {
      await _replace(doc.copyWith(lockHash: hash, clearLock: hash == null));
    }
  }

  /// Removes selected page records, retaining original files for recovery.
  /// The final page is not removable: delete the entire document instead.
  Future<void> removePages(String documentId, Set<String> pageIds) async {
    final doc = byId(documentId);
    if (doc == null || pageIds.isEmpty) return;
    final remaining = doc.pages.where((p) => !pageIds.contains(p.id)).toList();
    if (remaining.isEmpty) {
      throw StateError('A document must contain at least one page.');
    }
    await _replace(doc.copyWith(pages: remaining));
  }

  /// Reorder source pages without modifying any saved image data.
  Future<void> reorderPages(String documentId, int oldIndex, int newIndex) async {
    final doc = byId(documentId);
    if (doc == null) return;
    if (oldIndex < 0 || oldIndex >= doc.pages.length ||
        newIndex < 0 || newIndex >= doc.pages.length) {
      throw RangeError('Invalid page index');
    }
    final pages = [...doc.pages];
    final removed = pages.removeAt(oldIndex);
    pages.insert(newIndex, removed);
    await _replace(doc.copyWith(pages: pages));
  }

  /// Commit a staged page order in one operation. A cancelled reorder screen
  /// must not mutate the stored order, and no image files are rewritten.
  Future<void> setPageOrder(String documentId, List<String> pageIds) async {
    final doc = byId(documentId);
    if (doc == null) throw StateError('Document not found');
    final original = {for (final page in doc.pages) page.id: page};
    if (pageIds.length != doc.pages.length ||
        pageIds.toSet().length != pageIds.length ||
        pageIds.toSet().difference(original.keys.toSet()).isNotEmpty) {
      throw ArgumentError('The new order must contain every page exactly once');
    }
    await _replace(doc.copyWith(pages: [for (final id in pageIds) original[id]!]));
  }

  /// Create a separate editable image-based document from selected local pages.
  Future<ScanDocument> duplicatePages(
      String documentId, List<int> pageIndices, String name) async {
    final document = byId(documentId);
    if (document == null || pageIndices.isEmpty) {
      throw ArgumentError('Select at least one page');
    }
    final paths = <String>[];
    for (final index in pageIndices) {
      if (index < 0 || index >= document.pages.length) {
        throw RangeError.index(index, document.pages);
      }
      paths.add(document.pages[index].path);
    }
    return createFromPaths(paths, name: name);
  }

  /// Merge image pages from local documents; source documents remain unchanged.
  Future<ScanDocument> mergeDocuments(List<String> ids, String name, {
    bool keepOriginals = true,
    String? folderId,
  }) async {
    if (ids.length < 2 || ids.toSet().length != ids.length) {
      throw ArgumentError('Select two or more different documents');
    }
    final paths = <String>[];
    for (final id in ids) {
      final document = byId(id);
      if (document == null) throw ArgumentError('Document not found: $id');
      if (document.lockHash != null) {
        throw StateError('Unlock all selected documents before merging.');
      }
      paths.addAll(document.pages.map((page) => page.path));
    }
    final merged = await createFromPaths(paths, name: name, folderId: folderId);
    if (!keepOriginals) {
      _documents.removeWhere((doc) => ids.contains(doc.id));
      await _persist();
    }
    return merged;
  }

  /// Copies all document pages into independent local files; no file sharing
  /// between the two editable documents.
  Future<ScanDocument> copyDocument(String id, {String? folderId}) async {
    final doc = byId(id);
    if (doc == null) throw StateError('Document not found');
    if (doc.lockHash != null) throw StateError('Unlock the document first');
    return createFromPaths(
      doc.pages.map((page) => page.path).toList(growable: false),
      name: '${doc.name} - Copy',
      folderId: folderId,
      kind: doc.kind,
    );
  }

  Future<void> renameDocument(String id, String name) async {
    final doc = byId(id);
    if (doc != null && name.trim().isNotEmpty) {
      await _replace(doc.copyWith(name: name.trim()));
    }
  }

  Future<void> moveDocument(String id, String? folderId) async {
    final doc = byId(id);
    if (doc != null) {
      await _replace(doc.copyWith(folderId: folderId, clearFolder: folderId == null));
    }
  }

  Future<void> deleteDocument(String id) async {
    _documents.removeWhere((doc) => doc.id == id);
    // Keep image data for recovery until a separate cleanup routine is added.
    await _persist();
  }

  Future<DocumentFolder> createFolder(String name) async {
    final folder = DocumentFolder(id: _uuid.v4(), name: name.trim());
    _folders.add(folder);
    await _persist();
    return folder;
  }

  Future<void> renameFolder(String id, String name) async {
    final index = _folders.indexWhere((folder) => folder.id == id);
    if (index == -1 || name.trim().isEmpty) return;
    _folders[index] = DocumentFolder(id: id, name: name.trim());
    await _persist();
  }

  Future<void> deleteFolder(String id) async {
    _folders.removeWhere((folder) => folder.id == id);
    for (var i = 0; i < _documents.length; i++) {
      if (_documents[i].folderId == id) {
        _documents[i] = _documents[i].copyWith(clearFolder: true);
      }
    }
    await _persist();
  }

  Future<void> _replace(ScanDocument updated) async {
    final i = _documents.indexWhere((doc) => doc.id == updated.id);
    if (i < 0) return;
    _documents[i] = updated;
    await _persist();
  }

  Future<String> _copyInput(String from) async {
    final extension = p.extension(from).toLowerCase();
    final ext = const {'.jpg', '.jpeg', '.png', '.webp'}.contains(extension)
        ? extension
        : '.jpg';
    final destination = p.join(_images.path, '${_uuid.v4()}$ext');
    await File(from).copy(destination);
    return destination;
  }

  Future<void> _persist() async {
    final data = jsonEncode({
      'schema': 1,
      'documents': _documents.map((d) => d.toJson()).toList(),
      'folders': _folders.map((f) => f.toJson()).toList(),
    });
    await _index.writeAsString(data, flush: true);
    notifyListeners();
  }

  static String _two(int value) => value.toString().padLeft(2, '0');
}
