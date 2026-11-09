import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../models.dart';
import '../services/pdf_import_service.dart';
import '../storage/document_store.dart';
import 'video_tool_style.dart';

/// Source selection shared by video-reference Tools. Returns document IDs,
/// including images imported through Android's gallery picker.
class VideoToolSourcePicker extends StatefulWidget {
  const VideoToolSourcePicker({
    super.key,
    required this.store,
    required this.title,
    required this.description,
    required this.icon,
    this.multiSelect = false,
    this.light = false,
    this.allowGallery = false,
    this.allowPdf = false,
    this.importsOnly = false,
    this.onScan,
  });

  final DocumentStore store;
  final String title;
  final String description;
  final IconData icon;
  final bool multiSelect;
  final bool light;
  final bool allowGallery;
  final bool allowPdf;
  /// Hide existing documents when this entry point is strictly for imports.
  final bool importsOnly;
  final Future<void> Function()? onScan;

  @override
  State<VideoToolSourcePicker> createState() => _VideoToolSourcePickerState();
}

class _VideoToolSourcePickerState extends State<VideoToolSourcePicker> {
  static const _platform = MethodChannel('doclens/methods');
  final Set<String> _selected = {};
  bool _loading = false;

  Future<void> _importImages() async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      final images = await ImagePicker().pickMultiImage();
      if (images.isEmpty || !mounted) return;
      final document = await widget.store.createFromPaths(
        images.map((image) => image.path).toList(),
        name: 'Imported Document',
      );
      if (!mounted) return;
      if (widget.multiSelect) {
        setState(() => _selected.add(document.id));
      } else {
        Navigator.pop(context, [document.id]);
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not import images: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _importPdf() async {
    if (_loading) return;
    setState(() => _loading = true);
    String? cachedPath;
    try {
      cachedPath = await _platform.invokeMethod<String>('pickPdfFile');
      if (cachedPath == null) return;
      final document = await PdfImportService.importPdf(
          cachedPath, widget.store);
      if (!mounted) return;
      if (widget.multiSelect) {
        setState(() => _selected.add(document.id));
      } else {
        Navigator.pop(context, [document.id]);
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not import PDF: $error')),
        );
      }
    } finally {
      // The picker returns a separate app-cache copy, never the original SAF
      // URI. Delete only that known temporary import after rasterization.
      if (cachedPath != null &&
          File(cachedPath).uri.pathSegments.last.startsWith('docscanner_pdf_')) {
        final cacheCopy = File(cachedPath);
        if (await cacheCopy.exists()) await cacheCopy.delete();
      }
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final light = widget.light;
    final muted = light ? const Color(0xFF656877) : VideoToolStyle.muted;
    final headerColor = light ? const Color(0xFFF7F8FB) : VideoToolStyle.header;
    final surfaceColor = light ? Colors.white : VideoToolStyle.tile;
    final ink = light ? const Color(0xFF22242C) : Colors.white;
    final theme = light
        ? ThemeData.light(useMaterial3: true).copyWith(
            scaffoldBackgroundColor: const Color(0xFFF7F8FB),
            colorScheme: ColorScheme.fromSeed(seedColor: VideoToolStyle.teal),
          )
        : VideoToolStyle.dark;
    return Theme(data: theme, child: Scaffold(
      body: SafeArea(child: AnimatedBuilder(
        animation: widget.store,
        builder: (context, _) {
          final documents = widget.store.documents.toList();
          return Column(children: [
            Container(color: headerColor, child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 5, 17, 20),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  IconButton(onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.arrow_back),
                    padding: EdgeInsets.zero,
                    alignment: Alignment.centerLeft),
                  const SizedBox(height: 14),
                  Row(children: [
                    Expanded(child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(widget.title, style: TextStyle(color: ink,
                          fontSize: 28, fontWeight: FontWeight.w500)),
                        const SizedBox(height: 8),
                        Text(widget.description, style: TextStyle(
                          color: muted, fontSize: 13)),
                      ],
                    )),
                    Container(width: 92, height: 92,
                      decoration: BoxDecoration(
                        color: VideoToolStyle.teal.withValues(alpha: .10),
                        borderRadius: BorderRadius.circular(16)),
                      child: Icon(widget.icon, size: 55,
                          color: VideoToolStyle.teal)),
                  ]),
                ],
              ),
            )),
            if (_loading) const LinearProgressIndicator(
                color: VideoToolStyle.teal),
            Expanded(child: ListView(padding: const EdgeInsets.all(16),
              children: [
                Text('Create or Import', style: TextStyle(color: muted,
                    fontWeight: FontWeight.w500)),
                const SizedBox(height: 12),
                Row(children: [
                  if (widget.onScan != null) ...[
                    Expanded(child: _sourceTile('Scan', Icons.camera_alt_outlined,
                        surfaceColor, () async {
                          await widget.onScan!();
                        })),
                    const SizedBox(width: 8),
                  ],
                  Expanded(child: _sourceTile(widget.importsOnly
                      ? 'Images' : 'Device', Icons.smartphone,
                      surfaceColor, _importImages)),
                  if (widget.allowGallery) ...[
                    const SizedBox(width: 8),
                    Expanded(child: _sourceTile('Gallery', Icons.photo_library_outlined,
                        surfaceColor, _importImages)),
                  ],
                  if (widget.allowPdf) ...[
                    const SizedBox(width: 8),
                    Expanded(child: _sourceTile('PDF File',
                        Icons.picture_as_pdf_outlined,
                        surfaceColor, _importPdf)),
                  ],
                ]),
                if (!widget.importsOnly) ...[
                  const SizedBox(height: 24),
                  Text('Select from This App', style: TextStyle(color: muted,
                      fontWeight: FontWeight.w500)),
                  const SizedBox(height: 12),
                  for (final document in documents)
                    _documentTile(document, surfaceColor, ink, muted),
                ],
              ],
            )),
            if (widget.multiSelect)
              Container(
                padding: const EdgeInsets.fromLTRB(16, 9, 16, 12),
                color: headerColor,
                child: SafeArea(top: false, child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _selected.length < 2 ? null :
                        () => Navigator.pop(context, _selected.toList()),
                    style: VideoToolStyle.tealButton,
                    child: Text('Merge (${_selected.length})'),
                  ),
                )),
              ),
          ]);
        },
      )),
    ));
  }

  Widget _sourceTile(String label, IconData icon, Color color,
      VoidCallback action) => Material(
    color: color,
    borderRadius: BorderRadius.circular(widget.light ? 12 : 4),
    child: InkWell(onTap: _loading ? null : action,
      borderRadius: BorderRadius.circular(widget.light ? 12 : 4),
      child: Padding(padding: const EdgeInsets.symmetric(
        vertical: 16, horizontal: 9),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, color: VideoToolStyle.teal, size: 19),
          const SizedBox(width: 6),
          Text(label, style: const TextStyle(fontSize: 14)),
        ]),
      ),
    ),
  );

  Widget _documentTile(ScanDocument document, Color surface, Color ink,
      Color muted) {
    final selected = _selected.contains(document.id);
    final locked = document.lockHash != null;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: selected ? VideoToolStyle.teal.withValues(alpha: .18) : surface,
      child: InkWell(
        onTap: locked ? null : () {
          if (widget.multiSelect) {
            setState(() {
              if (selected) { _selected.remove(document.id); }
              else { _selected.add(document.id); }
            });
          } else {
            Navigator.pop(context, [document.id]);
          }
        },
        borderRadius: BorderRadius.circular(9),
        child: Padding(padding: const EdgeInsets.all(8), child: Row(children: [
          SizedBox(width: 58, height: 67,
            child: document.pages.isEmpty
              ? const Icon(Icons.description_outlined)
              : ClipRRect(borderRadius: BorderRadius.circular(5),
                  child: Image.file(File(document.pages.first.path),
                    fit: BoxFit.cover, errorBuilder: (_, _, _) =>
                        const Icon(Icons.broken_image_outlined)))),
          const SizedBox(width: 13),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(document.name, maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: ink, fontSize: 15)),
              const SizedBox(height: 5),
              Text('${document.createdAt.day.toString().padLeft(2, '0')}/'
                  '${document.createdAt.month.toString().padLeft(2, '0')}/'
                  '${document.createdAt.year}   ▯ ${document.pages.length} Page(s)',
                  style: TextStyle(color: muted, fontSize: 11)),
            ],
          )),
          if (locked)
            const Padding(padding: EdgeInsets.all(4),
                child: Icon(Icons.lock, size: 18, color: VideoToolStyle.teal))
          else if (widget.multiSelect)
            Checkbox(value: selected, activeColor: VideoToolStyle.teal,
              onChanged: (value) => setState(() {
                if (value == true) { _selected.add(document.id); }
                else { _selected.remove(document.id); }
              })),
        ])),
      ),
    );
  }
}
