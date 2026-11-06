import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

import '../theme.dart';

/// Local Text-to-PDF conversion, independent of the camera and OCR pipeline.
class TextToPdfScreen extends StatefulWidget {
  const TextToPdfScreen({super.key});

  @override
  State<TextToPdfScreen> createState() => _TextToPdfScreenState();
}

class _TextToPdfScreenState extends State<TextToPdfScreen> {
  final _title = TextEditingController(text: 'New document');
  final _body = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _export() async {
    final content = _body.text.trim();
    if (content.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Enter some text first.')));
      return;
    }
    setState(() => _busy = true);
    try {
      final document = pw.Document();
      document.addPage(pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(38),
        build: (_) => [
          pw.Text(_title.text.trim().isEmpty ? 'Document' : _title.text.trim(),
              style: pw.TextStyle(fontSize: 21, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 16),
          pw.Text(content, style: const pw.TextStyle(fontSize: 11)),
        ],
      ));
      final directory = await getTemporaryDirectory();
      final file = File(p.join(directory.path,
          'docscanner_text_${DateTime.now().microsecondsSinceEpoch}.pdf'));
      await file.writeAsBytes(await document.save(), flush: true);
      await SharePlus.instance.share(ShareParams(
        files: [XFile(file.path, mimeType: 'application/pdf')],
        subject: _title.text.trim(),
      ));
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('PDF creation failed: $error')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Text to PDF')),
    body: SafeArea(child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 20),
      child: Column(children: [
        TextField(
          controller: _title,
          decoration: const InputDecoration(labelText: 'Document title',
              border: OutlineInputBorder()),
        ),
        const SizedBox(height: 12),
        Expanded(child: TextField(
          controller: _body,
          keyboardType: TextInputType.multiline,
          maxLines: null,
          expands: true,
          textAlignVertical: TextAlignVertical.top,
          decoration: const InputDecoration(
            hintText: 'Type or paste the document text',
            helperText: 'PDF export currently supports Latin-script text.',
            border: OutlineInputBorder(),
            alignLabelWithHint: true,
          ),
        )),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: _busy ? null : _export,
          icon: const Icon(Icons.picture_as_pdf_outlined),
          label: Text(_busy ? 'Preparing PDF…' : 'Create and Share PDF'),
          style: FilledButton.styleFrom(backgroundColor: dsTeal,
              minimumSize: const Size(double.infinity, 52)),
        ),
      ]),
    )),
  );
}
