import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../models.dart';
import '../storage/document_store.dart';
import '../theme.dart';
import 'camera_screen.dart';
import 'document_screen.dart';

class IdCardScreen extends StatefulWidget {
  const IdCardScreen({super.key, required this.store, required this.kind});

  final DocumentStore store;
  final DocumentKind kind;

  @override
  State<IdCardScreen> createState() => _IdCardScreenState();
}

class _IdCardScreenState extends State<IdCardScreen> {
  final List<String> _selected = [];
  final _picker = ImagePicker();
  bool _saving = false;

  void _warn(String message) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _import() async {
    final remaining = 2 - _selected.length;
    if (remaining <= 0) {
      _warn('Only 2 images are allowed: front and back.');
      return;
    }
    try {
      List<String> paths;
      if (remaining == 1) {
        final single = await _picker.pickImage(source: ImageSource.gallery);
        paths = single == null ? [] : [single.path];
      } else {
        final photos = await _picker.pickMultiImage(
          limit: remaining,
          requestFullMetadata: false,
        );
        paths = photos.map((photo) => photo.path).toList();
      }
      if (!mounted) return;
      if (paths.length > remaining) {
        _warn('Please select a maximum of $remaining image(s).');
        return;
      }
      setState(() => _selected.addAll(paths));
    } catch (error) {
      _warn('Import failed: $error');
    }
  }

  Future<void> _capture() async {
    if (_selected.length >= 2) {
      _warn('You already have front and back photos.');
      return;
    }
    final paths = await Navigator.push<List<String>>(context, MaterialPageRoute(
      builder: (_) => CameraScreen(
        cardMode: true,
        side: _selected.isEmpty ? 'Front' : 'Back',
      ),
    ));
    if (paths == null || !mounted) return;
    final remaining = 2 - _selected.length;
    if (paths.length > remaining) {
      _warn('Only $remaining more image(s) allowed.');
      return;
    }
    setState(() => _selected.addAll(paths));
  }

  Future<void> _finish() async {
    if (_selected.isEmpty || _saving) return;
    setState(() => _saving = true);
    try {
      final document = await widget.store.createFromPaths(
        _selected, kind: widget.kind,
      );
      if (!mounted) return;
      await Navigator.push<void>(context, MaterialPageRoute(
        builder: (_) => DocumentScreen(store: widget.store, documentId: document.id),
      ));
      if (mounted) Navigator.pop(context);
    } catch (error) {
      _warn('Could not save card: $error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(widget.kind.label), actions: [
          TextButton(onPressed: _selected.isEmpty ? null : _finish, child: const Text('Done',
              style: TextStyle(color: dsTeal, fontWeight: FontWeight.bold))),
        ]),
        body: SafeArea(child: Column(children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 10, 20, 6),
            child: Text('Capture or import the two sides of your card',
                textAlign: TextAlign.center, style: TextStyle(fontSize: 15)),
          ),
          const SizedBox(height: 8),
          Expanded(child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 22),
            children: [
              for (var i = 0; i < 2; i++) ...[
                _side(i),
                const SizedBox(height: 17),
              ],
              Row(children: [
                const Icon(Icons.info_outline, size: 18, color: dsMuted),
                const SizedBox(width: 8),
                Expanded(child: Text('Gallery selection limit: 2 images total. ${_selected.length}/2 selected.',
                  style: const TextStyle(fontSize: 12, color: dsMuted))),
              ]),
            ],
          )),
          if (_saving) const LinearProgressIndicator(color: dsTeal),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 18),
            child: Row(children: [
              Expanded(child: OutlinedButton.icon(
                onPressed: _selected.length >= 2 ? null : _import,
                icon: const Icon(Icons.photo_library_outlined), label: const Text('Import Gallery'),
              )),
              const SizedBox(width: 14),
              Expanded(child: FilledButton.icon(
                onPressed: _selected.isEmpty ? null : _finish,
                icon: const Icon(Icons.check), label: const Text('Make it now'),
              )),
            ]),
          ),
        ])),
      );

  Widget _side(int index) {
    final filled = index < _selected.length;
    return InkWell(
      onTap: filled ? null : _capture,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        height: 185,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: filled ? dsTeal : dsTeal.withValues(alpha: .35), width: 1.6),
        ),
        child: Stack(children: [
          if (filled)
            Positioned.fill(child: Padding(padding: const EdgeInsets.all(9),
              child: ClipRRect(borderRadius: BorderRadius.circular(12),
                child: Image.file(File(_selected[index]), fit: BoxFit.contain)))),
          if (!filled)
            Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.add_a_photo_outlined, color: dsTeal, size: 38),
              const SizedBox(height: 8),
              Text(index == 0 ? 'Front' : 'Back',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const Text('Tap to scan', style: TextStyle(color: dsMuted)),
            ])),
          Positioned(left: 11, top: 11, child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(20)),
            child: Text(index == 0 ? 'Front' : 'Back',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
          )),
          if (filled)
            Positioned(right: 4, top: 4, child: IconButton(
              tooltip: 'Remove image', icon: const Icon(Icons.cancel, color: Colors.redAccent),
              onPressed: () => setState(() => _selected.removeAt(index)),
            )),
        ]),
      ),
    );
  }
}
