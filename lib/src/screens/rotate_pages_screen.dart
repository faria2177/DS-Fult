import 'dart:io';

import 'package:flutter/material.dart';

import '../models.dart';
import '../storage/document_store.dart';
import 'video_tool_style.dart';

/// Video 381565: preview and rotate selected pages without modifying the
/// saved document until the user explicitly confirms Done.
class RotatePagesScreen extends StatefulWidget {
  const RotatePagesScreen({
    super.key,
    required this.store,
    required this.documentId,
  });

  final DocumentStore store;
  final String documentId;

  @override
  State<RotatePagesScreen> createState() => _RotatePagesScreenState();
}

class _RotatePagesScreenState extends State<RotatePagesScreen> {
  final Set<String> _selected = {};
  final Map<String, int> _rotations = {};
  bool _saving = false;
  String? _error;

  void _rotate(int quarterTurns) {
    if (_saving || _selected.isEmpty) return;
    setState(() {
      _error = null;
      for (final id in _selected) {
        final next = ((_rotations[id] ?? 0) + quarterTurns) % 4;
        if (next == 0) {
          _rotations.remove(id);
        } else {
          _rotations[id] = next;
        }
      }
    });
  }

  void _resetSelected() {
    if (_saving || _selected.isEmpty) return;
    setState(() {
      _error = null;
      for (final id in _selected) {
        _rotations.remove(id);
      }
    });
  }

