import 'dart:io';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../models.dart';
import '../services/document_export.dart';
import '../theme.dart';

enum CompressionLevel { medium, high }

extension CompressionLevelDetails on CompressionLevel {
  String get label => this == CompressionLevel.medium ? 'Medium' : 'High';
  String get description => this == CompressionLevel.medium
      ? 'Medium size, better quality'
      : 'Smaller size, standard quality';
  int get imageQuality => this == CompressionLevel.medium ? 70 : 36;
}

/// Compressed PDF is created locally and shared only after user confirmation.
class CompressScreen extends StatefulWidget {
  const CompressScreen({super.key, required this.document});

  final ScanDocument document;

  @override
  State<CompressScreen> createState() => _CompressScreenState();
}

class _CompressScreenState extends State<CompressScreen> {
  CompressionLevel _level = CompressionLevel.medium;
  int? _originalBytes;
  File? _result;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _measureOriginal();
  }

  Future<void> _measureOriginal() async {
    try {
      final bytes = await DocumentExport.toPdf(widget.document);
      if (mounted) setState(() => _originalBytes = bytes.length);
    } catch (_) {
      // Compression can still be attempted if source size cannot be measured.
    }
  }

  Future<void> _compress() async {
    if (_busy) return;
    setState(() { _busy = true; _result = null; });
    try {
      final file = await DocumentExport.savePdf(widget.document,
          imageQuality: _level.imageQuality);
      if (mounted) setState(() => _result = file);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Compression failed: $error')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _share() async {
    final file = _result;
    if (file == null) return;
    await SharePlus.instance.share(ShareParams(
      files: [XFile(file.path, mimeType: 'application/pdf')],
      subject: widget.document.name,
    ));
  }

  String _formatBytes(int bytes) => bytes >= 1024 * 1024
      ? '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB'
      : '${(bytes / 1024).toStringAsFixed(1)} KB';

  @override
  Widget build(BuildContext context) {
    final result = _result;
    return Scaffold(
      appBar: AppBar(title: const Text('Compress')),
      body: SafeArea(child: Column(children: [
        if (_busy) const LinearProgressIndicator(),
        Expanded(child: result == null
          ? ListView(padding: const EdgeInsets.all(18), children: [
              const SizedBox(height: 28),
              const Center(child: CircleAvatar(radius: 36,
                  backgroundColor: dsTeal,
                  child: Icon(Icons.compress, size: 38, color: Colors.white))),
              const SizedBox(height: 18),
              Text(widget.document.name, textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 6),
              Text(_originalBytes == null ? 'Calculating PDF size…' :
                  'Original PDF: ${_formatBytes(_originalBytes!)}',
                  textAlign: TextAlign.center),
              const SizedBox(height: 32),
              const Text('Select compression level:'),
              const SizedBox(height: 8),
              for (final level in CompressionLevel.values)
                Card(
                  color: _level == level ? dsTeal.withValues(alpha: .12) : null,
                  shape: RoundedRectangleBorder(
                    side: BorderSide(color: _level == level ? dsTeal :
                        Theme.of(context).dividerColor),
                    borderRadius: BorderRadius.circular(8)),
                  child: ListTile(
                    title: Text(level.label),
                    subtitle: Text(level.description),
                    trailing: _level == level ?
                        const Icon(Icons.check, color: dsTeal) : null,
                    onTap: _busy ? null : () => setState(() => _level = level),
                  ),
                ),
            ])
          : Column(children: [
              Expanded(child: Center(child: widget.document.pages.isEmpty ?
                  const Icon(Icons.picture_as_pdf, size: 80) :
                  Image.file(File(widget.document.pages.first.path),
                      fit: BoxFit.contain))),
              Padding(padding: const EdgeInsets.all(10), child: FutureBuilder<int>(
                future: result.length(),
                builder: (context, snapshot) => Text(snapshot.hasData
                    ? 'Compressed PDF: ${_formatBytes(snapshot.data!)}'
                    : 'Calculating compressed size…'),
              )),
            ])),
        Padding(padding: const EdgeInsets.all(16),
          child: SizedBox(width: double.infinity,
            child: FilledButton(
              onPressed: _busy ? null : result == null ? _compress : _share,
              child: Text(_busy ? 'Compressing…' : result == null
                  ? 'Compress' : 'Share Compressed PDF'),
            ))),
      ])),
    );
  }
}
