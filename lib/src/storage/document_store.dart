import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../models.dart';
import '../services/image_processor.dart';

/// Local-only storage: the image files and index never leave the device.
class DocumentStore extends ChangeNotifier {
  static const _uuid = Uuid();
  late Directory _root;
  late Directory _images;
  late File _index;
  late File _backup;
  Future<void> _writes = Future.value();
  /// False while `index.json` on disk is damaged; such a file must never
  /// replace the good backup.
  bool _liveIndexTrusted = false;

  final List<ScanDocument> _documents = [];
  final List<DocumentFolder> _folders = [];

  List<ScanDocument> get documents => List.unmodifiable(_documents);
  List<DocumentFolder> get folders => List.unmodifiable(_folders);

  /// [baseDirectory] replaces the app-support folder in tests.
  Future<void> initialize({Directory? baseDirectory}) async {
    final directory = baseDirectory ?? await getApplicationSupportDirectory();
    _root = Directory(p.join(directory.path, 'docscanner'));
    _images = Directory(p.join(_root.path, 'images'));
    await _images.create(recursive: true);
    _index = File(p.join(_root.path, 'index.json'));
    _backup = File('${_index.path}.bak');
    // Newest good copy first: the live index, then the copy kept from the
    // save before it. A torn or damaged live file therefore costs at most
    // the very last change instead of the whole library.
    var loaded = false;
    for (final candidate in [_index, _backup]) {
      if (!await candidate.exists()) continue;
      final skipped = await _load(candidate);
      if (skipped == null) {
        await _preserve(candidate, 'unreadable');
        continue;
      }
      if (skipped > 0) await _preserve(candidate, 'partial');
      _liveIndexTrusted = identical(candidate, _index) && skipped == 0;
      loaded = true;
      break;
    }
    if (!loaded) {
      _documents.clear();
      _folders.clear();
    }
    notifyListeners();
  }

  /// Reads [file] into memory. Returns how many damaged entries were left
  /// out, or null when the file as a whole cannot be understood. One bad
  /// entry never discards the entries around it.
  Future<int?> _load(File file) async {
    try {
      final data = jsonDecode(await file.readAsString());
      if (data is! Map<String, dynamic>) return null;
      final documents = <ScanDocument>[];
      final folders = <DocumentFolder>[];
      var skipped = 0;
      for (final value in data['documents'] as List<dynamic>? ?? const []) {
        try {
          documents.add(ScanDocument.fromJson(value as Map<String, dynamic>));
        } catch (error) {
          skipped++;
          debugPrint('Skipped a damaged document entry: $error');
        }
      }
      for (final value in data['folders'] as List<dynamic>? ?? const []) {
        try {
          folders.add(DocumentFolder.fromJson(value as Map<String, dynamic>));
        } catch (error) {
          skipped++;
          debugPrint('Skipped a damaged folder entry: $error');
        }
      }
      _documents
        ..clear()
        ..addAll(documents);
      _folders
        ..clear()
        ..addAll(folders);
      return skipped;
    } catch (error) {
      debugPrint('Document index ${p.basename(file.path)} unreadable: $error');
      return null;
    }
  }

