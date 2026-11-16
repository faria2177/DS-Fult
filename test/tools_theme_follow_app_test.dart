import 'package:docscanner/src/screens/home_shell.dart';
import 'package:docscanner/src/storage/document_store.dart';
import 'package:docscanner/src/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Tools follows Light and Dark without forcing black',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final documents = DocumentStore();
    Widget shell(bool dark) => MaterialApp(
      theme: buildDocTheme(dark: dark),
      home: HomeShell(
        store: documents,
        darkTheme: dark,
        onThemeChanged: (_) {},
      ),
    );

    await tester.pumpWidget(shell(false));
    await tester.pump();
    await tester.tap(find.text('Tools'));
    await tester.pump();
    final light = tester.widget<ColoredBox>(
      find.byKey(const Key('tools-tab-background')),
    );
    expect(light.color, dsPaper);
    expect(find.text('BG Remover'), findsOneWidget);

    await tester.pumpWidget(shell(true));
    await tester.pump();
    final dark = tester.widget<ColoredBox>(
      find.byKey(const Key('tools-tab-background')),
    );
    expect(dark.color, const Color(0xFF101519));
    expect(dark.color, isNot(light.color));
  });
}