  Future<void> _save() async {
    if (_saving) return;
    if (_rotations.isEmpty) {
      Navigator.pop(context, false);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.store.rotatePages(widget.documentId, Map.of(_rotations));
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) setState(() => _error = 'Could not rotate pages: $error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _preview(ScanPage page, int index) {
    showDialog<void>(context: context, builder: (dialog) => Dialog(
      child: Stack(children: [
        InteractiveViewer(minScale: .5, maxScale: 5,
          child: Center(child: RotatedBox(
            quarterTurns: _rotations[page.id] ?? 0,
            child: Image.file(File(page.path), fit: BoxFit.contain,
              errorBuilder: (_, _, _) => const Padding(
                padding: EdgeInsets.all(45),
                child: Text('Preview unavailable'),
              )),
          )),
        ),
        Positioned(top: 4, right: 4, child: IconButton(
          tooltip: 'Close page ${index + 1} preview',
          onPressed: () => Navigator.pop(dialog),
          icon: const Icon(Icons.close),
        )),
      ]),
    ));
  }

  Widget _tile(ScanPage page, int index) {
    final selected = _selected.contains(page.id);
    final turns = _rotations[page.id] ?? 0;
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(5),
        side: BorderSide(color: selected
            ? VideoToolStyle.teal : Colors.transparent,
          width: selected ? 2.5 : 1),
      ),
      child: InkWell(
        key: Key('rotate-page-${page.id}'),
        onTap: _saving ? null : () => setState(() {
          if (selected) { _selected.remove(page.id); }
          else { _selected.add(page.id); }
        }),
        child: Column(children: [
          Expanded(child: Stack(fit: StackFit.expand, children: [
            Padding(padding: const EdgeInsets.all(9), child: RotatedBox(
              key: Key('rotate-preview-${page.id}'),
              quarterTurns: turns,
              child: Image.file(File(page.path), fit: BoxFit.contain,
                cacheWidth: 320,
                errorBuilder: (_, _, _) => const Icon(
                  Icons.broken_image_outlined)),
            )),
            Positioned(top: 4, left: 4, child: IgnorePointer(
              child: Checkbox(value: selected,
                activeColor: VideoToolStyle.teal, onChanged: (_) {}),
            )),
            Positioned(top: 3, right: 3, child: IconButton(
              tooltip: 'Preview page ${index + 1}',
              icon: const Icon(Icons.zoom_in_outlined, size: 21),
              onPressed: () => _preview(page, index),
            )),
          ])),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 5),
            color: selected ? VideoToolStyle.teal.withValues(alpha: .15)
                : VideoToolStyle.header,
            child: Row(mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('Page ${index + 1}', style:
                  const TextStyle(fontWeight: FontWeight.w600)),
                if (turns != 0) ...[
                  const SizedBox(width: 6),
                  Text('${turns * 90}°', style: const TextStyle(
                    fontSize: 12, color: VideoToolStyle.teal)),
                ],
              ]),
          ),
        ]),
      ),
    );
  }

  Widget _rotateButton(String label, IconData icon, VoidCallback action) =>
      Expanded(child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3),
        child: OutlinedButton(
          onPressed: _saving || _selected.isEmpty ? null : action,
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 1),
            minimumSize: const Size(0, 62),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8)),
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 23),
            const SizedBox(height: 2),
            Text(label, style: const TextStyle(fontSize: 11),
              textAlign: TextAlign.center),
          ]),
        ),
      ));

  @override
  Widget build(BuildContext context) {
    final document = widget.store.byId(widget.documentId);
    if (document == null) {
      return const Scaffold(body: Center(child: Text('Document not found')));
    }
    final allSelected = document.pages.isNotEmpty &&
        document.pages.every((page) => _selected.contains(page.id));
    return VideoToolStyle.wrapDark(Scaffold(
      appBar: AppBar(
        title: const Text('Rotate Pages'),
        actions: [TextButton(
          onPressed: _saving ? null : () => setState(() {
            if (allSelected) { _selected.clear(); }
            else { _selected.addAll(document.pages.map((page) => page.id)); }
          }),
          child: Text(allSelected ? 'Deselect All' : 'Select All',
            style: const TextStyle(color: VideoToolStyle.teal)),
        )],
      ),
      body: SafeArea(child: Column(children: [
        if (_saving) const LinearProgressIndicator(color: VideoToolStyle.teal),
        Padding(padding: const EdgeInsets.fromLTRB(16, 12, 16, 7),
          child: Row(children: [
            Expanded(child: Text(document.name, maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600))),
            Text('${_selected.length}/${document.pages.length} selected',
              style: const TextStyle(color: VideoToolStyle.muted, fontSize: 12)),
          ]),
        ),
        const Padding(padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Align(alignment: Alignment.centerLeft,
            child: Text('Select one or more pages to rotate',
              style: TextStyle(fontSize: 12, color: VideoToolStyle.muted))),
        ),
        Expanded(child: GridView.builder(
          padding: const EdgeInsets.fromLTRB(14, 4, 14, 12),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2, childAspectRatio: .75,
            mainAxisSpacing: 12, crossAxisSpacing: 10),
          itemCount: document.pages.length,
          itemBuilder: (_, index) => _tile(document.pages[index], index),
        )),
        if (_error != null) Padding(
          padding: const EdgeInsets.fromLTRB(14, 4, 14, 6),
          child: Text(_error!, style: TextStyle(
            color: Theme.of(context).colorScheme.error)),
        ),
        Padding(padding: const EdgeInsets.fromLTRB(10, 6, 10, 12),
          child: Column(children: [
            Row(children: [
              _rotateButton('Left 90°', Icons.rotate_left, () => _rotate(-1)),
              _rotateButton('Right 90°', Icons.rotate_right, () => _rotate(1)),
              _rotateButton('180°', Icons.sync, () => _rotate(2)),
              _rotateButton('Reset', Icons.restart_alt, _resetSelected),
            ]),
            const SizedBox(height: 9),
            Text('${_rotations.length} page(s) changed • Save with Done',
              style: const TextStyle(color: VideoToolStyle.muted,
                fontSize: 12)),
          ]),
        ),
        VideoToolBottomBar(
          title: _saving ? 'Saving…' : 'Rotate Pages',
          busy: _saving,
          onCancel: () => Navigator.pop(context, false),
          onDone: _save,
        ),
      ])),
    ));
  }
}
