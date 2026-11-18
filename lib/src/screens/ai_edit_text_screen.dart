import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/ai_text_gateway.dart';
import '../services/image_text_processor.dart';
import '../storage/document_store.dart';
import '../theme.dart';
import 'ai_text_review_action.dart';

/// One recognized line of text, in normalized image coordinates.
class EditableTextLine {
  const EditableTextLine(this.bounds, this.text);
  final Rect bounds;
  final String text;
}

typedef TextLineRecognizer = Future<List<EditableTextLine>> Function(
    Uint8List bytes, Size imageSize);
typedef TextLineReplacer = Future<Uint8List> Function(
    Uint8List bytes, Rect area, String text);
typedef PageBytesSaver = Future<void> Function(Uint8List bytes);

/// CamScanner-style "Edit Text": DS AI analyses the page, the user taps a
/// line, edits it in a sheet, DS AI redraws it in the original style, and
/// nothing is written to the document until Save.
class AiEditTextScreen extends StatefulWidget {
  const AiEditTextScreen({
    super.key,
    required this.store,
    required this.documentId,
    required this.pageId,
    this.readBytes,
    this.recognize,
    this.replace,
    this.save,
    this.aiEngine,
    this.minAnalyzeTime = const Duration(milliseconds: 2400),
    this.minProcessTime = const Duration(milliseconds: 1200),
  });

  final DocumentStore store;
  final String documentId;
  final String pageId;

  /// Test hooks; the defaults use the page file, ML Kit and the store.
  final Future<Uint8List> Function(String path)? readBytes;
  final TextLineRecognizer? recognize;
  final TextLineReplacer? replace;
  final PageBytesSaver? save;
  final AiTextEngine? aiEngine;
  final Duration minAnalyzeTime;
  final Duration minProcessTime;

  static const skipSaveConfirmKey = 'ai_edit_text_skip_confirm_until';

  @override
  State<AiEditTextScreen> createState() => _AiEditTextScreenState();
}

enum _Phase { loading, analyzing, ready, processing }

class _Snapshot {
  const _Snapshot(this.bytes, this.lines);
  final Uint8List bytes;
  final List<EditableTextLine> lines;
}

