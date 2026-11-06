import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tesseract_ocr/flutter_tesseract_ocr.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import '../services/document_export.dart';
import '../storage/document_store.dart';
import '../theme.dart';
import 'image_text_editor_screen.dart';

class EditTextScreen extends StatefulWidget {
  const EditTextScreen({
    super.key,
    required this.store,
    required this.documentId,
    required this.pageId,
  });

  final DocumentStore store;
  final String documentId;
  final String pageId;

  @override
  State<EditTextScreen> createState() => _EditTextScreenState();
}

class _EditTextScreenState extends State<EditTextScreen>
    with SingleTickerProviderStateMixin {
  final _text = TextEditingController();
  late final AnimationController _pulse;
  bool _processing = false;
  String? _error;
  int _blocks = 0;
  bool _bengali = false;
  List<DetectedTextRegion> _regions = [];

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
      lowerBound: .78,
      upperBound: 1.08,
    )..repeat(reverse: true);
    final doc = widget.store.byId(widget.documentId);
    if (doc != null) {
      for (final page in doc.pages) {
        if (page.id == widget.pageId) _text.text = page.recognizedText;
      }
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _recognize());
  }

  @override
  void dispose() {
    _pulse.dispose();
    _text.dispose();
    super.dispose();
  }

  Future<void> _recognize() async {
    final doc = widget.store.byId(widget.documentId);
    if (doc == null) return;
    final page = doc.pages.where((p) => p.id == widget.pageId).firstOrNull;
    if (page == null) return;
    setState(() {
      _error = null;
      _processing = true;
    });
    try {
      if (_bengali) {
        // Tesseract + bundled ben.traineddata: works offline without ML Kit
        // downloads. Word boxes are not provided by this plugin.
        final recognized = await FlutterTesseractOcr.extractText(
          page.path,
          language: 'ben',
          args: const {'psm': '3', 'preserve_interword_spaces': '1'},
        );
        if (!mounted) return;
        setState(() {
          _text.text = recognized.trim().isNotEmpty ? recognized.trim() : _text.text;
          _blocks = recognized.trim().isEmpty ? 0 : recognized.split('\n').length;
          _regions = [];
        });
      } else {
        final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
        try {
          final recognized = await recognizer.processImage(InputImage.fromFilePath(page.path));
          final data = await File(page.path).readAsBytes();
          final codec = await ui.instantiateImageCodec(data);
          final frame = await codec.getNextFrame();
          final width = frame.image.width.toDouble();
          final height = frame.image.height.toDouble();
          frame.image.dispose();
          codec.dispose();
          if (!mounted) return;
          setState(() {
            _text.text = recognized.text.isNotEmpty ? recognized.text : _text.text;
            _blocks = recognized.blocks.length;
            _regions = [
              for (final block in recognized.blocks)
                for (final line in block.lines)
                  DetectedTextRegion(
                    Rect.fromLTRB(
                      (line.boundingBox.left / width).clamp(0.0, 1.0),
                      (line.boundingBox.top / height).clamp(0.0, 1.0),
                      (line.boundingBox.right / width).clamp(0.0, 1.0),
                      (line.boundingBox.bottom / height).clamp(0.0, 1.0),
                    ),
                    line.text,
                  ),
            ];
          });
        } finally {
          await recognizer.close();
        }
      }
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  Future<void> _save() async {
    await widget.store.updatePageText(widget.documentId, widget.pageId, _text.text);
    if (mounted) Navigator.pop(context);
  }

  Future<void> _editImage() async {
    await Navigator.push<void>(context, MaterialPageRoute(
      builder: (_) => ImageTextEditorScreen(
        store: widget.store,
        documentId: widget.documentId,
        pageId: widget.pageId,
        regions: _regions,
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit Text'),
        actions: [
          if (!_processing)
            TextButton(onPressed: _save, child: const Text('Done',
                style: TextStyle(fontWeight: FontWeight.bold, color: dsTeal))),
        ],
      ),
      body: SafeArea(child: _processing
          ? Center(child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ScaleTransition(
                  scale: _pulse,
                  child: Container(
                    width: 130, height: 130,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: dsTeal.withValues(alpha: .10),
                      border: Border.all(color: dsTeal.withValues(alpha: .45), width: 2),
                    ),
                    child: const Icon(Icons.auto_awesome, size: 65, color: dsTeal),
                  ),
                ),
                const SizedBox(height: 32),
                const Text('DS AI PROSINESS',
                    style: TextStyle(fontSize: 23, letterSpacing: 1.7, fontWeight: FontWeight.w900)),
                const SizedBox(height: 8),
                const Text('Recognizing document text on your device'),
                const SizedBox(height: 25),
                const SizedBox(width: 180, child: LinearProgressIndicator(color: dsTeal)),
              ],
            ))
          : Column(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
                child: Row(children: [
                  Expanded(child: SegmentedButton<bool>(
                    showSelectedIcon: false,
                    selected: {_bengali},
                    onSelectionChanged: (selection) {
                      setState(() => _bengali = selection.first);
                      _recognize();
                    },
                    segments: const [
                      ButtonSegment(value: false, label: Text('English')),
                      ButtonSegment(value: true, label: Text('বাংলা')),
                    ],
                  )),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: _editImage,
                    icon: const Icon(Icons.image_search_outlined),
                    label: const Text('On Image'),
                  ),
                ]),
              ),
              Container(
                width: double.infinity,
                color: dsTeal.withValues(alpha: .08),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Text(
                  _error != null ? 'Recognition unavailable: $_error'
                      : _bengali
                          ? 'বাংলা OCR: $_blocks lines • Add text on image manually'
                          : '$_blocks text blocks detected • Tap On Image to edit on the page',
                  style: const TextStyle(fontSize: 12),
                ),
              ),
              Expanded(child: Padding(
                padding: const EdgeInsets.all(16),
                child: TextField(
                  controller: _text,
                  keyboardType: TextInputType.multiline,
                  expands: true,
                  maxLines: null,
                  minLines: null,
                  textAlignVertical: TextAlignVertical.top,
                  decoration: InputDecoration(
                    hintText: 'Recognized text will appear here...',
                    filled: true,
                    fillColor: theme.colorScheme.surface,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              )),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: Row(children: [
                  OutlinedButton.icon(
                    onPressed: _recognize,
                    icon: const Icon(Icons.refresh), label: const Text('Re-scan'),
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: 'Copy text', icon: const Icon(Icons.copy_outlined),
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: _text.text));
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Copied to clipboard')));
                      }
                    },
                  ),
                  IconButton(
                    tooltip: 'Share text', icon: const Icon(Icons.share_outlined),
                    onPressed: () => DocumentExport.shareText(_text.text, 'DocScanner text'),
                  ),
                ]),
              ),
            ])),
    );
  }
}
