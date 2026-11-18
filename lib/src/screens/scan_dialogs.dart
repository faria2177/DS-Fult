import 'package:flutter/material.dart';

import '../theme.dart';

/// CamScanner-style confirmation shown when the user leaves a scan that
/// has not been kept yet. Returns true only when "Discard" is pressed.
Future<bool> confirmDiscardScans(BuildContext context) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (dialog) => AlertDialog(
      backgroundColor: const Color(0xFF2C2C2F),
      title: const Text('Discard Scans',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
      content: const Text('Closing will discard the scans you captured.',
          style: TextStyle(color: Colors.white70)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dialog, false),
            child: const Text('Cancel',
                style: TextStyle(color: Colors.white70))),
        TextButton(onPressed: () => Navigator.pop(dialog, true),
            child: const Text('Discard', style: TextStyle(color: dsTeal,
                fontWeight: FontWeight.bold))),
      ],
    ),
  );
  return result ?? false;
}

/// Progress of a multi-image processing job: processed / total.
class ScanProgress {
  const ScanProgress(this.processed, this.total);
  final int processed;
  final int total;

  double? get fraction => total <= 0 ? null : (processed / total).clamp(0.0, 1.0).toDouble();
}

/// Non-dismissible "Processing… N%  x/y" dialog. Update [progress] while
/// working and call the returned function to close it.
VoidCallback showProcessingDialog(BuildContext context,
    ValueNotifier<ScanProgress> progress) {
  final navigator = Navigator.of(context, rootNavigator: true);
  var open = true;
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    useRootNavigator: true,
    builder: (_) => PopScope(
      canPop: false,
      child: Dialog(
        backgroundColor: const Color(0xFF2C2C2F),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
          child: ValueListenableBuilder<ScanProgress>(
            valueListenable: progress,
            builder: (_, value, _) {
              final fraction = value.fraction;
              final percent = fraction == null ? null
                  : (fraction * 100).round();
              return Column(mainAxisSize: MainAxisSize.min, children: [
                Row(children: [
                  Text(percent == null ? 'Processing…'
                      : 'Processing… $percent%',
                      key: const Key('processing-label'),
                      style: const TextStyle(color: Colors.white,
                          fontSize: 16)),
                  const Spacer(),
                  if (value.total > 0)
                    Text('${value.processed}/${value.total}',
                        style: const TextStyle(color: Colors.white60)),
                ]),
                const SizedBox(height: 14),
                LinearProgressIndicator(value: fraction, color: dsTeal,
                    backgroundColor: Colors.white12),
              ]);
            },
          ),
        ),
      ),
    ),
  ).whenComplete(() => open = false);
  return () {
    if (open && navigator.mounted) {
      open = false;
      navigator.pop();
    }
  };
}
