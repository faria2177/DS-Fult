import 'package:docscanner/src/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('DocScanner can render a themed root widget', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: buildDocTheme(dark: false),
      home: const Scaffold(body: Center(child: Text('DocScanner'))),
    ));
    expect(find.text('DocScanner'), findsOneWidget);
  });
}