  /// Keeps a damaged index under a unique name so later saves can never
  /// overwrite the only copy that might still be repaired by hand.
  Future<void> _preserve(File file, String reason) async {
    try {
      final stamp = DateTime.now().millisecondsSinceEpoch;
      await file.copy(p.join(_root.path, 'index.$reason-$stamp.json'));
    } catch (error) {
      debugPrint('Could not preserve damaged index: $error');
    }
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
    /// Optional original upright images aligned with the processed pages.
    /// These become durable editable sources rather than temporary cache files.
    List<String>? originalPaths,
  }) async {
    if (paths.isEmpty ||
        (kind.twoSided && !compositeCardPages && paths.length > 2) ||
        (originalPaths != null && originalPaths.length != paths.length)) {
      throw ArgumentError('Invalid image/original count for ${kind.label}');
    }
    final pages = <ScanPage>[];
    for (var i = 0; i < paths.length; i++) {
      final copied = await _copyInput(paths[i]);
      final rawOriginal = originalPaths == null ||
              originalPaths[i] == paths[i]
          ? null
          : await _copyInput(originalPaths[i]);
      pages.add(ScanPage(
        id: _uuid.v4(),
        path: copied,
        originalPath: copied, // Filter baseline remains the corrected scan.
        rawSourcePath: rawOriginal, // Separate full still for re-crop.
      ));
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

  /// Apply all selected clockwise quarter-turns in one document-index update.
  /// The caller stages rotations in the UI; no saved page changes until this
  /// method is explicitly called. Original captures remain available for crop
  /// recovery and no existing backing image is overwritten.
  Future<void> rotatePages(
      String documentId, Map<String, int> clockwiseQuarterTurns) async {
    final document = byId(documentId);
    if (document == null) throw StateError('Document not found');
    if (document.lockHash != null) {
      throw StateError('Unlock this document before rotating pages');
    }
    final ids = document.pages.map((page) => page.id).toSet();
    if (clockwiseQuarterTurns.keys.any((id) => !ids.contains(id))) {
      throw ArgumentError('Rotation includes a page outside this document');
    }
    final turns = <String, int>{};
    for (final entry in clockwiseQuarterTurns.entries) {
      final normalized = entry.value % 4;
      if (normalized != 0) turns[entry.key] = normalized;
    }
    if (turns.isEmpty) return;

    final newPaths = <String>[];
    final replacements = <String, String>{};
    var committing = false;
    try {
      for (final page in document.pages) {
        final quarters = turns[page.id];
        if (quarters == null) continue;
        final bytes = await File(page.path).readAsBytes();
        final preservePng = p.extension(page.path).toLowerCase() == '.png';
        final rotated = await ImageProcessor.process(
          bytes, rotateDegrees: quarters * 90, outputPng: preservePng,
        );
        final destination = p.join(_images.path,
            '${_uuid.v4()}${preservePng ? '.png' : '.jpg'}');
        newPaths.add(destination);
        await File(destination).writeAsBytes(rotated, flush: true);
        replacements[page.id] = destination;
      }
      // Keep previous images and originalPath references intact. All changed
      // page records are committed in one persist operation.
      committing = true;
      await _replace(document.copyWith(pages: [
        for (final page in document.pages)
          replacements.containsKey(page.id)
              ? page.copyWith(path: replacements[page.id], clearWatermark: true)
              : page,
      ]));
    } catch (_) {
      // If staging fails, none of the stored page records was touched. Do not
      // delete prepared images after a failed index commit: in-memory records
      // may already refer to them and are safer to recover than missing files.
      if (!committing) {
        for (final path in newPaths) {
          try {
            final file = File(path);
            if (await file.exists()) await file.delete();
          } catch (_) {
            // Leave an unreachable staging file rather than hide the error.
          }
        }
      }
      rethrow;
    }
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

  /// Remove a scan the user discarded before keeping it. Unlike
  /// [deleteDocument] its copied page images are removed as well, because a
  /// discarded draft was never a saved document. Only files inside the
  /// app's own images folder are touched.
  Future<void> discardScan(String id) async {
    final doc = byId(id);
    if (doc == null) return;
    _documents.removeWhere((item) => item.id == id);
    await _persist();
    final imagesRoot = p.normalize(_images.path);
    final files = <String>{
      for (final page in doc.pages) ...[
        page.path, page.originalPath,
        if (page.rawSourcePath != null) page.rawSourcePath!,
        if (page.watermarkBackupPath != null) page.watermarkBackupPath!,
      ],
    };
    final stillUsed = <String>{
      for (final other in _documents)
        for (final page in other.pages) ...[
          page.path, page.originalPath,
          if (page.rawSourcePath != null) page.rawSourcePath!,
          if (page.watermarkBackupPath != null) page.watermarkBackupPath!,
        ],
    };
    for (final path in files) {
      if (stillUsed.contains(path) ||
          !p.isWithin(imagesRoot, p.normalize(path))) {
        continue;
      }
      try {
        final file = File(path);
        if (await file.exists()) await file.delete();
      } catch (_) {
        // A leftover image is harmless; the index no longer refers to it.
      }
    }
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

  Future<void> _persist() {
    // Snapshot now, so each save writes the state it was asked to save.
    final data = jsonEncode({
      'schema': 1,
      'documents': _documents.map((d) => d.toJson()).toList(),
      'folders': _folders.map((f) => f.toJson()).toList(),
    });
    // One write at a time, in order: overlapping saves used to be able to
    // interleave inside the same file.
    final write = _writes.then((_) => _writeIndex(data));
    _writes = write.catchError((Object _) {});
    return write.then((_) => notifyListeners());
  }

  /// Atomic replace: the new index is fully written and flushed to a
  /// temporary file, the current one is kept as `.bak`, then the temporary
  /// file is renamed into place. A crash at any point leaves a complete
  /// index or a complete backup on disk.
  Future<void> _writeIndex(String data) async {
    final temporary = File('${_index.path}.tmp');
    await temporary.writeAsString(data, flush: true);
    if (_liveIndexTrusted && await _index.exists()) {
      await _index.copy(_backup.path);
    }
    await temporary.rename(_index.path);
    _liveIndexTrusted = true;
  }

  static String _two(int value) => value.toString().padLeft(2, '0');
}
