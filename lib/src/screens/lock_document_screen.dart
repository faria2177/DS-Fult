import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';

import '../storage/document_store.dart';
import 'video_tool_style.dart';

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
    return Theme(data: ThemeData.light(useMaterial3: true),
      child: Scaffold(
        backgroundColor: const Color(0xFFF8F9FC),
        appBar: AppBar(title: const Text('Lock'), backgroundColor: Colors.white),
        body: SafeArea(child: Stack(children: [
          Positioned.fill(child: Padding(padding: const EdgeInsets.all(22),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Lock', style: TextStyle(fontSize: 30,
                    fontWeight: FontWeight.w600)),
                const SizedBox(height: 7),
                const Text('Protect your documents with a password.'),
                const SizedBox(height: 28),
                const Text('Selected from This App',
                    style: TextStyle(fontWeight: FontWeight.w500)),
                const SizedBox(height: 12),
                Card(color: Colors.white, child: ListTile(
                  leading: const Icon(Icons.picture_as_pdf,
                      color: VideoToolStyle.teal, size: 42),
                  title: Text(doc.name),
                  subtitle: Text('${doc.pages.length} Page(s)'),
                  trailing: doc.lockHash != null
                      ? const Icon(Icons.lock, color: VideoToolStyle.teal)
                      : null,
                )),
              ],
            ),
          )),
          Positioned.fill(child: Container(color: Colors.black38)),
          Align(alignment: Alignment.bottomCenter,
            child: Container(
              width: double.infinity,
              constraints: const BoxConstraints(maxWidth: 620),
              decoration: const BoxDecoration(
                color: Color(0xFF1B1D29),
                borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
              child: SingleChildScrollView(padding: const EdgeInsets.fromLTRB(
                22, 14, 22, 24), child: Column(mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(width: 48, height: 5, decoration: BoxDecoration(
                      color: const Color(0xFF454957),
                      borderRadius: BorderRadius.circular(3))),
                    const SizedBox(height: 15),
                    const Text('Lock Document', style: TextStyle(
                      color: Colors.white, fontSize: 21,
                      fontWeight: FontWeight.w500)),
                    const SizedBox(height: 11),
                    const Text('A password will be required to view this '
                      'document inside DocScanner.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white70, fontSize: 13)),
                    const SizedBox(height: 24),
                    if (_busy) const LinearProgressIndicator(),
                    if (doc.lockHash != null)
                      const Text('Already locked. Unlock from Files.',
                        style: TextStyle(color: Colors.white))
                    else ...[
                      TextField(controller: _password,
                        obscureText: !_showPassword,
                        autofocus: true,
                        onChanged: (_) => setState(() => _error = null),
                        style: const TextStyle(color: Color(0xFF252732)),
                        decoration: InputDecoration(
                          hintText: 'Enter password',
                          filled: true, fillColor: const Color(0xFFF0F2F7),
                          border: OutlineInputBorder(borderRadius:
                              BorderRadius.circular(12)),
                          suffixIcon: IconButton(
                            onPressed: () => setState(() =>
                                _showPassword = !_showPassword),
                            icon: Icon(_showPassword ? Icons.visibility :
                                Icons.visibility_off),
                          ),
                        ),
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 7),
                        Align(alignment: Alignment.centerLeft,
                          child: Text(_error!, style: const TextStyle(
                            color: Color(0xFFFF4A51), fontSize: 12))),
                      ],
                      const SizedBox(height: 16),
                      TextField(controller: _confirmation,
                        obscureText: !_showPassword,
                        onChanged: (_) => setState(() => _error = null),
                        style: const TextStyle(color: Color(0xFF252732)),
                        decoration: InputDecoration(
                          hintText: 'Confirm password',
                          filled: true, fillColor: const Color(0xFFF0F2F7),
                          border: OutlineInputBorder(borderRadius:
                              BorderRadius.circular(12)),
                          suffixIcon: Icon(_showPassword ? Icons.visibility :
                              Icons.visibility_off),
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Align(alignment: Alignment.centerLeft,
                        child: Text('Password must be at least 6 characters.',
                          style: TextStyle(color: Colors.white60, fontSize: 11))),
                    ],
                    const SizedBox(height: 22),
                    Row(children: [
                      Expanded(child: FilledButton(
                        style: VideoToolStyle.greyButton,
                        onPressed: _busy ? null : () => Navigator.pop(context),
                        child: const Text('Cancel'))),
                      const SizedBox(width: 12),
                      Expanded(child: FilledButton(
                        style: VideoToolStyle.tealButton,
                        onPressed: _busy || doc.lockHash != null ? null : _lock,
                        child: const Text('Lock'))),
                    ]),
                    const SizedBox(height: 11),
                    const Text('App-only access lock: exported PDFs are not encrypted.',
                      textAlign: TextAlign.center, style: TextStyle(
                        color: Colors.white54, fontSize: 11)),
                  ],
                ),
              ),
            ),
          ),
        ])),
      ),
    );
  }
}
