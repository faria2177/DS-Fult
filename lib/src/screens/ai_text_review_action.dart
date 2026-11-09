import 'package:flutter/material.dart';

import '../services/ai_text_gateway.dart';

/// A per-action privacy boundary: only explicitly confirmed OCR text is sent.
/// The caller must apply the result to its own reversible editor history.
abstract final class AiTextReviewAction {
  static Future<String?> run(BuildContext context, {
    required String text,
    required AiTextTask task,
    AiTextEngine? engine,
  }) async {
    final gateway = engine ?? AiTextGateway();
    AiTextConfig? config;
    try {
      config = await gateway.activeConfiguration();
    } catch (_) {
      if (context.mounted) {
        await _message(context, 'AI settings unavailable',
          'Could not access your saved AI settings. Try again.');
      }
      return null;
    }
    if (!context.mounted) return null;
    if (config == null) {
      await _message(context, 'AI Mode is not ready',
        'In Me → AI Mode, save a key, select Google AI Studio, Groq or '
        'OpenRouter, and enable AI Mode. Other provider keys are setup-only.');
      return null;
    }
    if (text.trim().isEmpty || text.length > AiTextGateway.maxInputCharacters) {
      await _message(context, 'Text length',
        'Choose non-empty text of up to 12,000 characters per request.');
      return null;
    }

    final consent = await showDialog<bool>(context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Send text to external AI?'),
        content: SingleChildScrollView(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Provider: ${config.providerName}'),
            Text('Model: ${config.modelId}'),
            Text('Text length: ${text.length} characters'),
            const SizedBox(height: 11),
            const Text('The current page\'s editable OCR text will be '
              'sent to this external provider for processing. This may '
              'incur costs or consume a free quota. No scan image, file '
              'name or other page is sent. Do not send confidential text '
              'unless you accept the provider\'s privacy terms.'),
            const SizedBox(height: 12),
            const Text('Text preview:', style: TextStyle(
              fontWeight: FontWeight.w600)),
            Text(text.length > 240 ? '${text.substring(0, 240)}…' : text,
              maxLines: 5, overflow: TextOverflow.ellipsis),
          ],
        )),
        actions: [
          TextButton(key: const Key('ai-cancel-send'),
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel')),
          FilledButton(key: const Key('ai-confirm-send'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Send text')),
        ],
      ));
    if (!context.mounted || consent != true) return null;

    try {
      final proposal = await gateway.rewrite(config: config, task: task,
        text: text);
      if (!context.mounted) return null;
      return showDialog<String>(context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Review AI suggestion'),
          content: SizedBox(width: double.maxFinite,
            child: SingleChildScrollView(child: SelectableText(proposal,
              key: const Key('ai-text-result')))),
          actions: [
            TextButton(key: const Key('ai-discard-result'),
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Discard')),
            FilledButton(key: const Key('ai-apply-result'),
              onPressed: () => Navigator.of(dialogContext).pop(proposal),
              child: const Text('Apply changes')),
          ],
        ));
    } catch (error) {
      if (!context.mounted) return null;
      // Unknown exception text could expose HTTP headers or user data.
      final message = error is AiTextException
          ? error.message : 'Request failed. Your text was not changed.';
      await _message(context, 'AI request not completed', message);
      return null;
    }
  }

  static Future<void> _message(BuildContext context,
      String title, String description) => showDialog<void>(context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(title),
      content: Text(description),
      actions: [TextButton(onPressed: () => Navigator.pop(dialogContext),
        child: const Text('OK'))],
    ));
}