class _AiEditTextScreenState extends State<AiEditTextScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _sweep = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1600))..repeat();
  _Phase _phase = _Phase.loading;
  Uint8List? _bytes;
  Size _size = const Size(1, 1);
  List<EditableTextLine> _lines = const [];
  final Set<int> _selected = {};
  final List<_Snapshot> _undo = [];
  final List<_Snapshot> _redo = [];
  Rect? _processingArea;
  String? _toast;
  Rect? _toastArea;
  Timer? _toastTimer;
  String? _error;

  bool get _dirty => _undo.isNotEmpty;
  int get _characters => _lines.isEmpty ? 0
      : _lines.fold<int>(0, (sum, line) => sum + line.text.length) +
          _lines.length - 1;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _toastTimer?.cancel();
    _sweep.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final page = widget.store.byId(widget.documentId)?.pages
        .where((page) => page.id == widget.pageId).firstOrNull;
    if (page == null) {
      setState(() => _error = 'Page not found');
      return;
    }
    try {
      final bytes = await (widget.readBytes ?? (path) => File(path).readAsBytes())(
          page.path);
      final info = img.findDecoderForData(bytes)?.startDecode(bytes);
      if (!mounted) return;
      setState(() {
        _bytes = bytes;
        if (info != null && info.width > 0 && info.height > 0) {
          _size = Size(info.width.toDouble(), info.height.toDouble());
        }
        _phase = _Phase.analyzing;
      });
      final results = await Future.wait([
        (widget.recognize ?? _recognizeWithMlKit)(bytes, _size),
        Future<void>.delayed(widget.minAnalyzeTime),
      ]);
      if (!mounted) return;
      _sweep.stop();
      setState(() {
        _lines = results.first! as List<EditableTextLine>;
        _phase = _Phase.ready;
      });
    } catch (_) {
      if (!mounted) return;
      _sweep.stop();
      setState(() {
        _lines = const [];
        _phase = _Phase.ready;
      });
      _showToast('Text recognition is unavailable on this device.');
    }
  }

  static Future<List<EditableTextLine>> _recognizeWithMlKit(
      Uint8List bytes, Size size) async {
    final dir = await getTemporaryDirectory();
    final file = File(p.join(dir.path,
        'ds_edit_text_${DateTime.now().microsecondsSinceEpoch}.png'));
    await file.writeAsBytes(bytes, flush: true);
    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      final result = await recognizer.processImage(
          InputImage.fromFilePath(file.path));
      return [
        for (final block in result.blocks)
          for (final line in block.lines)
            if (line.text.trim().isNotEmpty)
              EditableTextLine(Rect.fromLTRB(
                (line.boundingBox.left / size.width).clamp(0.0, 1.0),
                (line.boundingBox.top / size.height).clamp(0.0, 1.0),
                (line.boundingBox.right / size.width).clamp(0.0, 1.0),
                (line.boundingBox.bottom / size.height).clamp(0.0, 1.0),
              ), line.text),
      ];
    } finally {
      unawaited(recognizer.close().catchError((_) {}));
      unawaited(file.delete().then((_) {}, onError: (_) {}));
    }
  }

  void _showToast(String message, [Rect? area]) {
    _toastTimer?.cancel();
    setState(() {
      _toast = message;
      _toastArea = area;
    });
    _toastTimer = Timer(const Duration(milliseconds: 1800), () {
      if (mounted) setState(() => _toast = null);
    });
  }

  // ---------------------------------------------------------------- editing

  void _tapImage(Offset normalized) {
    if (_phase != _Phase.ready) return;
    var hit = -1;
    var best = double.infinity;
    for (var i = 0; i < _lines.length; i++) {
      final box = _lines[i].bounds.inflate(.012);
      if (box.contains(normalized)) {
        final d = (box.center - normalized).distance;
        if (d < best) {
          best = d;
          hit = i;
        }
      }
    }
    setState(() {
      _selected.clear();
      if (hit >= 0) _selected.add(hit);
    });
  }

  String get _selectedText => [
    for (final i in _selected.toList()..sort()) _lines[i].text,
  ].join('\n');

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: _selectedText));
    if (!mounted) return;
    setState(_selected.clear);
    _showToast('Copied');
  }

  void _selectAll() => setState(() {
    _selected
      ..clear()
      ..addAll(List.generate(_lines.length, (i) => i));
  });

  Future<void> _delete() async {
    final indexes = _selected.toList()..sort();
    if (indexes.isEmpty) return;
    await _process(indexes, [for (final _ in indexes) '']);
  }

  Future<void> _editLine(int index, {String? proposal}) async {
    final line = _lines[index];
    final text = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF242428),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(14))),
      builder: (sheet) => _EditTextSheet(
          original: line.text, initial: proposal ?? line.text),
    );
    if (text == null || text == line.text) return;
    await _process([index], [text]);
  }

  Future<void> _aiRewrite(int index, AiTextTask task) async {
    final proposal = await AiTextReviewAction.run(context,
        text: _lines[index].text, task: task, engine: widget.aiEngine);
    if (proposal == null || !mounted) return;
    await _editLine(index, proposal: proposal.trim().replaceAll('\n', ' '));
  }

  Future<void> _process(List<int> indexes, List<String> texts) async {
    final bytes = _bytes;
    if (bytes == null || indexes.isEmpty) return;
    final area = indexes.map((i) => _lines[i].bounds)
        .reduce((a, b) => a.expandToInclude(b));
    unawaited(_sweep.repeat());
    setState(() {
      _phase = _Phase.processing;
      _processingArea = area;
      _selected.clear();
    });
    try {
      final replace = widget.replace ??
          (bytes, area, text) => ImageTextProcessor.replaceLine(bytes,
              normalizedArea: area, replacement: text);
      final results = await Future.wait([
        () async {
          var current = bytes;
          for (var k = 0; k < indexes.length; k++) {
            current = await replace(current, _lines[indexes[k]].bounds,
                texts[k]);
          }
          return current;
        }(),
        Future<void>.delayed(widget.minProcessTime),
      ]);
      if (!mounted) return;
      _sweep.stop();
      final updated = <EditableTextLine>[];
      for (var i = 0; i < _lines.length; i++) {
        final k = indexes.indexOf(i);
        if (k < 0) {
          updated.add(_lines[i]);
        } else if (texts[k].trim().isNotEmpty) {
          updated.add(EditableTextLine(_lines[i].bounds, texts[k]));
        }
      }
      setState(() {
        _undo.add(_Snapshot(bytes, _lines));
        _redo.clear();
        _bytes = results.first! as Uint8List;
        _lines = updated;
        _phase = _Phase.ready;
        _processingArea = null;
      });
      _showToast('Processing complete', area);
    } catch (_) {
      if (!mounted) return;
      _sweep.stop();
      setState(() {
        _phase = _Phase.ready;
        _processingArea = null;
      });
      _showToast('Processing failed. Your page was not changed.');
    }
  }

  void _undoStep() {
    if (_undo.isEmpty || _phase != _Phase.ready) return;
    setState(() {
      _redo.add(_Snapshot(_bytes!, _lines));
      final previous = _undo.removeLast();
      _bytes = previous.bytes;
      _lines = previous.lines;
      _selected.clear();
    });
  }

  void _redoStep() {
    if (_redo.isEmpty || _phase != _Phase.ready) return;
    setState(() {
      _undo.add(_Snapshot(_bytes!, _lines));
      final next = _redo.removeLast();
      _bytes = next.bytes;
      _lines = next.lines;
      _selected.clear();
    });
  }

  // ------------------------------------------------------------ save / exit

  Future<void> _save() async {
    final bytes = _bytes;
    if (!_dirty || bytes == null || _phase != _Phase.ready) return;
    final prefs = await SharedPreferences.getInstance();
    final skipUntil = prefs.getInt(AiEditTextScreen.skipSaveConfirmKey) ?? 0;
    if (!mounted) return;
    if (DateTime.now().millisecondsSinceEpoch >= skipUntil) {
      final dontAsk = await showDialog<bool>(
        context: context,
        builder: (_) => const _SaveConfirmDialog(),
      );
      if (dontAsk == null || !mounted) return;
      if (dontAsk) {
        await prefs.setInt(AiEditTextScreen.skipSaveConfirmKey,
            DateTime.now().add(const Duration(days: 7))
                .millisecondsSinceEpoch);
      }
    }
    try {
      await (widget.save ?? (bytes) => widget.store.replacePageBytes(
          widget.documentId, widget.pageId, bytes, extension: '.png'))(bytes);
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) _showToast('Could not save: $error');
    }
  }

  Future<void> _close() async {
    if (_phase == _Phase.processing) return;
    if (!_dirty) {
      Navigator.pop(context, false);
      return;
    }
    final discard = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        backgroundColor: const Color(0xFF2C2C2F),
        title: const Text('Discard changes?',
            style: TextStyle(color: Colors.white)),
        content: const Text('Your text edits have not been saved.',
            style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialog, false),
              child: const Text('Cancel',
                  style: TextStyle(color: Colors.white70))),
          TextButton(onPressed: () => Navigator.pop(dialog, true),
              child: const Text('Discard', style: TextStyle(color: dsTeal))),
        ],
      ),
    );
    if (discard == true && mounted) Navigator.pop(context, false);
  }

  Future<void> _feedback() async {
    final answer = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: const Color(0xFF242428),
      builder: (sheet) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('Is DS AI recognizing and editing text correctly?',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white, fontSize: 15)),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(child: OutlinedButton.icon(
                onPressed: () => Navigator.pop(sheet, true),
                icon: const Icon(Icons.thumb_up_outlined),
                label: const Text('Yes'))),
            const SizedBox(width: 12),
            Expanded(child: OutlinedButton.icon(
                onPressed: () => Navigator.pop(sheet, false),
                icon: const Icon(Icons.thumb_down_outlined),
                label: const Text('No'))),
          ]),
        ]),
      ),
    );
    if (answer != null && mounted) _showToast('Thanks for your feedback');
  }

  // -------------------------------------------------------------------- UI

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: false,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) unawaited(_close());
    },
    child: Scaffold(
      backgroundColor: const Color(0xFF1B1B1D),
      body: SafeArea(child: Column(children: [
        _topBar(),
        _infoRow(),
        Expanded(child: _canvas()),
      ])),
    ),
  );

  Widget _topBar() => SizedBox(height: 52, child: Row(children: [
    IconButton(tooltip: 'Close', onPressed: _close,
        icon: const Icon(Icons.close, color: Colors.white)),
    const Spacer(),
    TextButton(onPressed: _phase == _Phase.ready ? _feedback : null,
        child: const Text('Feedback',
            style: TextStyle(color: Colors.white70))),
    Padding(
      padding: const EdgeInsets.only(right: 12),
      child: FilledButton(
        key: const Key('edit-text-save'),
        onPressed: _dirty && _phase == _Phase.ready ? _save : null,
        style: FilledButton.styleFrom(
          backgroundColor: dsTeal,
          disabledBackgroundColor: dsTeal.withValues(alpha: .35),
          disabledForegroundColor: Colors.white54,
          foregroundColor: Colors.white,
          visualDensity: VisualDensity.compact,
          padding: const EdgeInsets.symmetric(horizontal: 14),
        ),
        child: const Row(mainAxisSize: MainAxisSize.min, children: [
          Text('Save'),
          SizedBox(width: 4),
          Icon(Icons.auto_awesome, size: 15),
        ]),
      ),
    ),
  ]));

  Widget _infoRow() {
    final ready = _phase == _Phase.ready || _phase == _Phase.processing;
    return SizedBox(height: 34, child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(children: [
        if (_undo.isNotEmpty || _redo.isNotEmpty) ...[
          IconButton(tooltip: 'Undo', visualDensity: VisualDensity.compact,
              onPressed: _undo.isEmpty ? null : _undoStep,
              icon: const Icon(Icons.undo, size: 20),
              color: Colors.white, disabledColor: Colors.white30),
          IconButton(tooltip: 'Redo', visualDensity: VisualDensity.compact,
              onPressed: _redo.isEmpty ? null : _redoStep,
              icon: const Icon(Icons.redo, size: 20),
              color: Colors.white, disabledColor: Colors.white30),
        ] else if (ready)
          const Text('Tap text or image to edit.',
              style: TextStyle(color: Color(0xFFFFA726), fontSize: 12)),
        const Spacer(),
        if (ready)
          Text('$_characters characters',
              style: const TextStyle(color: Colors.white60, fontSize: 12)),
      ]),
    ));
  }

  Widget _canvas() {
    final bytes = _bytes;
    if (_error != null) {
      return Center(child: Text(_error!,
          style: const TextStyle(color: Colors.white70)));
    }
    if (bytes == null) {
      return const Center(child: CircularProgressIndicator(color: dsTeal));
    }
    return LayoutBuilder(builder: (context, box) {
      final aspect = _size.width / _size.height;
      var w = box.maxWidth;
      var h = w / aspect;
      if (h > box.maxHeight) {
        h = box.maxHeight;
        w = h * aspect;
      }
      final size = Size(w, h);
      return Center(child: SizedBox(width: w, height: h, child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(child: GestureDetector(
            key: const Key('edit-text-canvas'),
            behavior: HitTestBehavior.opaque,
            onTapDown: (details) => _tapImage(Offset(
                details.localPosition.dx / w, details.localPosition.dy / h)),
            child: Image.memory(bytes, fit: BoxFit.fill, gaplessPlayback: true),
          )),
          if (_phase == _Phase.ready || _phase == _Phase.processing)
            Positioned.fill(child: IgnorePointer(child: CustomPaint(
              painter: _LinesPainter(lines: _lines, selected: _selected,
                  processing: _processingArea)))),
          if (_phase == _Phase.analyzing || _phase == _Phase.loading)
            Positioned.fill(child: _AnalyzingOverlay(sweep: _sweep)),
          if (_phase == _Phase.processing && _processingArea != null)
            ..._processingOverlay(size, _processingArea!),
          if (_phase == _Phase.ready && _selected.isNotEmpty)
            _menu(size),
          if (_toast != null) _toastWidget(size),
        ],
      )));
    });
  }

  List<Widget> _processingOverlay(Size size, Rect area) => [
    Positioned.fill(child: Container(color: Colors.black45)),
    Positioned(
      left: (area.center.dx * size.width - 90).clamp(0.0, size.width - 180),
      top: (area.top * size.height - 40).clamp(0.0, size.height - 32),
      child: Container(
        width: 180, height: 32,
        decoration: BoxDecoration(color: const Color(0xE61E1E21),
            borderRadius: BorderRadius.circular(16)),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          RotationTransition(turns: _sweep, child: const Icon(
              Icons.auto_awesome, color: dsTeal, size: 16)),
          const SizedBox(width: 6),
          const Text('DS AI is processing',
              style: TextStyle(color: Colors.white, fontSize: 12)),
        ]),
      ),
    ),
  ];

  Widget _toastWidget(Size size) {
    final area = _toastArea;
    final top = area == null ? size.height * .45
        : (area.bottom * size.height + 10).clamp(0.0, size.height - 40);
    return Positioned(left: 0, right: 0, top: top, child: Center(child:
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(color: const Color(0xE6000000),
            borderRadius: BorderRadius.circular(6)),
        child: Text(_toast!, style: const TextStyle(color: Colors.white)),
      )));
  }

  Widget _menu(Size size) {
    final area = _selected.map((i) => _lines[i].bounds)
        .reduce((a, b) => a.expandToInclude(b));
    final single = _selected.length == 1 ? _selected.first : null;
    final items = <Widget>[
      _menuItem(Icons.copy_outlined, 'Copy', _copy),
      _menuItem(Icons.delete_outline, 'Delete', _delete),
      if (single != null) ...[
        _menuItem(Icons.select_all, 'Select All', _selectAll),
        const Padding(
          padding: EdgeInsets.fromLTRB(12, 6, 12, 2),
          child: Row(children: [
            Icon(Icons.auto_awesome, size: 12, color: Colors.white38),
            SizedBox(width: 4),
            Text('DS AI', style: TextStyle(color: Colors.white38,
                fontSize: 11)),
          ]),
        ),
        _menuItem(Icons.edit_note, 'Edit Text', () => _editLine(single)),
        _menuItem(Icons.spellcheck, 'AI Proofread',
            () => _aiRewrite(single, AiTextTask.proofread)),
        _menuItem(Icons.auto_fix_high, 'AI Polish',
            () => _aiRewrite(single, AiTextTask.polish)),
      ],
    ];
    const menuWidth = 150.0;
    final menuHeight = single != null ? 236.0 : 84.0;
    final left = (area.center.dx * size.width - menuWidth / 2)
        .clamp(0.0, math.max(0.0, size.width - menuWidth));
    // Stay inside the page: taps outside the Stack's box are not received.
    final above = area.top * size.height - menuHeight - 6;
    final below = area.bottom * size.height + 6;
    final top = (above >= 0 ? above : below)
        .clamp(0.0, math.max(0.0, size.height - menuHeight));
    return Positioned(left: left, top: top, width: menuWidth,
      child: Material(
        color: const Color(0xFF2E2E32),
        elevation: 6,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(mainAxisSize: MainAxisSize.min, children: items),
        ),
      ));
  }

  Widget _menuItem(IconData icon, String label, VoidCallback onTap) => InkWell(
    onTap: onTap,
    child: SizedBox(height: 34, child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(children: [
        Icon(icon, size: 17, color: Colors.white),
        const SizedBox(width: 10),
        Text(label, style: const TextStyle(color: Colors.white,
            fontSize: 13)),
      ]),
    )),
  );
}

