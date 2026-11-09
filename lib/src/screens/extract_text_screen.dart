import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models.dart';
import '../services/document_export.dart';
import '../services/docx_export.dart';
import '../theme.dart';

typedef ExtractTextRecognizer = Future<List<String>> Function(
    ScanDocument document, bool bengali);

/// The Tools > Extract Text flow works independently of the document image
/// editor. OCR, edits, copying, Word export and sharing all stay on-device
/// until the user deliberately chooses a sharing target.
class ExtractTextScreen extends StatefulWidget {
  const ExtractTextScreen({
    super.key,
    required this.document,
    this.recognizer,
  });

  final ScanDocument document;

  /// Allows deterministic tests without invoking the phone's OCR runtime.
  final ExtractTextRecognizer? recognizer;

  @override
  State<ExtractTextScreen> createState() => _ExtractTextScreenState();
}

class _ExtractTextScreenState extends State<ExtractTextScreen> {
  final _text = TextEditingController();
  final _focus = FocusNode();
  bool _bengali = false;
  bool _busy = false;
  String? _error;
  int _recognizedPages = 0;

  @override
  void initState() {
    super.initState();
    _text.text = widget.document.pages
        .map((page) => page.recognizedText.trim())
        .where((value) => value.isNotEmpty)
        .join('\n\n');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _recognize();
    });
  }

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _recognize() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final pages = await (widget.recognizer?.call(widget.document, _bengali)
          ?? DocxExport.recognizePageTexts(
            widget.document, bengali: _bengali, forceOcr: true));
      if (!mounted) return;
      final recognized = pages.where((page) => page.trim().isNotEmpty).toList();
      if (recognized.isEmpty) {
        throw const FormatException('No readable text found. Try a clearer scan.');
      }
      setState(() {
        _text.text = recognized.join('\n\n');
        _recognizedPages = recognized.length;
      });
    } catch (error) {
      if (mounted) setState(() => _error = 'OCR could not finish: $error');
      // Keep any previous text/hand edits available if OCR fails.
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _copy() async {
    if (_text.text.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: _text.text));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Text copied to clipboard')));
    }
  }

  void _selectAll() {
    _focus.requestFocus();
    _text.selection = TextSelection(
      baseOffset: 0, extentOffset: _text.text.length);
  }

  Future<void> _perform(Future<void> Function() action) async {
    if (_busy || _text.text.trim().isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } catch (error) {
      if (mounted) setState(() => _error = 'Export failed: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _toWord() => _perform(() async {
    final file = await DocxExport.createFromText(
        widget.document.name, _text.text);
    await DocxExport.shareFile(file, widget.document.name);
  });

  Future<void> _share() => _perform(() =>
      DocumentExport.shareText(_text.text, widget.document.name));

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Extract Text'), actions: [
      IconButton(
        tooltip: 'Recognize again',
        icon: const Icon(Icons.refresh_outlined),
        onPressed: _busy ? null : _recognize,
      ),
    ]),
    body: SafeArea(child: Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(widget.document.name, maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          SegmentedButton<bool>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: false, label: Text('English / Latin')),
              ButtonSegment(value: true, label: Text('বাংলা / Bengali')),
            ],
            selected: {_bengali},
            onSelectionChanged: _busy ? null : (values) {
              setState(() => _bengali = values.first);
              _recognize();
            },
          ),
          const SizedBox(height: 8),
          Text(_recognizedPages == 0
              ? 'Recognize text from your document, then edit or export.'
              : 'Recognized $_recognizedPages page(s) • Text is editable',
              style: const TextStyle(fontSize: 12, color: dsMuted)),
        ]),
      ),
      if (_busy) const LinearProgressIndicator(color: dsTeal),
      if (_error != null)
        Padding(padding: const EdgeInsets.symmetric(
            horizontal: 16, vertical: 8),
          child: Text(_error!, style: TextStyle(
              color: Theme.of(context).colorScheme.error))),
      Expanded(child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
        child: TextField(
          key: const Key('extracted-text'),
          controller: _text,
          focusNode: _focus,
          onChanged: (_) => setState(() {}),
          keyboardType: TextInputType.multiline,
          textAlignVertical: TextAlignVertical.top,
          expands: true,
          maxLines: null,
          minLines: null,
          decoration: InputDecoration(
            hintText: _busy ? 'Recognizing text on your device…'
                : 'Recognized text appears here. Tap to edit.',
            filled: true,
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none),
          ),
        ),
      )),
      Padding(padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: Column(children: [
          Row(children: [
            Expanded(child: OutlinedButton.icon(
              onPressed: _busy || _text.text.isEmpty ? null : _copy,
              icon: const Icon(Icons.copy_outlined),
              label: const Text('Copy'),
            )),
            const SizedBox(width: 10),
            Expanded(child: OutlinedButton.icon(
              onPressed: _busy || _text.text.isEmpty ? null : _selectAll,
              icon: const Icon(Icons.select_all_outlined),
              label: const Text('Select All'),
            )),
          ]),
          Row(children: [
            Expanded(child: FilledButton.icon(
              key: const Key('extract-to-word'),
              onPressed: _busy || _text.text.trim().isEmpty ? null : _toWord,
              icon: const Icon(Icons.description_outlined),
              label: const Text('To Word'),
            )),
            const SizedBox(width: 10),
            Expanded(child: FilledButton.icon(
              onPressed: _busy || _text.text.trim().isEmpty ? null : _share,
              icon: const Icon(Icons.share_outlined),
              label: const Text('Share Text'),
            )),
          ]),
        ]),
      ),
    ])),
  );
}
