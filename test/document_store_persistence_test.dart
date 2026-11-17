import 'dart:convert';
import 'dart:io';

import 'package:docscanner/src/storage/document_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory base;
  late File photo;
  late File index;
  late File backup;

  setUp(() async {
    base = await Directory.systemTemp.createTemp('ds_store_');
    photo = File(p.join(base.path, 'photo.jpg'));
    await photo.writeAsBytes([1, 2, 3, 4]);
    index = File(p.join(base.path, 'docscanner', 'index.json'));
    backup = File('${index.path}.bak');
  });

  tearDown(() => base.delete(recursive: true));

  Future<DocumentStore> open() async {
    final store = DocumentStore();
    await store.initialize(baseDirectory: base);
    return store;
  }

  List<File> preserved(String reason) => index.parent
      .listSync()
      .whereType<File>()
      .where((f) => p.basename(f.path).startsWith('index.$reason-'))
      .toList();

  test('documents survive a restart', () async {
    final store = await open();
    await store.createFromPaths([photo.path], name: 'First');
    await store.createFromPaths([photo.path], name: 'Second');
    final reopened = await open();
    expect(reopened.documents.map((d) => d.name), ['Second', 'First']);
  });

  test('a damaged index falls back to the previous save', () async {
    final store = await open();
    await store.createFromPaths([photo.path], name: 'First');
    await store.createFromPaths([photo.path], name: 'Second');
    // Simulate a write torn by a crash or a full disk.
    await index.writeAsString('{"schema":1,"documents":[{"id":"x"');

    final reopened = await open();
    expect(reopened.documents.map((d) => d.name), ['First']);
    expect(preserved('unreadable'), hasLength(1));

    // The next save must rebuild a valid index without destroying the
    // good backup with the damaged file.
    await reopened.createFromPaths([photo.path], name: 'Third');
    expect((await open()).documents.map((d) => d.name), ['Third', 'First']);
    expect(jsonDecode(await backup.readAsString()), isA<Map>());
  });

  test('one damaged entry does not discard the other documents', () async {
    final store = await open();
    await store.createFromPaths([photo.path], name: 'First');
    await store.createFromPaths([photo.path], name: 'Second');
    final data = jsonDecode(await index.readAsString()) as Map<String, dynamic>;
    (data['documents'] as List).insert(1, {'id': 'broken'});
    await index.writeAsString(jsonEncode(data));

    final reopened = await open();
    expect(reopened.documents.map((d) => d.name), ['Second', 'First']);
    expect(preserved('partial'), hasLength(1));
  });

  test('an unreadable index with no backup is kept, never overwritten',
      () async {
    await index.parent.create(recursive: true);
    await index.writeAsString('not json at all');

    final store = await open();
    expect(store.documents, isEmpty);
    await store.createFromPaths([photo.path], name: 'New');

    final kept = preserved('unreadable');
    expect(kept, hasLength(1));
    expect(await kept.single.readAsString(), 'not json at all');
    expect((await open()).documents.single.name, 'New');
  });

  test('overlapping saves leave a complete, valid index', () async {
    final store = await open();
    await Future.wait([
      for (var i = 0; i < 12; i++)
        store.createFromPaths([photo.path], name: 'Doc $i'),
    ]);
    final data = jsonDecode(await index.readAsString()) as Map<String, dynamic>;
    expect(data['documents'], hasLength(12));
    expect(File('${index.path}.tmp').existsSync(), isFalse);
    expect((await open()).documents, hasLength(12));
  });
}