class _LinesPainter extends CustomPainter {
  _LinesPainter({required this.lines, required this.selected,
      required this.processing});

  final List<EditableTextLine> lines;
  final Set<int> selected;
  final Rect? processing;

  @override
  void paint(Canvas canvas, Size size) {
    Rect toPx(Rect r) => Rect.fromLTRB(r.left * size.width,
        r.top * size.height, r.right * size.width, r.bottom * size.height)
        .inflate(2);
    for (var i = 0; i < lines.length; i++) {
      final rect = toPx(lines[i].bounds);
      final isSelected = selected.contains(i);
      canvas.drawRect(rect, Paint()
        ..color = dsTeal.withValues(alpha: isSelected ? .18 : .05));
      if (isSelected) {
        canvas.drawRect(rect, Paint()
          ..color = dsTeal
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6);
      }
    }
    final area = processing;
    if (area != null) {
      canvas.drawRect(toPx(area), Paint()
        ..color = dsTeal
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6);
    }
  }

  @override
  bool shouldRepaint(_LinesPainter old) => true;
}

/// Dimmed page with a sweeping light band and "DS AI is analyzing".
class _AnalyzingOverlay extends StatelessWidget {
  const _AnalyzingOverlay({required this.sweep});
  final Animation<double> sweep;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) => AnimatedBuilder(
      animation: sweep,
      builder: (context, _) {
        final y = sweep.value * box.maxHeight;
        return Stack(children: [
          Positioned.fill(child: Container(color: Colors.black38)),
          Positioned(left: 0, right: 0, top: y - 60, height: 60,
            child: DecoratedBox(decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter, end: Alignment.bottomCenter,
                colors: [dsTeal.withValues(alpha: 0),
                  const Color(0xFF64B5F6).withValues(alpha: .45)],
              ),
            ))),
          Positioned(left: 0, right: 0, top: y, height: 2,
              child: Container(color: Colors.white70)),
          Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 46, height: 46,
              decoration: BoxDecoration(shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 3),
                  color: Colors.black26),
              child: Transform.rotate(angle: sweep.value * 2 * math.pi,
                  child: const Icon(Icons.auto_awesome, color: dsTeal)),
            ),
            const SizedBox(height: 10),
            const Text('DS AI is analyzing',
                style: TextStyle(color: Colors.white, fontSize: 14,
                    shadows: [Shadow(blurRadius: 4)])),
          ])),
        ]);
      },
    ),
  );
}

