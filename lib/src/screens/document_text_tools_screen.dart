import 'package:flutter/material.dart';

import '../models.dart';
import '../services/docx_export.dart';
import '../services/document_export.dart';
import '../theme.dart';

enum DocumentTextTool { translate, quiz, formulas, read }

/// Offline text-based tools. Translation is handed to an app chosen by the
/// user; the scanner itself never transmits the text to a server.
class DocumentTextToolsScreen extends StatefulWidget {
  const DocumentTextToolsScreen({super.key, required this.document, required this.tool});
  final ScanDocument document;
  final DocumentTextTool tool;

  @override
  State<DocumentTextToolsScreen> createState() => _DocumentTextToolsScreenState();
}

class _DocumentTextToolsScreenState extends State<DocumentTextToolsScreen> {
  late final Future<String> _text = _loadText();
  double _fontSize = 17;

  Future<String> _loadText() async {
    final pages = await DocxExport.recognizePageTexts(widget.document);
    final original = pages.join('\n\n');
    switch (widget.tool) {
      case DocumentTextTool.read:
      case DocumentTextTool.translate:
        return original;
      case DocumentTextTool.formulas:
        final matches = RegExp(
          r'[^\n]*[=+×÷√∑∫<>≤≥][^\n]*',
        ).allMatches(original).map((m) => m.group(0)!.trim()).where(
          (line) => line.length > 2,
        ).toSet();
        return matches.isEmpty
            ? 'No recognizable mathematical formulas found.'
            : matches.join('\n\n');
      case DocumentTextTool.quiz:
        final sentences = original.split(RegExp(r'[.!?\n]+'))
            .map((text) => text.trim())
            .where((text) => text.split(' ').length >= 5)
            .take(12);
        final quiz = <String>[];
        var index = 1;
        for (final sentence in sentences) {
          final words = RegExp(r'[A-Za-z]{5,}').allMatches(sentence)
              .map((m) => m.group(0)!).toList();
          if (words.isEmpty) continue;
          words.sort((a, b) => b.length.compareTo(a.length));
          quiz.add('$index. ${sentence.replaceFirst(words.first, '________')}\n'
              'Answer: ${words.first}');
          index++;
        }
        return quiz.isEmpty
            ? 'Not enough recognizable sentences to make a fill-in-the-blank quiz.'
            : quiz.join('\n\n');
    }
  }

  String get _title => switch (widget.tool) {
    DocumentTextTool.translate => 'Translate',
    DocumentTextTool.quiz => 'Create Quiz',
    DocumentTextTool.formulas => 'Extract Formulas',
    DocumentTextTool.read => 'Read Mode',
  };

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(_title), actions: [
      if (widget.tool == DocumentTextTool.read)
        IconButton(
          tooltip: 'Increase text size',
          onPressed: () => setState(() =>
              _fontSize = (_fontSize + 2).clamp(12, 32).toDouble()),
          icon: const Icon(Icons.text_increase),
        ),
    ]),
    body: FutureBuilder<String>(
      future: _text,
      builder: (context, snapshot) {
        if (snapshot.hasError) return Center(child: Padding(
          padding: const EdgeInsets.all(20), child: Text('${snapshot.error}'),
        ));
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator(color: dsTeal));
        }
        final content = snapshot.data!;
        return SafeArea(child: Column(children: [
          if (widget.tool == DocumentTextTool.quiz)
            const Padding(padding: EdgeInsets.all(12), child: Text(
              'Practice questions generated on your device from recognized text. '
              'Answers are shown below each question.',
            )),
          if (widget.tool == DocumentTextTool.translate)
            const Padding(padding: EdgeInsets.all(12), child: Text(
              'Choose an installed translation app using Share Text. '
              'Translation is not performed inside DocScanner.',
            )),
          Expanded(child: SingleChildScrollView(
            padding: const EdgeInsets.all(18),
            child: SelectableText(content, style: TextStyle(fontSize: _fontSize,
                height: 1.5)),
          )),
          Padding(padding: const EdgeInsets.all(14), child: SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () => DocumentExport.shareText(content, _title),
              icon: const Icon(Icons.share_outlined),
              label: Text(widget.tool == DocumentTextTool.translate
                  ? 'Share text to translation app' : 'Share Text'),
            ),
          )),
        ]));
      },
    ),
  );
}
