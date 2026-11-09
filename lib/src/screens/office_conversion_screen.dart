import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../models.dart';
import '../services/ai_document_vision_gateway.dart';
import '../services/ai_text_gateway.dart';
import '../services/docx_export.dart';
import '../services/xlsx_export.dart';
import 'excel_review_screen.dart';
import 'video_tool_style.dart';
import 'word_review_screen.dart';

/// Local OCR -> editable review -> genuine Office file -> Android share sheet.
/// Selecting/recognizing here never rewrites the original document pages.
class OfficeConversionScreen extends StatefulWidget {
  const OfficeConversionScreen({super.key, required this.document,
      required this.toExcel, this.onTagsChanged, this.visionEngine,
      this.localRecognizer, this.prepareAiPage});

  final ScanDocument document;
  final bool toExcel;
  final Future<void> Function(List<String>)? onTagsChanged;
  final AiDocumentVisionEngine? visionEngine;
  final Future<List<String>> Function(ScanDocument, bool)? localRecognizer;
  final Future<Uint8List> Function(String)? prepareAiPage;

  @override
  State<OfficeConversionScreen> createState() => _OfficeConversionScreenState();
}

class _OfficeConversionScreenState extends State<OfficeConversionScreen> {
  final Set<String> _selected = {};
  final Map<String, TextEditingController> _editors = {};
  bool _bengali = false;
  bool _recognized = false;
  bool _busy = false;
  bool _usingOnlineAi = false;
  int _aiPageNumber = 0;
  String? _currentPageId;
  late final AiDocumentVisionEngine _vision =
      widget.visionEngine ?? AiDocumentVisionGateway();

  List<ScanPage> get _pages => widget.document.pages
      .where((page) => _selected.contains(page.id)).toList();

  @override
  void initState() {
    super.initState();
    for (final page in widget.document.pages) {
      _selected.add(page.id);
      _editors[page.id] = TextEditingController(text: page.recognizedText);
    }
    _currentPageId = widget.document.pages.firstOrNull?.id;
  }

  @override
  void dispose() {
    for (final editor in _editors.values) {
      editor.dispose();
    }
    super.dispose();
  }

  void _togglePage(String id) {
    if (_busy) return;
    setState(() {
      if (_selected.contains(id)) {
        if (_selected.length == 1) return;
        _selected.remove(id);
      } else {
        _selected.add(id);
      }
      if (!_selected.contains(_currentPageId)) _currentPageId = _pages.first.id;
      _recognized = false; // Selection changed: OCR may now be incomplete.
    });
  }

