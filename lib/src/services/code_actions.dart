import 'package:doclens/doclens.dart' show DoclensCodeActions;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

/// Actions for a QR code / barcode: open a link, copy, share. Used by the
/// live camera chip (libds_qr.so) and the Scan Code screen.
abstract final class CodeActions {
  static void install() {
    DoclensCodeActions.onTap = (context, code) =>
        show(context, code.text, code.label);
  }

  static bool isLink(String text) {
    final uri = Uri.tryParse(text.trim());
    return uri != null && (uri.scheme == 'http' || uri.scheme == 'https') &&
        uri.host.isNotEmpty;
  }

  static Future<void> show(BuildContext context, String text, String format) =>
      showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        builder: (sheet) => SafeArea(child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(format, style: const TextStyle(fontWeight: FontWeight.w700,
                fontSize: 13, color: Color(0xFF20C7B0))),
            const SizedBox(height: 6),
            SelectableText(text, style: const TextStyle(fontSize: 16)),
            const SizedBox(height: 14),
            Wrap(spacing: 8, runSpacing: 8, children: [
              if (isLink(text))
                FilledButton.icon(
                  key: const Key('code-open'),
                  onPressed: () {
                    Navigator.pop(sheet);
                    launchUrl(Uri.parse(text.trim()),
                        mode: LaunchMode.externalApplication);
                  },
                  icon: const Icon(Icons.open_in_new), label: const Text('Open'),
                ),
              OutlinedButton.icon(
                key: const Key('code-copy'),
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: text));
                  if (sheet.mounted) {
                    Navigator.pop(sheet);
                    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                        const SnackBar(content: Text('Code copied')));
                  }
                },
                icon: const Icon(Icons.copy_outlined), label: const Text('Copy'),
              ),
              OutlinedButton.icon(
                key: const Key('code-share'),
                onPressed: () {
                  Navigator.pop(sheet);
                  SharePlus.instance.share(ShareParams(text: text));
                },
                icon: const Icon(Icons.share_outlined), label: const Text('Share'),
              ),
            ]),
          ]),
        )),
      );
}
