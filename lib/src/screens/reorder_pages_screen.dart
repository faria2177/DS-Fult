import 'dart:io';

import 'package:flutter/material.dart';

import '../models.dart';
import '../storage/document_store.dart';
import '../theme.dart';

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
  String? _selectedId;
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
      _selectedId = movingId;
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
    return Scaffold(
      appBar: AppBar(
        title: Text(_selectedId == null ? 'Reorder Pages' : '1 selected'),
      ),
      body: SafeArea(child: Column(children: [
        if (_saving) const LinearProgressIndicator(),
        const ListTile(
          dense: true,
          leading: Icon(Icons.info_outline, size: 19),
          title: Text('Hold and drag a page to change its position'),
        ),
        Expanded(child: GridView.builder(
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 18),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisSpacing: 12,
            crossAxisSpacing: 10,
            childAspectRatio: .72,
          ),
          itemCount: _order.length,
          itemBuilder: (context, index) {
            final id = _order[index];
            final page = pages[id]!;
            final selected = _selectedId == id;
            Widget tile({bool dragging = false}) => Card(
              margin: EdgeInsets.zero,
              clipBehavior: Clip.antiAlias,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
                side: BorderSide(color: selected ? dsTeal : Colors.transparent,
                    width: selected ? 2.5 : 1),
              ),
              child: Column(children: [
                Expanded(child: Stack(fit: StackFit.expand, children: [
                  Image.file(File(page.path), fit: BoxFit.contain,
                    errorBuilder: (_, _, _) =>
                        const Center(child: Icon(Icons.broken_image_outlined))),
                  if (selected)
                    const Positioned(right: 6, top: 6,
                      child: Icon(Icons.check_circle, color: dsTeal)),
                ])),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  color: selected ? dsTeal : Theme.of(context).colorScheme.surface,
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
                      Border.all(color: dsTeal, width: 3),
                ),
                child: LongPressDraggable<String>(
                  data: id,
                  feedback: Material(color: Colors.transparent,
                    child: SizedBox(width: 140, height: 190, child: tile(dragging: true))),
                  childWhenDragging: Opacity(opacity: .3, child: tile()),
                  child: InkWell(
                    onTap: () => setState(() => _selectedId = id),
                    child: tile(),
                  ),
                ),
              ),
            );
          },
        )),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
          child: Row(children: [
            Expanded(child: OutlinedButton.icon(
              onPressed: _saving ? null : () => Navigator.pop(context, false),
              icon: const Icon(Icons.close), label: const Text('Cancel'))),
            const SizedBox(width: 12),
            Expanded(child: FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: const Icon(Icons.check), label: const Text('Confirm'))),
          ]),
        ),
      ])),
    );
  }
}
