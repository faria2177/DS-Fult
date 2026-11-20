import 'package:flutter/material.dart';

import 'src/app.dart';
import 'src/services/code_actions.dart';
import 'src/storage/document_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final store = DocumentStore();
  await store.initialize();
  // Live QR / barcode chip in the scanner: open, copy or share.
  CodeActions.install();
  runApp(DocScannerApp(store: store));
}
