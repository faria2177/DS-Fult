import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_barcode_scanning/google_mlkit_barcode_scanning.dart';
import 'package:image_picker/image_picker.dart';
import 'package:share_plus/share_plus.dart';

import '../theme.dart';

/// Reads QR and common linear/2D barcodes from a captured or imported image.
/// Uses the bundled on-device ML Kit processor with no network endpoint.
class ScanCodeScreen extends StatefulWidget {
  const ScanCodeScreen({super.key});

  @override
  State<ScanCodeScreen> createState() => _ScanCodeScreenState();
}

class _CodeResult {
  const _CodeResult(this.format, this.value);
  final String format;
  final String value;
}

class _ScanCodeScreenState extends State<ScanCodeScreen> {
  final _picker = ImagePicker();
  List<_CodeResult> _codes = const [];
  String? _photoPath;
  String? _notice;
  bool _busy = false;

  Future<void> _scan(ImageSource source) async {
    if (_busy) return;
    try {
      final image = await _picker.pickImage(source: source,
          imageQuality: 95, maxWidth: 3000, maxHeight: 3000);
      if (image == null || !mounted) return;
      setState(() { _busy = true; _codes = []; _notice = null; _photoPath = image.path; });
      final scanner = BarcodeScanner(formats: const [BarcodeFormat.all]);
      try {
        final decoded = await scanner.processImage(InputImage.fromFilePath(image.path));
        final unique = <String>{};
        final found = <_CodeResult>[];
        for (final code in decoded) {
          final value = (code.rawValue ?? code.displayValue ?? '').trim();
          if (value.isEmpty || !unique.add(value)) continue;
          found.add(_CodeResult(code.format.name, value));
        }
        if (mounted) {
          setState(() {
            _codes = found;
            _notice = found.isEmpty
                ? 'No QR or barcode found. Try a brighter, sharper picture.'
                : '${found.length} code(s) found';
          });
        }
      } finally {
        await scanner.close();
      }
    } catch (error) {
      if (mounted) {
        setState(() => _notice = 'Could not scan the code: $error');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _copy(String value) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Code copied')),
      );
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Scan Code')),
    body: SafeArea(child: ListView(padding: const EdgeInsets.all(16), children: [
      const Text('Scan QR, EAN, Code 128, Data Matrix and more',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
      const SizedBox(height: 6),
      const Text('Capture a clear image or select one from your gallery. '
          'Detection runs locally on your phone.',
          style: TextStyle(color: dsMuted)),
      const SizedBox(height: 20),
      Row(children: [
        Expanded(child: FilledButton.icon(
          onPressed: _busy ? null : () => _scan(ImageSource.camera),
          icon: const Icon(Icons.camera_alt_outlined),
          label: const Text('Camera'),
          style: FilledButton.styleFrom(backgroundColor: dsTeal),
        )),
        const SizedBox(width: 12),
        Expanded(child: OutlinedButton.icon(
          onPressed: _busy ? null : () => _scan(ImageSource.gallery),
          icon: const Icon(Icons.photo_library_outlined),
          label: const Text('Gallery'),
        )),
      ]),
      if (_busy) ...[
        const SizedBox(height: 22),
        const LinearProgressIndicator(),
      ],
      if (_photoPath != null) ...[
        const SizedBox(height: 24),
        ClipRRect(borderRadius: BorderRadius.circular(12),
          child: Image.file(File(_photoPath!), height: 230, fit: BoxFit.contain)),
      ],
      if (_notice != null) ...[
        const SizedBox(height: 16),
        Text(_notice!, style: const TextStyle(fontWeight: FontWeight.w600)),
      ],
      for (final result in _codes) ...[
        const SizedBox(height: 12),
        Card(child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(result.format.toUpperCase(),
                style: const TextStyle(color: dsTeal, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            SelectableText(result.value),
            const SizedBox(height: 10),
            Row(children: [
              TextButton.icon(onPressed: () => _copy(result.value),
                  icon: const Icon(Icons.copy_outlined), label: const Text('Copy')),
              TextButton.icon(onPressed: () => SharePlus.instance.share(
                  ShareParams(text: result.value)),
                  icon: const Icon(Icons.share_outlined), label: const Text('Share')),
            ]),
          ]),
        )),
      ],
    ])),
  );
}
