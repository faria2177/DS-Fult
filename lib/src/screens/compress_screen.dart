import 'dart:io';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../models.dart';
import '../services/document_export.dart';
import 'video_tool_style.dart';

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
    return VideoToolStyle.wrapDark(Scaffold(
      appBar: AppBar(title: const Text('Compress')),
      body: SafeArea(child: Column(children: [
        if (_busy) const LinearProgressIndicator(),
        Expanded(child: result == null
          ? ListView(padding: EdgeInsets.zero, children: [
              Container(
                padding: const EdgeInsets.fromLTRB(16, 36, 16, 29),
                decoration: const BoxDecoration(gradient: LinearGradient(
                  begin: Alignment.topLeft, end: Alignment.bottomRight,
                  colors: [Color(0xFF27333D), Color(0xFF1C2D2D),
                    VideoToolStyle.background],
                )),
                child: Column(children: [
                  const CircleAvatar(radius: 51,
                    backgroundColor: VideoToolStyle.teal,
                    child: Icon(Icons.compress, size: 62, color: Colors.white)),
                  const SizedBox(height: 18),
                  Text(widget.document.name, textAlign: TextAlign.center,
                    maxLines: 2, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 21, color: Colors.white)),
                  const SizedBox(height: 6),
                  Text(_originalBytes == null ? 'Calculating PDF size…' :
                      _formatBytes(_originalBytes!),
                      style: const TextStyle(fontSize: 14, color: Colors.white70)),
                ]),
              ),
              const Padding(padding: EdgeInsets.fromLTRB(20, 16, 20, 12),
                child: Text('Select compression level:',
                  style: TextStyle(fontSize: 16, color: Colors.white))),
              for (final level in CompressionLevel.values)
                Card(margin: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                  color: _level == level
                      ? VideoToolStyle.teal.withValues(alpha: .10)
                      : VideoToolStyle.background,
                  shape: RoundedRectangleBorder(
                    side: BorderSide(color: _level == level
                        ? VideoToolStyle.teal : const Color(0xFF55555A)),
                    borderRadius: BorderRadius.circular(5)),
                  child: ListTile(
                    contentPadding: const EdgeInsets.fromLTRB(16, 9, 16, 9),
                    title: Text(level.label, style: TextStyle(fontSize: 19,
                      color: _level == level
                          ? VideoToolStyle.teal : Colors.white)),
                    subtitle: Padding(padding: const EdgeInsets.only(top: 5),
                      child: Text(level.description,
                        style: const TextStyle(color: VideoToolStyle.muted))),
                    trailing: _level == level ?
                        const Icon(Icons.check, color: VideoToolStyle.teal) : null,
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
        Container(color: VideoToolStyle.header,
          padding: const EdgeInsets.fromLTRB(16, 9, 16, 12),
          child: SizedBox(width: double.infinity,
            child: FilledButton(
              onPressed: _busy ? null : result == null ? _compress : _share,
              style: VideoToolStyle.tealButton,
              child: Text(_busy ? 'Compressing…' : result == null
                  ? 'Compress' : 'Share Compressed PDF'),
            ))),
      ])),
    ));
  }
}