class _EditTextSheet extends StatefulWidget {
  const _EditTextSheet({required this.original, required this.initial});
  final String original;
  final String initial;

  @override
  State<_EditTextSheet> createState() => _EditTextSheetState();
}

class _EditTextSheetState extends State<_EditTextSheet> {
  late final TextEditingController _text =
      TextEditingController(text: widget.initial);

  @override
  void initState() {
    super.initState();
    _text.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _tips() => showDialog<void>(context: context,
    builder: (dialog) => AlertDialog(
      backgroundColor: const Color(0xFF2C2C2F),
      title: const Text('Tips', style: TextStyle(color: Colors.white)),
      content: const Text(
        'Edit one line at a time for the best result. DS AI removes the '
        'old words and writes yours in the same colour, size and position. '
        'Leave the box empty to remove the line.',
        style: TextStyle(color: Colors.white70)),
      actions: [TextButton(onPressed: () => Navigator.pop(dialog),
          child: const Text('OK', style: TextStyle(color: dsTeal)))],
    ));

  @override
  Widget build(BuildContext context) {
    final changed = _text.text != widget.original;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 14, 16,
          16 + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Text('Edit Text', style: TextStyle(color: Colors.white,
              fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(width: 4),
          const Icon(Icons.auto_awesome, color: dsTeal, size: 15),
          const Spacer(),
          InkWell(onTap: _tips, child: const Row(children: [
            Icon(Icons.info_outline, size: 14, color: Colors.white54),
            SizedBox(width: 3),
            Text('Tips', style: TextStyle(color: Colors.white54,
                fontSize: 12)),
          ])),
        ]),
        const SizedBox(height: 4),
        const Text('DS AI matches your text to the original font style.',
            style: TextStyle(color: Colors.white54, fontSize: 12)),
        const SizedBox(height: 12),
        TextField(
          key: const Key('edit-text-field'),
          controller: _text,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          cursorColor: dsTeal,
          decoration: InputDecoration(
            isDense: true,
            filled: true,
            fillColor: const Color(0xFF1B1B1D),
            enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: const BorderSide(color: dsTeal)),
            focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: const BorderSide(color: dsTeal, width: 2)),
          ),
        ),
        const SizedBox(height: 14),
        Row(children: [
          Expanded(child: FilledButton(
            onPressed: () => Navigator.pop(context),
            style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF3A3A3F),
                foregroundColor: Colors.white),
            child: const Text('Cancel'))),
          const SizedBox(width: 12),
          Expanded(child: FilledButton(
            key: const Key('edit-text-confirm'),
            onPressed: changed ? () => Navigator.pop(context, _text.text)
                : null,
            style: FilledButton.styleFrom(
                backgroundColor: dsTeal,
                disabledBackgroundColor: dsTeal.withValues(alpha: .35),
                disabledForegroundColor: Colors.white54),
            child: const Text('Confirm'))),
        ]),
      ]),
    );
  }
}

