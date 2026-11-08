import 'package:docscanner/src/screens/photo_studio_screen.dart';
import 'package:docscanner/src/storage/document_store.dart';
import 'package:docscanner/src/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final mode in PhotoStudioMode.values) {
    testWidgets('${mode.name} opens real gallery/document editor',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: buildDocTheme(dark: false),
        home: PhotoStudioScreen(mode: mode, store: DocumentStore()),
      ));
      expect(find.text('Gallery'), findsOneWidget);
      expect(find.text('Camera'), findsOneWidget);
      expect(find.text('My Documents'), findsOneWidget);
      expect(find.textContaining('Not implemented'), findsNothing);
    });
  }
}
