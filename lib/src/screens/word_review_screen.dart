import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

import '../models.dart';
import '../services/docx_export.dart';
import 'video_tool_style.dart';

/// Video-inspired Word review with *real* offline text editing and export.
/// All CS reference branding is replaced by DS; no remote AI is invoked.
class WordReviewScreen extends StatefulWidget {
  const WordReviewScreen({super.key, required this.document,
    required this.pageTexts, this.onTagsChanged});

  final ScanDocument document;
  final List<String> pageTexts;
  final Future<void> Function(List<String>)? onTagsChanged;

  @override
  State<WordReviewScreen> createState() => _WordReviewScreenState();
}

class _WordReviewScreenState extends State<WordReviewScreen> {
  late List<String> _texts;
  final List<List<String>> _undo = [];
  final List<List<String>> _redo = [];
  int _page = 0;
  int _textSize = 1;
  int _lineSpacing = 1;
  bool _oneTapFormat = false;
  bool _showOriginal = false;
  bool _busy = false;
  late List<String> _tags;

  @override
  void initState() {
    super.initState();
    _texts = List.of(widget.pageTexts);
    _tags = List.of(widget.document.tags);
  }

  String get _current => _texts[_page];
  int get _characters => _texts.fold(0, (sum, text) => sum + text.length);
  double get _fontSize => [13.0, 15.0, 18.0][_textSize];
  double get _lineHeight => [1.22, 1.52, 1.85][_lineSpacing];

  void _commit(List<String> next) {
    if (_texts.join('\u0000') == next.join('\u0000')) return;
    setState(() {
      _undo.add(List.of(_texts));
      if (_undo.length > 30) _undo.removeAt(0);
      _redo.clear();
      _texts = next;
    });
  }

  void _restore({required bool undo}) {
    final from = undo ? _undo : _redo;
    final to = undo ? _redo : _undo;
    if (from.isEmpty) return;
    setState(() {
      to.add(List.of(_texts));
      _texts = from.removeLast();
    });
  }

