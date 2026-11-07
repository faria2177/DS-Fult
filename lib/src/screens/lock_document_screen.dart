import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';

import '../storage/document_store.dart';
import '../theme.dart';

/// Device-local access lock. This is intentionally not labeled as PDF
/// encryption: exported copies remain unencrypted.
class LockDocumentScreen extends StatefulWidget {
  const LockDocumentScreen({
    super.key,
    required this.store,
    required this.documentId,
  });

  final DocumentStore store;
  final String documentId;

  @override
  State<LockDocumentScreen> createState() => _LockDocumentScreenState();
}

class _LockDocumentScreenState extends State<LockDocumentScreen> {
  final _password = TextEditingController();
  final _confirmation = TextEditingController();
  bool _showPassword = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    _confirmation.dispose();
    super.dispose();
  }

  String _hash(String pin) => sha256.convert(
      utf8.encode('${widget.documentId}:$pin')).toString();

  Future<void> _lock() async {
    final password = _password.text;
    if (password.length < 6) {
      setState(() => _error = 'Password must be at least 6 characters.');
      return;
    }
    if (password != _confirmation.text) {
      setState(() => _error = 'Passwords do not match.');
      return;
    }
    setState(() { _busy = true; _error = null; });
    try {
      await widget.store.setLockHash(widget.documentId, _hash(password));
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final doc = widget.store.byId(widget.documentId);
    if (doc == null) {
      return const Scaffold(body: Center(child: Text('Document not found')));
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Lock')),
      body: SafeArea(child: Column(children: [
        if (_busy) const LinearProgressIndicator(),
        Expanded(child: ListView(padding: const EdgeInsets.all(20), children: [
          const SizedBox(height: 20),
          const Center(child: Icon(Icons.lock_outline, size: 56, color: dsTeal)),
          const SizedBox(height: 12),
          Text(doc.name, textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 16),
          if (doc.lockHash != null)
            const Text('This document already has a lock. Open it from Files '
                'and enter your password to access the pages.'),
          if (doc.lockHash == null) ...[
            TextField(
              controller: _password,
              obscureText: !_showPassword,
              decoration: InputDecoration(
                labelText: 'Enter password',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  onPressed: () => setState(() => _showPassword = !_showPassword),
                  icon: Icon(_showPassword ? Icons.visibility :
                      Icons.visibility_off),
                ),
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _confirmation,
              obscureText: !_showPassword,
              decoration: const InputDecoration(
                labelText: 'Confirm password',
                border: OutlineInputBorder(),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: TextStyle(
                color: Theme.of(context).colorScheme.error)),
            ],
            const SizedBox(height: 16),
            const Text('Password must be at least 6 characters.'),
            const SizedBox(height: 9),
            const Text('This protects access inside DocScanner. Exported '
                'PDFs and original image files are not encrypted.',
                style: TextStyle(color: dsMuted)),
          ],
        ])),
        Padding(padding: const EdgeInsets.all(16), child: Row(children: [
          Expanded(child: OutlinedButton(
            onPressed: _busy ? null : () => Navigator.pop(context),
            child: const Text('Cancel'))),
          const SizedBox(width: 10),
          Expanded(child: FilledButton(
            onPressed: _busy || doc.lockHash != null ? null : _lock,
            child: const Text('Lock'))),
        ])),
      ])),
    );
  }
}
