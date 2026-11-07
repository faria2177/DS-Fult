import 'package:doclens/doclens.dart';
import 'package:docscanner/src/screens/home_shell.dart';
import 'package:docscanner/src/screens/scan_more_settings_screen.dart';
import 'package:docscanner/src/services/scan_settings_store.dart';
import 'package:docscanner/src/storage/document_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('Me has one Scan entry which opens all seven live preferences',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 1280));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final store = DocumentStore();
    addTearDown(store.dispose);

    await tester.pumpWidget(MaterialApp(home: HomeShell(
      store: store,
      darkTheme: false,
      onThemeChanged: (_) {},
    )));
    await tester.tap(find.text('Me'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('me-scan-settings')), findsOneWidget);
    await tester.tap(find.byKey(const Key('me-scan-settings')));
    await tester.pumpAndSettle();
    for (final title in const [
      'Auto Adjust Borders',
      'Adjust After Each Scan',
      'Start with Camera',
      'Use System Camera',
      'Import from Gallery',
      'Save Scans to Gallery After Scanning',
      'Double-Focus',
    ]) {
      expect(find.text(title), findsOneWidget);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('all seven Scan switches change their corresponding flags',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 1280));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final settings = ReferenceScanSettings();
    addTearDown(settings.dispose);
    await tester.pumpWidget(MaterialApp(home:
      ScanMoreSettingsScreen(settings: settings)));

    for (final entry in const [
      ('Auto Adjust Borders', 'autoAdjustBorders'),
      ('Adjust After Each Scan', 'adjustAfterEachScan'),
      ('Start with Camera', 'startWithCamera'),
      ('Use System Camera', 'useSystemCamera'),
      ('Import from Gallery', 'importFromGallery'),
      ('Save Scans to Gallery After Scanning', 'saveScansToGallery'),
      ('Double-Focus', 'doubleFocus'),
    ]) {
      final before = settings.flag(entry.$2);
      final tile = find.widgetWithText(SwitchListTile, entry.$1);
      expect(tile, findsOneWidget);
      await tester.tap(tile);
      await tester.pump();
      expect(settings.flag(entry.$2), !before, reason: entry.$1);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('Tools no longer offers the nine removed actions',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 1280));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final store = DocumentStore();
    addTearDown(store.dispose);
    await tester.pumpWidget(MaterialApp(home: HomeShell(
      store: store,
      darkTheme: false,
      onThemeChanged: (_) {},
    )));
    await tester.tap(find.text('Tools'));
    await tester.pumpAndSettle();
    final search = find.byType(TextField);
    expect(search, findsOneWidget);
    for (final name in const [
      'Mega Scan', 'Long Document', 'Driver License', 'Bank Card',
      'Photo Translation', 'Scan Code', 'To PPT', 'Erase Marks',
      'Restore Photo',
    ]) {
      await tester.enterText(search, name);
      await tester.pumpAndSettle();
      expect(find.text(name), findsNothing, reason: name);
    }
    await tester.enterText(search, 'ID Cards');
    await tester.pumpAndSettle();
    expect(find.text('ID Cards'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('rapid shared setting updates persist in the correct order', () async {
    final settings = ReferenceScanSettings();
    addTearDown(settings.dispose);
    settings.setFlag('startWithCamera', true);
    final first = ScanSettingsStore.save(settings);
    settings.setFlag('startWithCamera', false);
    settings.setFlag('doubleFocus', true);
    final second = ScanSettingsStore.save(settings);
    await Future.wait([first, second]);
    final stored = await ScanSettingsStore.load();
    addTearDown(stored.dispose);
    expect(stored.startWithCamera, isFalse);
    expect(stored.doubleFocus, isTrue);
  });
}
