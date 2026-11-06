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
  }) async {
    if (paths.isEmpty || (kind.twoSided && paths.length > 2)) {
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
    );
    _documents.insert(0, document);
    await _persist();
    return document;
  }

  Future<void> appendPaths(String documentId, List<String> paths) async {
    final doc = byId(documentId);
    if (doc == null) return;
    if (doc.kind.twoSided && doc.pages.length + paths.length > 2) {
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
  }) async {
    final doc = byId(documentId);
    if (doc == null) return;
    final imagePath = p.join(_images.path, '${_uuid.v4()}.jpg');
    await File(imagePath).writeAsBytes(jpegBytes, flush: true);
    final pages = doc.pages.map((page) {
      if (page.id != pageId) return page;
      return page.copyWith(path: imagePath, filter: filter);
    }).toList(growable: false);
    await _replace(doc.copyWith(pages: pages));
  }

  Future<void> updatePageText(String documentId, String pageId, String text) async {
    final doc = byId(documentId);
    if (doc == null) return;
    final pages = doc.pages.map((page) => page.id == pageId
        ? page.copyWith(recognizedText: text)
        : page).toList(growable: false);
    await _replace(doc.copyWith(pages: pages));
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
