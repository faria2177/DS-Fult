import 'dart:io';

import 'package:flutter/material.dart';

import '../models.dart';
import '../storage/document_store.dart';
import 'video_tool_style.dart';

/// Two-column, drag-to-sort page workspace. Changes are saved only on Done.
class ReorderPagesScreen extends StatefulWidget {
  const ReorderPagesScreen({
    super.key,
    required this.store,
    required this.documentId,
  });

  final DocumentStore store;
  final String documentId;

  @override
  State<ReorderPagesScreen> createState() => _ReorderPagesScreenState();
}

class _ReorderPagesScreenState extends State<ReorderPagesScreen> {
  late final List<String> _order;
  final Set<String> _selectedIds = {};
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _order = [
      for (final page in widget.store.byId(widget.documentId)?.pages ?? <ScanPage>[])
        page.id,
    ];
  }

  void _move(String movingId, String destinationId) {
    if (movingId == destinationId) return;
    final from = _order.indexOf(movingId);
    final to = _order.indexOf(destinationId);
    if (from < 0 || to < 0) return;
    setState(() {
      _order.removeAt(from);
      _order.insert(to, movingId);
      _selectedIds..clear()..add(movingId);
    });
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await widget.store.setPageOrder(widget.documentId, _order);
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not reorder pages: $error')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final doc = widget.store.byId(widget.documentId);
    if (doc == null) {
      return const Scaffold(body: Center(child: Text('Document not found')));
    }
    final pages = {for (final page in doc.pages) page.id: page};
    return VideoToolStyle.wrapDark(Scaffold(
      appBar: AppBar(
        title: Text(_selectedIds.isEmpty ? 'Reorder Pages' :
            '${_selectedIds.length} selected'),
        actions: [TextButton(
          onPressed: () => setState(() {
            if (_selectedIds.length == _order.length) {
              _selectedIds.clear();
            } else {
              _selectedIds..clear()..addAll(_order);
            }
          }),
          child: Text(_selectedIds.length == _order.length
              ? 'Deselect All' : 'Select All',
              style: const TextStyle(color: VideoToolStyle.teal)),
        )],
      ),
      body: SafeArea(child: Column(children: [
        if (_saving) const LinearProgressIndicator(),
        const Padding(padding: EdgeInsets.fromLTRB(15, 10, 15, 7),
          child: Row(children: [
            Icon(Icons.info_outline, color: VideoToolStyle.muted, size: 17),
            SizedBox(width: 6),
            Text('Hold and drag to reorder',
              style: TextStyle(color: VideoToolStyle.muted, fontSize: 13)),
          ]),
        ),
        Expanded(child: GridView.builder(
          padding: const EdgeInsets.fromLTRB(14, 6, 14, 18),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisSpacing: 16,
            crossAxisSpacing: 9,
            childAspectRatio: .70,
          ),
          itemCount: _order.length,
          itemBuilder: (context, index) {
            final id = _order[index];
            final page = pages[id]!;
            final selected = _selectedIds.contains(id);
            Widget tile() => Card(
              margin: EdgeInsets.zero,
              clipBehavior: Clip.antiAlias,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(3),
                side: BorderSide(color: selected
                    ? VideoToolStyle.teal : Colors.transparent,
                    width: selected ? 2.5 : 1),
              ),
              child: Column(children: [
                Expanded(child: Stack(fit: StackFit.expand, children: [
                  Image.file(File(page.path), fit: BoxFit.cover,
                    errorBuilder: (_, _, _) =>
                        const Center(child: Icon(Icons.broken_image_outlined))),
                  if (selected)
                    const Positioned(right: 6, top: 6,
                      child: Icon(Icons.check_box,
                          color: VideoToolStyle.teal, size: 25)),
                ])),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  color: selected ? VideoToolStyle.teal
                      : VideoToolStyle.background,
                  child: Text('${index + 1}'.padLeft(2, '0'),
                      textAlign: TextAlign.center,
                      style: TextStyle(color: selected ? Colors.white : null)),
                ),
              ]),
            );
            return DragTarget<String>(
              onWillAcceptWithDetails: (details) => details.data != id,
              onAcceptWithDetails: (details) => _move(details.data, id),
              builder: (context, candidates, rejected) => Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  border: candidates.isEmpty ? null :
                      Border.all(color: VideoToolStyle.teal, width: 3),
                ),
                child: LongPressDraggable<String>(
                  data: id,
                  feedback: Material(color: Colors.transparent,
                    child: SizedBox(width: 140, height: 190, child: tile())),
                  childWhenDragging: Opacity(opacity: .3, child: tile()),
                  child: InkWell(
                    onTap: () => setState(() {
                      if (selected) { _selectedIds.remove(id); }
                      else { _selectedIds.add(id); }
                    }),
                    child: tile(),
                  ),
                ),
              ),
            );
          },
        )),
        VideoToolBottomBar(
          title: 'Reorder Pages', busy: _saving,
          onCancel: () => Navigator.pop(context, false),
          onDone: _save,
        ),
      ])),
    ));
  }
}