  Future<void> _editCurrent() async {
    if (_busy) return;
    final controller = TextEditingController(text: _current);
    final updated = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: VideoToolStyle.panel,
      shape: const RoundedRectangleBorder(borderRadius:
        BorderRadius.vertical(top: Radius.circular(22))),
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(sheetContext).bottom),
        child: SafeArea(top: false, child: SizedBox(
          height: (MediaQuery.sizeOf(sheetContext).height -
              MediaQuery.viewInsetsOf(sheetContext).bottom) * .78,
          child: Column(children: [
            Padding(padding: const EdgeInsets.fromLTRB(18, 12, 12, 8),
              child: Row(children: [
                const Expanded(child: Text('Edit text', style: TextStyle(
                  fontSize: 19, fontWeight: FontWeight.bold,
                  color: Colors.white))),
                TextButton(onPressed: () => Navigator.pop(sheetContext),
                    child: const Text('Cancel')),
                FilledButton(key: const Key('word-apply-edit'),
                  onPressed: () => Navigator.pop(sheetContext, controller.text),
                  child: const Text('Done')),
              ])),
            Expanded(child: Padding(padding: const EdgeInsets.all(14),
              child: TextField(
                key: const Key('word-edit-field'),
                controller: controller,
                autofocus: true,
                expands: true, minLines: null, maxLines: null,
                textAlignVertical: TextAlignVertical.top,
                decoration: const InputDecoration(
                  filled: true, fillColor: Color(0xFFF9F9FA),
                  hintText: 'Edit recognized text',
                  border: OutlineInputBorder()),
                style: const TextStyle(color: Colors.black87, fontSize: 15),
              ))),
            const Padding(padding: EdgeInsets.fromLTRB(18, 0, 18, 12),
              child: Text('Changes are local until you share or export.',
                style: TextStyle(color: VideoToolStyle.muted, fontSize: 12))),
          ]),
        )),
      ),
    );
    controller.dispose();
    if (!mounted || updated == null) return;
    final next = List<String>.of(_texts)..[_page] = updated;
    _commit(next);
  }

  Future<void> _run(Future<void> Function() task) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await task();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Could not share document: $error')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _shareWord() => _run(() async {
    final file = await DocxExport.createFromPageTexts(
        widget.document.name, _texts);
    await DocxExport.shareFile(file, widget.document.name);
  });

  Future<void> _sharePdf() => _run(() async {
    if (_texts.every((text) => text.trim().isEmpty)) {
      throw const FormatException('There is no text to export.');
    }
    // Core PDF fonts lack Bengali/other Unicode glyphs. Do not silently
    // generate unreadable text: DOCX supports these scripts without loss.
    if (_texts.any((text) => text.runes.any((rune) => rune > 255))) {
      throw const FormatException('Text PDF currently supports Latin script. '
          'Use Share as Word for বাংলা or other Unicode text.');
    }
    final pdf = pw.Document();
    for (final text in _texts) {
      pdf.addPage(pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(45),
        build: (_) => [pw.Text(text,
          style: pw.TextStyle(fontSize: _fontSize,
            lineSpacing: (_lineHeight - 1) * _fontSize))],
      ));
    }
    final temp = await getTemporaryDirectory();
    final file = File(p.join(temp.path,
      'ds_word_${DateTime.now().microsecondsSinceEpoch}.pdf'));
    await file.writeAsBytes(await pdf.save(), flush: true);
    await SharePlus.instance.share(ShareParams(
      files: [XFile(file.path, mimeType: 'application/pdf')],
      subject: widget.document.name));
  });

  Future<void> _shareOriginalImages() => _run(() async {
    final pages = widget.document.pages;
    if (pages.isEmpty || !pages.every((page) => File(page.path).existsSync())) {
      throw const FormatException('Original page images are missing.');
    }
    await SharePlus.instance.share(ShareParams(
      files: [for (final page in pages) XFile(page.path)],
      subject: '${widget.document.name} - original scan images'));
  });

  static String polishText(String value) => value
      .replaceAll(RegExp(r'[ \t]+'), ' ')
      .replaceAll(RegExp(r' *\n *'), '\n')
      .replaceAll(RegExp(r'\n{3,}'), '\n\n')
      .trim();

  static String proofreadText(String value) => value
      .replaceAll(RegExp(r'\bteh\b', caseSensitive: false), 'the')
      .replaceAll(RegExp(r'\badn\b', caseSensitive: false), 'and')
      .replaceAll(RegExp(r' +([,.;:!?])'), r'$1')
      .replaceAll(RegExp(r'([,.;:!?])([A-Za-z])'), r'$1 $2');

  void _applyWriting(String Function(String) operation) {
    final next = _texts.map(operation).toList(growable: false);
    _commit(next);
    Navigator.of(context).pop();
  }

  Future<void> _editTags() async {
    final controller = TextEditingController(text: _tags.join(', '));
    final tags = await showDialog<String>(context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Document tags'),
        content: TextField(controller: controller, autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Tags separated by commas',
            border: OutlineInputBorder())),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel')),
          FilledButton(onPressed: () =>
              Navigator.pop(dialogContext, controller.text),
            child: const Text('Save')),
        ],
      ));
    controller.dispose();
    if (!mounted || tags == null) return;
    final next = tags.split(',').map((tag) => tag.trim())
        .where((tag) => tag.isNotEmpty).toSet().toList();
    if (widget.onTagsChanged == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:
        Text('Open this document from Files to save tags.')));
      return;
    }
    await _run(() async {
      await widget.onTagsChanged!(next);
      if (mounted) setState(() => _tags = next);
    });
  }

  void _formattingSheet() => showModalBottomSheet<void>(
    context: context,
    backgroundColor: VideoToolStyle.panel,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => StatefulBuilder(builder: (context, updateSheet) {
      Widget segmented(List<String> choices, int index, ValueChanged<int> onTap) =>
          Container(decoration: BoxDecoration(color: const Color(0xFF424246),
            borderRadius: BorderRadius.circular(25)),
            child: Row(children: [for (var i = 0; i < choices.length; i++)
              Expanded(child: InkWell(onTap: () {
                onTap(i);
                updateSheet(() {});
              }, borderRadius: BorderRadius.circular(25),
                child: Container(padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    color: i == index ? VideoToolStyle.header : Colors.transparent,
                    borderRadius: BorderRadius.circular(25)),
                  child: Text(choices[i], textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white))))),
            ]));
      return SafeArea(top: false, child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 12, 22, 26),
        child: Column(mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('DS Formatting ✦', style: TextStyle(
            color: VideoToolStyle.teal, fontSize: 20,
            fontWeight: FontWeight.w600)),
          const SizedBox(height: 25),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: const Text('One-Tap Formatting',
              style: TextStyle(color: Colors.white, fontSize: 18)),
            subtitle: const Text('Use balanced font size and spacing',
              style: TextStyle(color: VideoToolStyle.muted)),
            activeTrackColor: VideoToolStyle.teal,
            value: _oneTapFormat,
            onChanged: (enabled) {
              setState(() {
                _oneTapFormat = enabled;
                if (enabled) { _textSize = 1; _lineSpacing = 1; }
              });
              updateSheet(() {});
            },
          ),
          const Divider(height: 29),
          const Text('Text Size', style: TextStyle(
              fontSize: 18, color: Colors.white)),
          const SizedBox(height: 16),
          segmented(['Small', 'Normal', 'Large'], _textSize, (value) =>
            setState(() { _textSize = value; _oneTapFormat = false; })),
          const Divider(height: 34),
          const Text('Line Spacing', style: TextStyle(
              fontSize: 18, color: Colors.white)),
          const SizedBox(height: 16),
          segmented(['Compact', 'Medium', 'Wide'], _lineSpacing, (value) =>
            setState(() { _lineSpacing = value; _oneTapFormat = false; })),
        ]),
      ));
    }),
  );

  void _writingSheet() => showModalBottomSheet<void>(
    context: context,
    backgroundColor: VideoToolStyle.panel,
    showDragHandle: true,
    builder: (context) => SafeArea(top: false, child: Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 23),
      child: Column(mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('DS Writing ✦', style: TextStyle(color: VideoToolStyle.teal,
            fontSize: 20, fontWeight: FontWeight.w600)),
        const SizedBox(height: 5),
        const Text('Local rule-based cleanup; no cloud AI or upload.',
          style: TextStyle(color: VideoToolStyle.muted, fontSize: 12)),
        const SizedBox(height: 19),
        ListTile(key: const Key('word-polish'),
          leading: const Icon(Icons.auto_fix_high, color: VideoToolStyle.teal),
          title: const Text('DS Polish'),
          subtitle: const Text('Normalize spacing and blank lines'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _applyWriting(polishText)),
        ListTile(key: const Key('word-proofread'),
          leading: const Icon(Icons.spellcheck, color: VideoToolStyle.teal),
          title: const Text('DS Proofread'),
          subtitle: const Text('Fix a few common typos and punctuation spaces'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _applyWriting(proofreadText)),
      ]),
    )),
  );

  void _shareSheet() => showModalBottomSheet<void>(
    context: context,
    backgroundColor: VideoToolStyle.panel,
    showDragHandle: true,
    builder: (context) => SafeArea(top: false, child: Padding(
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 26),
      child: Column(mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Share', style: TextStyle(color: Colors.white,
            fontSize: 21, fontWeight: FontWeight.w700)),
        const SizedBox(height: 12),
        ListTile(key: const Key('word-share-docx'),
          leading: const Icon(Icons.description, color: VideoToolStyle.teal),
          title: const Text('Share as Word'),
          subtitle: const Text('Editable DOCX with your changes'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () { Navigator.pop(context); _shareWord(); }),
        const Divider(),
        const Text('More Sharing Options', style: TextStyle(
            color: VideoToolStyle.muted)),
        ListTile(key: const Key('word-share-pdf'),
          leading: const Icon(Icons.picture_as_pdf_outlined,
            color: VideoToolStyle.teal),
          title: const Text('Share as PDF'),
          subtitle: const Text('Export edited text (Latin script)'),
          onTap: () { Navigator.pop(context); _sharePdf(); }),
        ListTile(key: const Key('word-share-images'),
          leading: const Icon(Icons.image_outlined,
              color: VideoToolStyle.teal),
          title: const Text('Share as Images'),
          subtitle: const Text('Share original scan images'),
          onTap: () { Navigator.pop(context); _shareOriginalImages(); }),
      ]),
    )),
  );

  Widget _action(IconData icon, String title, VoidCallback callback) =>
      Expanded(child: InkWell(onTap: _busy ? null : callback,
        child: Padding(padding: const EdgeInsets.symmetric(vertical: 9),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, color: Colors.white, size: 25),
            const SizedBox(height: 5),
            Text(title, textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontSize: 11)),
          ]))));

  Widget _paper() {
    final normalized = _current.replaceAll('\r\n', '\n').trim();
    final split = normalized.split('\n');
    final heading = split.firstOrNull ?? '';
    final treatAsHeading = heading.length <= 55 && split.length > 1;
    return Center(child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 620),
      child: Container(
        constraints: const BoxConstraints(minHeight: 720),
        color: Colors.white,
        child: Stack(children: [
          InkWell(key: const Key('word-page-preview'),
            onTap: _editCurrent,
            child: Padding(padding: const EdgeInsets.fromLTRB(44, 100, 44, 70),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (treatAsHeading) ...[
                    Text(heading, textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.black87,
                        fontSize: _fontSize + 1,
                        fontWeight: FontWeight.w600,
                        height: _lineHeight)),
                    const SizedBox(height: 44),
                  ],
                  Text(treatAsHeading ? split.skip(1).join('\n').trimLeft()
                      : normalized,
                    style: TextStyle(color: Colors.black87,
                      fontSize: _fontSize, height: _lineHeight)),
                  if (normalized.isEmpty) const Text('Tap to edit this page',
                    style: TextStyle(color: Colors.black54)),
                ],
              ]))),
          Positioned(left: 20, top: 30, child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
            color: const Color(0xFF4B4B4B),
            child: Text('${_page + 1}/${_texts.length}',
              style: const TextStyle(color: Colors.white)))),
        ]),
      ),
    ));
  }

  @override
  Widget build(BuildContext context) => Theme(data: VideoToolStyle.dark,
    child: Scaffold(backgroundColor: const Color(0xFFF3F3F3),
      appBar: AppBar(
        titleSpacing: 2,
        title: Text('To Word_${widget.document.name}',
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 18)),
        actions: [
          TextButton(onPressed: _editTags, child: Text(
            _tags.isEmpty ? 'Tags+' : 'Tags (${_tags.length})',
            style: const TextStyle(color: VideoToolStyle.muted))),
          PopupMenuButton<String>(
            onSelected: (choice) {
              if (choice == 'word') _shareWord();
              if (choice == 'pdf') _sharePdf();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'word', child: Text('Share as Word')),
              PopupMenuItem(value: 'pdf', child: Text('Save as PDF')),
            ],
          ),
        ],
      ),
      body: SafeArea(child: Column(children: [
        Container(color: VideoToolStyle.background,
          padding: const EdgeInsets.fromLTRB(15, 3, 7, 3),
          child: Row(children: [
            const Icon(Icons.info_outline, color: VideoToolStyle.muted,
              size: 20),
            const SizedBox(width: 8),
            Expanded(child: Text('Tap text to edit · $_characters characters',
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: VideoToolStyle.muted,
                fontSize: 12))),
            IconButton(tooltip: 'Undo', icon: const Icon(Icons.undo, size: 19),
              onPressed: _undo.isEmpty ? null : () => _restore(undo: true)),
            IconButton(tooltip: 'Redo', icon: const Icon(Icons.redo, size: 19),
              onPressed: _redo.isEmpty ? null : () => _restore(undo: false)),
          ])),
        if (_busy) const LinearProgressIndicator(color: VideoToolStyle.teal),
        Expanded(child: _showOriginal
          ? InteractiveViewer(child: Image.file(
              File(widget.document.pages[_page].path),
              fit: BoxFit.contain, errorBuilder: (_, _, _) =>
                const Center(child: Text('Original scan is unavailable'))))
          : ListView(children: [_paper()])),
        Container(color: VideoToolStyle.header,
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
          child: Row(children: [
            _viewToggle('Recognized Text', !_showOriginal, () =>
              setState(() => _showOriginal = false)),
            const SizedBox(width: 8),
            _viewToggle('Original Scan', _showOriginal, () =>
              setState(() => _showOriginal = true)),
            const Spacer(),
            if (_texts.length > 1) ...[
              IconButton(tooltip: 'Previous page',
                onPressed: _page > 0 ? () => setState(() => _page--) : null,
                icon: const Icon(Icons.chevron_left)),
              IconButton(tooltip: 'Next page',
                onPressed: _page < _texts.length - 1
                    ? () => setState(() => _page++) : null,
                icon: const Icon(Icons.chevron_right)),
            ],
          ])),
        Container(color: VideoToolStyle.header,
          child: Row(children: [
            _action(Icons.format_line_spacing, 'DS Formatting',
              _formattingSheet),
            _action(Icons.auto_fix_high, 'DS Writing', _writingSheet),
            _action(Icons.share_outlined, 'Share', _shareSheet),
            _action(Icons.picture_as_pdf_outlined, 'Save as PDF', _sharePdf),
          ])),
      ])),
    ));

  Widget _viewToggle(String label, bool active, VoidCallback action) =>
    OutlinedButton(onPressed: action,
      style: OutlinedButton.styleFrom(
        foregroundColor: active ? Colors.white : VideoToolStyle.muted,
        backgroundColor: active ? const Color(0xFF55555A) : Colors.transparent,
        side: BorderSide.none,
        padding: const EdgeInsets.symmetric(horizontal: 10)),
      child: Text(label, style: const TextStyle(fontSize: 12)));
}