  Future<void> _recognize() async {
    if (_busy || _pages.isEmpty) return;
    final selectedPages = _pages;
    final selectedDocument = widget.document.copyWith(pages: selectedPages);
    AiTextConfig? config;
    try {
      config = await _vision.activeConfiguration();
    } catch (_) {
      // Locked or unavailable secure storage must not disable offline OCR.
      config = null;
    }
    final activeConfig = config;
    if (!mounted) return;
    bool useAi = false;
    if (activeConfig != null) {
      final choice = await showDialog<bool>(context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Improve accuracy with AI vision?'),
          content: Text('AI can read the original scanned image, including '
            'table columns and rows. Sending ${selectedPages.length} selected '
            'page image(s) to ${activeConfig.providerName} (${activeConfig.modelId}) '
            'requires internet and may use paid API credits. The images '
            'will be sent only if you choose Use AI. Check the transcription '
            'carefully; AI can still misread numbers.'),
          actions: [
            TextButton(key: const Key('office-ai-cancel'),
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel')),
            TextButton(key: const Key('office-ai-local'),
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('On-device only')),
            FilledButton(key: const Key('office-ai-send'),
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Use AI')),
          ],
        ),
      );
      if (!mounted || choice == null) return;
      useAi = choice;
    }
    setState(() {
      _busy = true;
      _usingOnlineAi = useAi;
      _aiPageNumber = 0;
    });
    List<String>? reviewTexts;
    try {
      final List<String> texts;
      if (useAi) {
        texts = [];
        for (var i = 0; i < selectedPages.length; i++) {
          if (mounted) setState(() => _aiPageNumber = i + 1);
          final image = await (widget.prepareAiPage ?? AiPageImage.prepare)(
            selectedPages[i].path);
          final text = await _vision.transcribe(config: activeConfig!,
            format: widget.toExcel ? AiDocumentFormat.excel
                : AiDocumentFormat.word, jpeg: image);
          texts.add(text);
        }
      } else {
        texts = await (widget.localRecognizer?.call(selectedDocument, _bengali)
            ?? DocxExport.recognizePageTexts(selectedDocument,
              bengali: _bengali, forceOcr: true));
      }
      if (!mounted) return;
      for (var i = 0; i < selectedPages.length; i++) {
        _editors[selectedPages[i].id]!.text = texts[i];
      }
      reviewTexts = texts;
      setState(() {
        _recognized = false;
        _currentPageId = selectedPages.first.id;
      });
    } catch (error) {
      if (mounted) {
        final message = error is AiTextException ? error.message
            : error is FormatException ? error.message
                : 'Could not recognize selected pages. Try on-device OCR '
                  'or a clearer scan.';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(message),
        ));
      }
    } finally {
      if (mounted) setState(() { _busy = false; _usingOnlineAi = false; });
    }
    if (!mounted || reviewTexts == null) return;
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => widget.toExcel
          ? ExcelReviewScreen(document: selectedDocument,
              pageTexts: reviewTexts!, onTagsChanged: widget.onTagsChanged)
          : WordReviewScreen(document: selectedDocument,
              pageTexts: reviewTexts!, onTagsChanged: widget.onTagsChanged),
    ));
  }

  Future<void> _export() async {
    if (_busy || !_recognized) return;
    final texts = _pages.map((page) => _editors[page.id]!.text).toList();
    if (texts.every((text) => text.trim().isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Enter or recognize some text before exporting.'),
      ));
      return;
    }
    setState(() => _busy = true);
    try {
      final File result = widget.toExcel
          ? await XlsxExport.createFromPageTexts(widget.document.name, texts)
          : await DocxExport.createFromPageTexts(widget.document.name, texts);
      if (!mounted) return;
      if (widget.toExcel) {
        await XlsxExport.shareFile(result, widget.document.name);
      } else {
        await DocxExport.shareFile(result, widget.document.name);
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Office export failed: $error'),
        ));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _pageChooser() => SizedBox(height: 150, child: ListView.separated(
    scrollDirection: Axis.horizontal,
    padding: const EdgeInsets.symmetric(horizontal: 18),
    itemCount: widget.document.pages.length,
    separatorBuilder: (_, _) => const SizedBox(width: 12),
    itemBuilder: (context, index) {
      final page = widget.document.pages[index];
      final selected = _selected.contains(page.id);
      final current = _recognized && _currentPageId == page.id;
      return InkWell(
        key: Key('office-page-${page.id}'),
        onTap: _recognized && selected
            ? () => setState(() => _currentPageId = page.id)
            : () => _togglePage(page.id),
        onLongPress: () => _togglePage(page.id),
        child: Container(width: 105, padding: const EdgeInsets.all(5),
          decoration: BoxDecoration(
            color: VideoToolStyle.tile,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: current || selected
                ? VideoToolStyle.teal : Colors.transparent,
                width: current ? 2.2 : 1.2),
          ),
          child: Column(children: [
            Expanded(child: Stack(fit: StackFit.expand, children: [
              ClipRRect(borderRadius: BorderRadius.circular(9),
                child: Image.file(File(page.path), fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => const Icon(Icons.description,
                      size: 42, color: VideoToolStyle.muted))),
              Positioned(right: 4, top: 4, child: CircleAvatar(radius: 12,
                backgroundColor: selected ? VideoToolStyle.teal : Colors.black54,
                child: Icon(selected ? Icons.check : Icons.add,
                  size: 15, color: Colors.white))),
            ])),
            const SizedBox(height: 5),
            Text('Page ${index + 1}', style: const TextStyle(fontSize: 12)),
          ]),
        ),
      );
    },
  ));

  static List<List<String>> parseTablePreview(String text) => text
      .split(RegExp(r'\r?\n'))
      .where((line) => line.trim().isNotEmpty)
      .take(8)
      .map(XlsxExport.cellsFromLine)
      .toList();

  Widget _tablePreview(String text) {
    final rows = parseTablePreview(text);
    if (rows.isEmpty) return const Text('No table rows yet.');
    final count = rows.fold<int>(1, (max, cells) =>
        cells.length > max ? cells.length : max).clamp(1, 6).toInt();
    return SingleChildScrollView(scrollDirection: Axis.horizontal,
      child: DataTable(
        columnSpacing: 20,
        headingRowHeight: 35,
        dataRowMinHeight: 34,
        dataRowMaxHeight: 46,
        columns: List.generate(count, (index) => DataColumn(
          label: Text('Column ${index + 1}',
              style: const TextStyle(fontSize: 11)),
        )),
        rows: rows.map((cells) => DataRow(cells: List.generate(count,
          (index) => DataCell(SizedBox(width: 100,
            child: Text(index < cells.length ? cells[index] : '',
                maxLines: 2, overflow: TextOverflow.ellipsis))),
        ))).toList(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final excel = widget.toExcel;
    final title = excel ? 'To Excel' : 'To Word';
    final currentText = _editors[_currentPageId]?.text ?? '';
    return Theme(data: VideoToolStyle.dark, child: Scaffold(
      appBar: AppBar(title: Text(title), actions: [
        if (_recognized) TextButton.icon(
          onPressed: _busy ? null : _recognize,
          icon: const Icon(Icons.refresh, size: 18),
          label: const Text('Re-OCR'),
        ),
      ]),
      body: Stack(children: [SafeArea(child: Column(children: [
        if (_busy) const LinearProgressIndicator(color: VideoToolStyle.teal),
        Expanded(child: ListView(children: [
          Container(padding: const EdgeInsets.fromLTRB(20, 20, 20, 22),
            color: VideoToolStyle.header,
            child: Row(children: [
              Container(width: 64, height: 64,
                decoration: BoxDecoration(
                    color: VideoToolStyle.teal.withValues(alpha: .13),
                    borderRadius: BorderRadius.circular(18)),
                child: Icon(excel ? Icons.table_chart : Icons.description,
                    size: 33, color: VideoToolStyle.teal)),
              const SizedBox(width: 15),
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Convert to editable ${excel ? 'Excel' : 'Word'}',
                    style: const TextStyle(fontSize: 19,
                        fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                Text(widget.document.name, maxLines: 2,
                    style: const TextStyle(color: VideoToolStyle.muted)),
              ])),
            ]),
          ),
          const SizedBox(height: 20),
          Padding(padding: const EdgeInsets.symmetric(horizontal: 18),
            child: Row(children: [
              const Expanded(child: Text('Select pages',
                  style: TextStyle(fontSize: 17,
                      fontWeight: FontWeight.w700))),
              Text('${_selected.length} selected',
                  style: const TextStyle(color: VideoToolStyle.teal)),
            ])),
          const SizedBox(height: 12),
          _pageChooser(),
          const SizedBox(height: 18),
          Padding(padding: const EdgeInsets.symmetric(horizontal: 18),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Recognition language',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                const SizedBox(height: 10),
                Row(children: [
                  _languageChip('English / Latin', !_bengali, () => setState(() {
                    _bengali = false; _recognized = false;
                  })),
                  const SizedBox(width: 10),
                  _languageChip('বাংলা / Bengali', _bengali, () => setState(() {
                    _bengali = true; _recognized = false;
                  })),
                ]),
                const SizedBox(height: 11),
                const Text('Offline OCR stays on this device. If AI Mode is '
                    'enabled, you can choose image-based AI recognition with '
                    'separate consent. Always review names, dates and numbers.',
                  style: TextStyle(color: VideoToolStyle.muted, fontSize: 12)),
                if (_recognized) ...[
                  const SizedBox(height: 24),
                  const Text('Review & edit', style: TextStyle(
                      fontSize: 17, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  Text('Page ${widget.document.pages.indexWhere(
                      (page) => page.id == _currentPageId) + 1} · '
                      'Tap a selected thumbnail to switch pages.',
                    style: const TextStyle(color: VideoToolStyle.muted,
                        fontSize: 12)),
                  const SizedBox(height: 12),
                  TextField(
                    key: ValueKey('office-text-$_currentPageId'),
                    controller: _editors[_currentPageId],
                    minLines: 8, maxLines: 16,
                    keyboardType: TextInputType.multiline,
                    decoration: InputDecoration(
                      hintText: 'Edit recognized text here…',
                      filled: true,
                      fillColor: VideoToolStyle.tile,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16)),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                  if (excel) ...[
                    const SizedBox(height: 18),
                    const Text('Table preview', style: TextStyle(
                        fontSize: 17, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 5),
                    const Text('Separate columns with Tab or two spaces. '
                        'Check rows and columns before export.',
                      style: TextStyle(color: VideoToolStyle.muted,
                          fontSize: 12)),
                    const SizedBox(height: 10),
                    _tablePreview(currentText),
                  ],
                ],
              ],
            )),
          const SizedBox(height: 24),
        ])),
        Container(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 14),
          decoration: const BoxDecoration(color: VideoToolStyle.header,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
          child: SafeArea(top: false, child: SizedBox(width: double.infinity,
            child: FilledButton.icon(
              key: const Key('office-primary-action'),
              onPressed: _busy || _pages.isEmpty ? null :
                  (_recognized ? _export : _recognize),
              style: VideoToolStyle.tealButton,
              icon: Icon(_recognized ? Icons.ios_share : Icons.document_scanner),
              label: Text(_busy ? 'Processing…' : _recognized
                  ? 'Export ${excel ? 'XLSX' : 'DOCX'}'
                  : 'Recognize & Preview'),
            ),
          )),
        ),
      ])),
      if (_busy) Positioned.fill(child: ColoredBox(
        color: const Color(0xEB1A1A1D),
        child: Column(mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Stack(alignment: Alignment.center, children: [
              SizedBox(width: 92, height: 92,
                child: CircularProgressIndicator(
                  color: VideoToolStyle.teal, strokeWidth: 3)),
              Icon(Icons.auto_awesome, color: VideoToolStyle.teal,
                size: 38),
            ]),
            const SizedBox(height: 23),
            Text(_usingOnlineAi ? 'Reading page $_aiPageNumber with AI'
                : 'Recognizing on device', style: const TextStyle(
              color: Colors.white, fontSize: 19,
              fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Text(_usingOnlineAi
                ? 'Image sent only after your approval'
                : 'Private, on-device text recognition',
              style: const TextStyle(color: VideoToolStyle.muted, fontSize: 12)),
          ]),
      )),
      ]),
    ));
  }

  Widget _languageChip(String label, bool selected, VoidCallback onTap) =>
      Expanded(child: OutlinedButton(
        onPressed: _busy ? null : onTap,
        style: OutlinedButton.styleFrom(
          backgroundColor: selected ? VideoToolStyle.teal.withValues(alpha: .20)
              : VideoToolStyle.tile,
          side: BorderSide(color: selected ? VideoToolStyle.teal
              : Colors.transparent),
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 14),
        ),
        child: Text(label, style: const TextStyle(fontSize: 12)),
      ));
}
