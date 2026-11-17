import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A version such as `0.5.41+55` (name 0.5.41, build 55).
@immutable
class AppVersion implements Comparable<AppVersion> {
  const AppVersion(this.parts, this.build);

  /// Parses `v0.5.41+55`, `0.5.41`, `0.5.41-b55` and similar tags.
  /// Returns null when no number can be read.
  static AppVersion? tryParse(String? text) {
    if (text == null) return null;
    final match = RegExp(r'(\d+(?:\.\d+)*)(?:[+\-_ ]?(?:b|build)?(\d+))?')
        .firstMatch(text.trim());
    if (match == null) return null;
    final parts = [for (final part in match.group(1)!.split('.'))
        int.parse(part)];
    final build = match.group(2) == null ? null : int.tryParse(match.group(2)!);
    return AppVersion(parts, build);
  }

  final List<int> parts;
  final int? build;

  /// Shown to the user, e.g. `v0.5.41`.
  String get label => 'v${parts.join('.')}';

  @override
  int compareTo(AppVersion other) {
    final length = parts.length > other.parts.length
        ? parts.length : other.parts.length;
    for (var i = 0; i < length; i++) {
      final a = i < parts.length ? parts[i] : 0;
      final b = i < other.parts.length ? other.parts[i] : 0;
      if (a != b) return a.compareTo(b);
    }
    // Same version name: only a known, higher build counts as newer.
    if (build != null && other.build != null) return build!.compareTo(other.build!);
    return 0;
  }

  bool isNewerThan(AppVersion other) => compareTo(other) > 0;

  @override
  String toString() => build == null ? label : '$label+$build';
}

/// One published GitHub release that contains an installable APK.
@immutable
class AppRelease {
  const AppRelease({required this.version, required this.title,
      required this.notes, required this.publishedAt,
      required this.apkUrl, required this.apkSize, required this.pageUrl});

  final AppVersion version;
  final String title;
  final String notes;
  final DateTime? publishedAt;
  final String apkUrl;
  final int apkSize;
  final String pageUrl;

  /// Reads one entry of the GitHub releases API. Drafts, pre-releases and
  /// releases without an `.apk` asset are ignored.
  static AppRelease? fromGitHub(Map<String, dynamic> json) {
    if (json['draft'] == true || json['prerelease'] == true) return null;
    final version = AppVersion.tryParse(json['tag_name'] as String?);
    if (version == null) return null;
    Map<String, dynamic>? apk;
    for (final asset in json['assets'] as List<dynamic>? ?? const []) {
      if (asset is! Map<String, dynamic>) continue;
      final name = (asset['name'] as String? ?? '').toLowerCase();
      if (!name.endsWith('.apk')) continue;
      // Prefer the 64-bit ARM build when several APKs are attached.
      if (apk == null || name.contains('arm64')) apk = asset;
    }
    final url = apk?['browser_download_url'];
    if (url is! String || !url.startsWith('https://')) return null;
    return AppRelease(
      version: version,
      title: (json['name'] as String?)?.trim().isNotEmpty == true
          ? (json['name'] as String).trim() : version.label,
      notes: (json['body'] as String? ?? '').trim(),
      publishedAt: DateTime.tryParse(json['published_at'] as String? ?? ''),
      apkUrl: url,
      apkSize: (apk!['size'] as num?)?.toInt() ?? 0,
      pageUrl: json['html_url'] as String? ?? '',
    );
  }
}

/// Result of an update check.
@immutable
class UpdateCheck {
  const UpdateCheck({required this.installed, required this.releases});

  final AppVersion installed;

  /// Published releases, newest first.
  final List<AppRelease> releases;

  AppRelease? get latest => releases.isEmpty ? null : releases.first;

  bool get updateAvailable =>
      latest != null && latest!.version.isNewerThan(installed);

  /// Releases newer than the installed version, newest first.
  List<AppRelease> get missed => [
    for (final release in releases)
      if (release.version.isNewerThan(installed)) release,
  ];
}

class UpdateException implements Exception {
  const UpdateException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Checks GitHub Releases for a newer DocScanner APK, downloads it and
/// hands it to Android's installer. Nothing is installed without the
/// user's confirmation in the system installer.
class AppUpdateService {
  AppUpdateService({HttpClient Function()? httpClient,
      Future<Map<String, String>?> Function()? installedVersion})
      : _httpClient = httpClient ?? HttpClient.new,
        _installedVersion = installedVersion;

  static const repository = 'faria2177/DS-Fult';
  static const _channel = MethodChannel('doclens/methods');
  static const _autoCheckKey = 'update_auto_check';
  static const _promptedKey = 'update_prompted';

  /// Do not ask again about the same version within this period after
  /// "Later".
  static const promptPause = Duration(hours: 20);

  final HttpClient Function() _httpClient;
  final Future<Map<String, String>?> Function()? _installedVersion;

  static Future<bool> autoCheckEnabled() async =>
      (await SharedPreferences.getInstance()).getBool(_autoCheckKey) ?? true;

  static Future<void> setAutoCheck(bool enabled) async =>
      (await SharedPreferences.getInstance()).setBool(_autoCheckKey, enabled);

  /// Whether the launch dialog should be shown for [version] now.
  static Future<bool> shouldPrompt(AppVersion version, {DateTime? now}) async {
    final stored = (await SharedPreferences.getInstance())
        .getString(_promptedKey);
    if (stored == null) return true;
    final parts = stored.split('|');
    if (parts.length != 2 || parts[0] != version.toString()) return true;
    final at = DateTime.tryParse(parts[1]);
    return at == null ||
        (now ?? DateTime.now()).difference(at) >= promptPause;
  }

