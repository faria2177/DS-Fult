import 'package:flutter/material.dart';

import 'src/app.dart';
import 'src/storage/document_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final store = DocumentStore();
  await store.initialize();
  runApp(DocScannerApp(store: store));
}
