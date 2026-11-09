import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models.dart';
import '../services/document_export.dart';
import '../services/image_tool_operations.dart';
import '../storage/document_store.dart';
import '../theme.dart';
import 'document_detail_screen.dart';

typedef LongImageBuilder = Future<Uint8List> Function(
    ScanDocument document, bool watermark);

/// Video 381562: preview the finished long image before deciding whether to
/// save to this app, share, export a readable PDF or save to Android Gallery.
class LongImageStudioScreen extends StatefulWidget {
  const LongImageStudioScreen({
    super.key,
    required this.document,
    required this.store,
    this.builder,
  });

  final ScanDocument document;
  final DocumentStore store;

  /// Allows preview/widget tests without touching Android storage.
  final LongImageBuilder? builder;

  @override
  State<LongImageStudioScreen> createState() => _LongImageStudioScreenState();
}

class _LongImageStudioScreenState extends State<LongImageStudioScreen> {
  Uint8List? _preview;
  bool _watermark = false;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _render();
    });
  }

  Future<void> _render() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
      _preview = null;
    });
    try {
      final bytes = await (widget.builder?.call(widget.document, _watermark)
          ?? ImageToolOperations.createLongImage(widget.document,
              watermark: _watermark));
      if (mounted) setState(() => _preview = bytes);
    } catch (error) {
      if (mounted) setState(() => _error = 'Long image could not be created: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<File> _temporaryFile(Uint8List bytes, String extension) async {
    final directory = await getTemporaryDirectory();
    final file = File(p.join(directory.path,
      'docscanner_long_${DateTime.now().microsecondsSinceEpoch}.$extension'));
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  Future<void> _run(Future<void> Function(Uint8List) action) async {
    final bytes = _preview;
    if (bytes == null || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action(bytes);
    } catch (error) {
      if (mounted) setState(() => _error = 'Long image export failed: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _saveAsNew() => _run((bytes) async {
    final file = await _temporaryFile(bytes, 'jpg');
    final doc = await widget.store.createFromPaths(
        [file.path], name: '${widget.document.name} - Long Image');
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Done — long image saved as a new document')));
    await Navigator.push<void>(context, MaterialPageRoute(
      builder: (_) => DocumentDetailScreen(
        store: widget.store, documentId: doc.id),
    ));
  });

  Future<void> _shareLongImage() => _run((bytes) async {
    final file = await _temporaryFile(bytes, 'jpg');
    await SharePlus.instance.share(ShareParams(
      files: [XFile(file.path, mimeType: 'image/jpeg')],
      subject: '${widget.document.name} - Long Image',
    ));
  });

  Future<void> _sharePdf() => _run((bytes) async {
    final pdf = await compute(ImageToolOperations.longImagePdfBytes, bytes);
    final file = await _temporaryFile(pdf, 'pdf');
    await SharePlus.instance.share(ShareParams(
      files: [XFile(file.path, mimeType: 'application/pdf')],
      subject: '${widget.document.name} - Long Image PDF',
    ));
  });

  Future<void> _shareSourceImages() => _run((_) async {
    // This action exports original individual pages, never a sliced or
    // re-encoded version of the stitched result.
    await DocumentExport.shareImages(widget.document);
  });

  Future<void> _saveGallery() => _run((bytes) async {
    final file = await _temporaryFile(bytes, 'jpg');
    await DocumentExport.saveImageFileToGallery(file.path);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Long image saved to Gallery')));
    }
  });

  Widget _actionButton(String label, IconData icon, VoidCallback action,
      {bool primary = false}) => SizedBox(
    height: 46,
    child: primary
      ? FilledButton.icon(onPressed: _busy || _preview == null ? null : action,
          icon: Icon(icon, size: 20), label: Text(label))
      : OutlinedButton.icon(onPressed: _busy || _preview == null ? null : action,
          icon: Icon(icon, size: 20), label: Text(label)),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('PDF to Long Image'), actions: [
      IconButton(tooltip: 'Refresh Preview',
        onPressed: _busy ? null : _render,
        icon: const Icon(Icons.refresh_outlined)),
    ]),
    body: SafeArea(child: Column(children: [
      Padding(padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
        child: Row(children: [
          Expanded(child: Text(widget.document.name, maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w700))),
          Text('${widget.document.pages.length} page(s)',
            style: const TextStyle(color: dsMuted, fontSize: 12)),
        ])),
      if (_busy) const LinearProgressIndicator(color: dsTeal),
      Expanded(child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16),
        width: double.infinity,
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: _preview == null
          ? Center(child: _busy
              ? const CircularProgressIndicator(color: dsTeal)
              : const Icon(Icons.panorama_vertical_outlined,
                  size: 72, color: dsMuted))
          : SingleChildScrollView(child: Image.memory(_preview!,
              key: const Key('long-image-preview'),
              cacheWidth: 650, width: double.infinity,
              fit: BoxFit.fitWidth, gaplessPlayback: true)),
      )),
      if (_error != null)
        Padding(padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Text(_error!, style: TextStyle(
              color: Theme.of(context).colorScheme.error))),
      SwitchListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16),
        title: const Text('Add DocScanner watermark'),
        subtitle: const Text('Places a small mark below the last page'),
        value: _watermark,
        onChanged: _busy ? null : (value) {
          setState(() => _watermark = value);
          _render();
        },
      ),
      Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: Column(children: [
          Row(children: [
            Expanded(child: _actionButton('Save as New',
                Icons.save_alt_outlined, _saveAsNew, primary: true)),
            const SizedBox(width: 8),
            Expanded(child: _actionButton('Share Image',
                Icons.share_outlined, _shareLongImage)),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: _actionButton('Share as PDF',
                Icons.picture_as_pdf_outlined, _sharePdf)),
            const SizedBox(width: 8),
            Expanded(child: _actionButton('Share as Images',
                Icons.collections_outlined, _shareSourceImages)),
          ]),
          const SizedBox(height: 8),
          SizedBox(width: double.infinity,
            child: _actionButton('Save to Gallery',
                Icons.photo_album_outlined, _saveGallery)),
        ]),
      ),
    ])),
  );
}
