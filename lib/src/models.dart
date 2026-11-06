import 'package:flutter/foundation.dart';

enum DocumentKind { document, idCard, driverLicense, bankCard }

extension DocumentKindLabel on DocumentKind {
  String get label => switch (this) {
        DocumentKind.document => 'Document',
        DocumentKind.idCard => 'ID Card',
        DocumentKind.driverLicense => 'Driver License',
        DocumentKind.bankCard => 'Bank Card',
      };

  bool get twoSided => this != DocumentKind.document;
}

@immutable
class ScanPage {
  const ScanPage({
    required this.id,
    required this.path,
    required this.originalPath,
    this.filter = 'Original',
    this.recognizedText = '',
  });

  final String id;
  final String path;
  final String originalPath;
  final String filter;
  final String recognizedText;

  ScanPage copyWith({String? path, String? filter, String? recognizedText}) => ScanPage(
        id: id,
        path: path ?? this.path,
        originalPath: originalPath,
        filter: filter ?? this.filter,
        recognizedText: recognizedText ?? this.recognizedText,
      );

  factory ScanPage.fromJson(Map<String, dynamic> json) => ScanPage(
        id: json['id'] as String,
        path: json['path'] as String,
        originalPath: json['originalPath'] as String? ?? json['path'] as String,
        filter: json['filter'] as String? ?? 'Original',
        recognizedText: json['recognizedText'] as String? ?? '',
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'path': path,
        'originalPath': originalPath,
        'filter': filter,
        'recognizedText': recognizedText,
      };
}

@immutable
class ScanDocument {
  const ScanDocument({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.pages,
    this.folderId,
    this.kind = DocumentKind.document,
  });

  final String id;
  final String name;
  final DateTime createdAt;
  final List<ScanPage> pages;
  final String? folderId;
  final DocumentKind kind;

  ScanDocument copyWith({
    String? name,
    List<ScanPage>? pages,
    String? folderId,
    bool clearFolder = false,
  }) => ScanDocument(
        id: id,
        name: name ?? this.name,
        createdAt: createdAt,
        pages: pages ?? this.pages,
        kind: kind,
        folderId: clearFolder ? null : (folderId ?? this.folderId),
      );

  factory ScanDocument.fromJson(Map<String, dynamic> json) => ScanDocument(
        id: json['id'] as String,
        name: json['name'] as String,
        createdAt: DateTime.parse(json['createdAt'] as String),
        pages: (json['pages'] as List<dynamic>)
            .map((e) => ScanPage.fromJson(e as Map<String, dynamic>))
            .toList(growable: false),
        folderId: json['folderId'] as String?,
        kind: DocumentKind.values.firstWhere(
          (e) => e.name == json['kind'],
          orElse: () => DocumentKind.document,
        ),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'createdAt': createdAt.toIso8601String(),
        'pages': pages.map((p) => p.toJson()).toList(),
        'folderId': folderId,
        'kind': kind.name,
      };
}

@immutable
class DocumentFolder {
  const DocumentFolder({required this.id, required this.name});

  final String id;
  final String name;

  factory DocumentFolder.fromJson(Map<String, dynamic> json) =>
      DocumentFolder(id: json['id'] as String, name: json['name'] as String);

  Map<String, dynamic> toJson() => {'id': id, 'name': name};
}
