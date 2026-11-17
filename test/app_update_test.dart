import 'package:docscanner/src/screens/updates_screen.dart';
import 'package:docscanner/src/services/app_update_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, dynamic> _release(String tag, {List<String> assets = const [
    'DocScanner-arm64-v8a.apk'], bool prerelease = false, String body = ''}) =>
    {
      'tag_name': tag,
      'name': 'DocScanner $tag',
      'body': body,
      'draft': false,
      'prerelease': prerelease,
      'published_at': '2026-11-17T08:00:00Z',
      'html_url': 'https://github.com/faria2177/DS-Fult/releases/tag/$tag',
      'assets': [
        for (final name in assets)
          {
            'name': name,
            'size': 1000,
            'browser_download_url':
                'https://github.com/faria2177/DS-Fult/releases/download/$tag/$name',
          },
      ],
    };

class _FakeService extends AppUpdateService {
  _FakeService(this.result);
  final UpdateCheck result;
  @override
  Future<UpdateCheck> check() async => result;
}

void main() {
  group('AppVersion', () {
    test('reads tags and build numbers', () {
      final v = AppVersion.tryParse('v0.5.41+55')!;
      expect(v.parts, [0, 5, 41]);
      expect(v.build, 55);
      expect(v.label, 'v0.5.41');
      expect(AppVersion.tryParse('0.5.41')!.build, isNull);
      expect(AppVersion.tryParse('nothing'), isNull);
    });

    test('compares like version numbers, not text', () {
      final a = AppVersion.tryParse('0.5.9')!;
      final b = AppVersion.tryParse('0.5.41')!;
      expect(b.isNewerThan(a), isTrue);
      expect(AppVersion.tryParse('1.0')!.isNewerThan(
          AppVersion.tryParse('0.9.99')!), isTrue);
      expect(AppVersion.tryParse('0.5.41+56')!.isNewerThan(
          AppVersion.tryParse('0.5.41+55')!), isTrue);
      // A missing build number never invents an update.
      expect(AppVersion.tryParse('0.5.41')!.isNewerThan(
          AppVersion.tryParse('0.5.41+55')!), isFalse);
    });
  });

  test('release parsing skips pre-releases and releases without an APK', () {
    expect(AppRelease.fromGitHub(_release('v0.5.41+55', prerelease: true)),
        isNull);
    expect(AppRelease.fromGitHub(_release('v0.5.41+55', assets: ['a.zip'])),
        isNull);
    final release = AppRelease.fromGitHub(_release('v0.5.41+55',
        assets: ['DocScanner-armeabi.apk', 'DocScanner-arm64-v8a.apk']))!;
    expect(release.apkUrl, endsWith('arm64-v8a.apk'));
    expect(release.version.build, 55);
  });

  test('check result lists only newer releases', () {
    final installed = AppVersion.tryParse('0.5.40+54')!;
    final releases = [
      for (final tag in ['v0.5.42+56', 'v0.5.41+55', 'v0.5.40+54'])
        AppRelease.fromGitHub(_release(tag))!,
    ];
    final result = UpdateCheck(installed: installed, releases: releases);
    expect(result.updateAvailable, isTrue);
    expect(result.latest!.version.label, 'v0.5.42');
    expect(result.missed.map((r) => r.version.label), ['v0.5.42', 'v0.5.41']);
  });

  test('Later pauses the prompt for the same version only', () async {
    SharedPreferences.setMockInitialValues({});
    final v41 = AppVersion.tryParse('0.5.41+55')!;
    final v42 = AppVersion.tryParse('0.5.42+56')!;
    expect(await AppUpdateService.shouldPrompt(v41), isTrue);
    await AppUpdateService.rememberPrompt(v41);
    expect(await AppUpdateService.shouldPrompt(v41), isFalse);
    expect(await AppUpdateService.shouldPrompt(v42), isTrue);
    expect(await AppUpdateService.shouldPrompt(v41,
        now: DateTime.now().add(const Duration(days: 1))), isTrue);
  });

  testWidgets('launch dialog shows both versions and opens Updates',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final result = UpdateCheck(
      installed: AppVersion.tryParse('0.5.40+54')!,
      releases: [AppRelease.fromGitHub(_release('v0.5.41+55',
          body: '## Highlights\n- Faster auto crop\n- New update screen'))!],
    );
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) =>
        Scaffold(body: TextButton(
          onPressed: () => checkForUpdateOnLaunch(context,
              service: _FakeService(result)),
          child: const Text('Launch'))))));
    await tester.tap(find.text('Launch'));
    await tester.pumpAndSettle();

    expect(find.text('Update Available'), findsOneWidget);
    expect(find.text('v0.5.40'), findsOneWidget);
    expect(find.text('v0.5.41'), findsOneWidget);
    await tester.tap(find.byKey(const Key('update-view')));
    await tester.pumpAndSettle();

    expect(find.text('Update Available!'), findsOneWidget);
    expect(find.text('Download & Install v0.5.41'), findsOneWidget);
    expect(find.text('Faster auto crop'), findsOneWidget);

    await tester.tap(find.byKey(const Key('update-download-install')));
    await tester.pumpAndSettle();
    expect(find.text('Download Update?'), findsOneWidget);
    await tester.tap(find.byKey(const Key('update-not-now')));
    await tester.pumpAndSettle();
    expect(find.text('Download Update?'), findsNothing);
  });

  testWidgets('an up-to-date app says so and offers no download',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final result = UpdateCheck(
      installed: AppVersion.tryParse('0.5.41+55')!,
      releases: [AppRelease.fromGitHub(_release('v0.5.41+55'))!],
    );
    await tester.pumpWidget(MaterialApp(home: UpdatesScreen(
        service: _FakeService(result), initial: result)));
    await tester.pumpAndSettle();
    expect(find.text("You're up to date"), findsOneWidget);
    expect(find.byKey(const Key('update-download-install')), findsNothing);

    final autoCheck = find.byKey(const Key('update-auto-check'));
    await tester.scrollUntilVisible(autoCheck, 200,
        scrollable: find.byType(Scrollable).first);
    await tester.ensureVisible(autoCheck);
    await tester.pumpAndSettle();
    expect(tester.widget<SwitchListTile>(autoCheck).value, isTrue);
    await tester.tap(find.descendant(of: autoCheck,
        matching: find.byType(Switch)));
    await tester.pumpAndSettle();
    expect(tester.widget<SwitchListTile>(autoCheck).value, isFalse);
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    });
    expect(await AppUpdateService.autoCheckEnabled(), isFalse);
  });

  testWidgets('a pending launch check never pops up when autocheck is off',
      (tester) async {
    SharedPreferences.setMockInitialValues({'update_auto_check': false});
    final result = UpdateCheck(
      installed: AppVersion.tryParse('0.5.40+54')!,
      releases: [AppRelease.fromGitHub(_release('v0.5.41+55'))!],
    );
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) =>
        Scaffold(body: TextButton(
          onPressed: () => checkForUpdateOnLaunch(context,
              service: _FakeService(result)),
          child: const Text('Launch'))))));
    await tester.tap(find.text('Launch'));
    await tester.pumpAndSettle();
    expect(find.text('Update Available'), findsNothing);
  });
}
