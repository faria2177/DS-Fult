import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'screens/home_shell.dart';
import 'storage/document_store.dart';
import 'theme.dart';

class DocScannerApp extends StatefulWidget {
  const DocScannerApp({super.key, required this.store});

  final DocumentStore store;

  @override
  State<DocScannerApp> createState() => _DocScannerAppState();
}

class _DocScannerAppState extends State<DocScannerApp> {
  bool _dark = false;

  @override
  void initState() {
    super.initState();
    _restoreTheme();
  }

  Future<void> _restoreTheme() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) setState(() => _dark = prefs.getBool('darkTheme') ?? false);
  }

  Future<void> _setDark(bool value) async {
    setState(() => _dark = value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('darkTheme', value);
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'DocScanner',
        debugShowCheckedModeBanner: false,
        theme: buildDocTheme(dark: false),
        darkTheme: buildDocTheme(dark: true),
        themeMode: _dark ? ThemeMode.dark : ThemeMode.light,
        home: HomeShell(
          store: widget.store,
          darkTheme: _dark,
          onThemeChanged: _setDark,
        ),
      );
}
