import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../theme.dart';

/// Generates a shareable QR PNG entirely on-device using the existing
/// pdf/printing dependencies; no cloud service or additional plugin required.
class QrCodeScreen extends StatefulWidget {
  const QrCodeScreen({super.key});

  @override
  State<QrCodeScreen> createState() => _QrCodeScreenState();
}

class _QrCodeScreenState extends State<QrCodeScreen> {
  final _content = TextEditingController();
  Uint8List? _qrBytes;
  bool _busy = false;

  @override
  void dispose() {
    _content.dispose();
    super.dispose();
  }

  Future<void> _generate() async {
    final data = _content.text.trim();
    if (data.isEmpty) return;
    setState(() => _busy = true);
    try {
      final pdf = pw.Document();
      pdf.addPage(pw.Page(
        pageFormat: const PdfPageFormat(320, 320),
        margin: const pw.EdgeInsets.all(20),
        build: (_) => pw.Center(child: pw.BarcodeWidget(
          barcode: pw.Barcode.qrCode(),
          data: data,
          width: 280,
          height: 280,
          drawText: false,
        )),
      ));
      Uint8List? png;
      await for (final page in Printing.raster(await pdf.save(),
          pages: [0], dpi: 180)) {
        png = await page.toPng();
        break;
      }
      if (png == null) throw StateError('The QR image renderer returned no pages.');
      if (mounted) setState(() => _qrBytes = png);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('QR creation failed: $error')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _share() async {
    final bytes = _qrBytes;
    if (bytes == null) return;
    final directory = await getTemporaryDirectory();
    final file = File(p.join(directory.path,
        'docscanner_qr_${DateTime.now().microsecondsSinceEpoch}.png'));
    await file.writeAsBytes(bytes, flush: true);
    await SharePlus.instance.share(ShareParams(
      files: [XFile(file.path, mimeType: 'image/png')],
      subject: 'QR Code',
    ));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Create QR Code')),
    body: SafeArea(child: ListView(
      padding: const EdgeInsets.all(18),
      children: [
        TextField(
          controller: _content,
          maxLines: 3,
          minLines: 2,
          onChanged: (_) => setState(() => _qrBytes = null),
          decoration: const InputDecoration(
            labelText: 'Text, link or contact details',
            border: OutlineInputBorder(),
            alignLabelWithHint: true,
          ),
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: _busy ? null : _generate,
          icon: const Icon(Icons.qr_code),
          label: Text(_busy ? 'Generating…' : 'Generate QR Code'),
          style: FilledButton.styleFrom(backgroundColor: dsTeal),
        ),
        if (_qrBytes != null) ...[
          const SizedBox(height: 26),
          Center(child: Container(
            padding: const EdgeInsets.all(12),
            color: Colors.white,
            child: Image.memory(_qrBytes!, width: 250, height: 250),
          )),
          const SizedBox(height: 22),
          FilledButton.icon(
            onPressed: _share,
            icon: const Icon(Icons.share_outlined),
            label: const Text('Share QR PNG'),
          ),
        ],
      ],
    )),
  );
}