/// "Changes can't be undone once saved." Pops null for Cancel, otherwise
/// whether "Don't ask again for 7 days" is ticked.
class _SaveConfirmDialog extends StatefulWidget {
  const _SaveConfirmDialog();

  @override
  State<_SaveConfirmDialog> createState() => _SaveConfirmDialogState();
}

class _SaveConfirmDialogState extends State<_SaveConfirmDialog> {
  bool _dontAsk = false;

  @override
  Widget build(BuildContext context) => Dialog(
    backgroundColor: const Color(0xFF2C2C2F),
    child: Padding(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 12),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Text("Changes can't be undone once saved.",
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white, fontSize: 16)),
        const SizedBox(height: 18),
        Row(children: [
          Expanded(child: FilledButton(
            onPressed: () => Navigator.pop(context),
            style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF3A3A3F),
                foregroundColor: Colors.white),
            child: const Text('Cancel'))),
          const SizedBox(width: 12),
          Expanded(child: FilledButton(
            key: const Key('edit-text-save-confirm'),
            onPressed: () => Navigator.pop(context, _dontAsk),
            style: FilledButton.styleFrom(backgroundColor: dsTeal),
            child: const Text('Save'))),
        ]),
        const SizedBox(height: 6),
        InkWell(
          onTap: () => setState(() => _dontAsk = !_dontAsk),
          child: Row(children: [
            Checkbox(value: _dontAsk, activeColor: dsTeal,
                visualDensity: VisualDensity.compact,
                onChanged: (v) => setState(() => _dontAsk = v ?? false)),
            const Text("Don't ask again for 7 days",
                style: TextStyle(color: Colors.white60, fontSize: 12)),
          ]),
        ),
      ]),
    ),
  );
}