  static Future<void> rememberPrompt(AppVersion version) async =>
      (await SharedPreferences.getInstance()).setString(
          _promptedKey, '$version|${DateTime.now().toIso8601String()}');

  Future<AppVersion> installedVersion() async {
    Map<String, String>? raw;
    try {
      final provider = _installedVersion;
      if (provider != null) {
        raw = await provider();
      } else {
        final map = await _channel.invokeMapMethod<String, Object?>(
            'appVersion');
        if (map != null) {
          raw = {for (final e in map.entries) e.key: '${e.value ?? ''}'};
        }
      }
    } catch (_) {
      raw = null;
    }
    final name = AppVersion.tryParse(raw?['versionName']);
    if (name == null) return const AppVersion([0], null);
    return AppVersion(name.parts, int.tryParse(raw?['buildNumber'] ?? ''));
  }

  Future<UpdateCheck> check() async {
    final installed = await installedVersion();
    final client = _httpClient()..connectionTimeout = const Duration(seconds: 15);
    try {
      final request = await client.getUrl(Uri.parse(
          'https://api.github.com/repos/$repository/releases?per_page=30'));
      request.headers
        ..set(HttpHeaders.acceptHeader, 'application/vnd.github+json')
        ..set(HttpHeaders.userAgentHeader, 'DocScanner-Updater');
      final response = await request.close()
          .timeout(const Duration(seconds: 20));
      final body = await response.transform(utf8.decoder).join();
      if (response.statusCode == 403 || response.statusCode == 429) {
        throw const UpdateException(
            'GitHub is busy right now. Please try again in a while.');
      }
      if (response.statusCode != 200) {
        throw UpdateException('Update server answered ${response.statusCode}.');
      }
      final data = jsonDecode(body);
      if (data is! List) throw const UpdateException('Unexpected update data.');
      final releases = [
        for (final entry in data)
          if (entry is Map<String, dynamic>) AppRelease.fromGitHub(entry),
      ].whereType<AppRelease>().toList()
        ..sort((a, b) => b.version.compareTo(a.version));
      return UpdateCheck(installed: installed, releases: releases);
    } on UpdateException {
      rethrow;
    } on SocketException {
      throw const UpdateException('No internet connection.');
    } on TimeoutException {
      throw const UpdateException('The update server did not respond.');
    } catch (error) {
      throw UpdateException('Could not check for updates: $error');
    } finally {
      client.close(force: true);
    }
  }

  /// Downloads [release] into the app's private update folder and returns
  /// the file path. [onProgress] receives 0..1.
  Future<String> download(AppRelease release,
      {void Function(double progress)? onProgress}) async {
    final folder = Directory(p.join((await getTemporaryDirectory()).path,
        'updates'));
    if (await folder.exists()) {
      // Only the newest download is kept.
      await for (final entry in folder.list()) {
        try {
          await entry.delete(recursive: true);
        } catch (_) {}
      }
    } else {
      await folder.create(recursive: true);
    }
    final target = File(p.join(folder.path,
        'DocScanner-${release.version.label}.apk'));
    final partial = File('${target.path}.part');
    final client = _httpClient()..connectionTimeout = const Duration(seconds: 20);
    IOSink? sink;
    try {
      final request = await client.getUrl(Uri.parse(release.apkUrl));
      request.headers.set(HttpHeaders.userAgentHeader, 'DocScanner-Updater');
      final response = await request.close();
      if (response.statusCode != 200) {
        throw UpdateException('Download failed (${response.statusCode}).');
      }
      final total = response.contentLength > 0
          ? response.contentLength : release.apkSize;
      sink = partial.openWrite();
      var received = 0;
      await for (final chunk in response.timeout(const Duration(seconds: 45))) {
        sink.add(chunk);
        received += chunk.length;
        if (total > 0) onProgress?.call((received / total).clamp(0.0, 1.0));
      }
      await sink.flush();
      await sink.close();
      sink = null;
      // A cut-off download must never reach the installer.
      if (release.apkSize > 0 && received != release.apkSize) {
        throw const UpdateException(
            'The download was incomplete. Please try again.');
      }
      await partial.rename(target.path);
      onProgress?.call(1);
      return target.path;
    } on UpdateException {
      rethrow;
    } on SocketException {
      throw const UpdateException('Connection lost during download.');
    } on TimeoutException {
      throw const UpdateException('The download stopped responding.');
    } catch (error) {
      throw UpdateException('Download failed: $error');
    } finally {
      await sink?.close();
      client.close(force: true);
      if (await partial.exists()) {
        try {
          await partial.delete();
        } catch (_) {}
      }
    }
  }

  /// Opens Android's installer. Returns false when the app first needs the
  /// "Install unknown apps" permission (the settings page is then opened).
  Future<bool> install(String apkPath) async {
    final allowed = await _channel.invokeMethod<bool>('canInstallUpdates');
    if (allowed == false) {
      await _channel.invokeMethod<bool>('openInstallPermission');
      return false;
    }
    final started = await _channel.invokeMethod<bool>(
        'installUpdate', {'path': apkPath});
    if (started != true) {
      throw const UpdateException('The installer could not be opened.');
    }
    return true;
  }
}
