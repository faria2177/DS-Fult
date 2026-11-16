import 'dart:typed_data';

import 'package:docscanner/src/models.dart';
import 'package:docscanner/src/screens/compress_screen.dart';
import 'package:docscanner/src/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Medium and High update exact PDF size beside Compress',
      (tester) async {
    final document = ScanDocument(
      id: 'sample', name: 'Example document',
      createdAt: DateTime(2026, 11, 16),
      pages: const [],
    );
    final requested = <CompressionLevel?>[];
    await tester.pumpWidget(MaterialApp(
      theme: buildDocTheme(dark: false),
      home: CompressScreen(
        document: document,
        pdfBytesBuilder: (level) async {
          requested.add(level);
          return Uint8List(level == null
              ? 4000
              : level == CompressionLevel.medium ? 2700 : 1200);
        },
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Compress  ·  2.6 KB'), findsOneWidget);
    expect(find.textContaining('smaller than original PDF'), findsOneWidget);

    await tester.tap(find.text('High'));
    await tester.pumpAndSettle();
    expect(find.text('Compress  ·  1.2 KB'), findsOneWidget);
    expect(requested, containsAllInOrder([
      null, CompressionLevel.medium, CompressionLevel.high,
    ]));

    // Selecting the already measured level uses the exact cached PDF bytes
    // and does not run a second expensive conversion.
    final before = requested.length;
    await tester.tap(find.text('Medium'));
    await tester.pumpAndSettle();
    expect(find.text('Compress  ·  2.6 KB'), findsOneWidget);
    expect(requested.length, before);
  });
}
