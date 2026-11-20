import 'package:flutter/widgets.dart';

/// A QR code or barcode read on a live camera frame by libds_qr.so.
class LiveCode {
  const LiveCode({required this.format, required this.text,
      this.corners = const []});

  /// zxing-cpp format name, e.g. "QRCode", "EAN-13", "Code128".
  final String format;
  final String text;

  /// TL, TR, BR, BL in displayed, normalised [0, 1] coordinates.
  final List<Offset> corners;

  bool get isLink {
    final t = text.trim().toLowerCase();
    return t.startsWith('http://') || t.startsWith('https://');
  }

  /// Short, friendly name for the format.
  String get label {
    switch (format) {
      case 'QRCode':
      case 'MicroQRCode':
      case 'rMQRCode':
        return 'QR';
      case 'DataMatrix':
        return 'Data Matrix';
      default:
        return format;
    }
  }

  static List<LiveCode> listFrom(Object? raw) {
    if (raw is! List) return const [];
    final out = <LiveCode>[];
    for (final item in raw) {
      if (item is! Map) continue;
      final format = item['format'], text = item['text'];
      if (format is! String || text is! String || text.isEmpty) continue;
      final c = item['corners'];
      final corners = <Offset>[];
      if (c is List && c.length == 8) {
        for (var i = 0; i < 8; i += 2) {
          corners.add(Offset((c[i] as num).toDouble(), (c[i + 1] as num).toDouble()));
        }
      }
      out.add(LiveCode(format: format, text: text, corners: corners));
    }
    return out;
  }

  @override
  bool operator ==(Object other) =>
      other is LiveCode && other.format == format && other.text == text;

  @override
  int get hashCode => Object.hash(format, text);
}
