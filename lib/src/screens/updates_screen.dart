import 'dart:io';

import 'package:flutter/material.dart';

import '../services/app_update_service.dart';

/// Checks for an update on app launch (when Auto Check is on) and shows the
/// "Update Available" dialog at most once per version every
/// [AppUpdateService.promptPause].
Future<void> checkForUpdateOnLaunch(BuildContext context,
    {AppUpdateService? service}) async {
  // Widget tests have no network; never start a background check there.
  if (service == null && Platform.environment.containsKey('FLUTTER_TEST')) {
    return;
  }
  final updates = service ?? AppUpdateService();
  try {
    if (!await AppUpdateService.autoCheckEnabled()) return;
    final result = await updates.check();
    final latest = result.latest;
    if (!result.updateAvailable || latest == null) return;
    if (!await AppUpdateService.shouldPrompt(latest.version)) return;
    // Never pop up over the camera or an open document; try next launch.
    if (!context.mounted || ModalRoute.of(context)?.isCurrent == false) return;
    await AppUpdateService.rememberPrompt(latest.version);
    if (!context.mounted) return;
    final view = await showDialog<bool>(
      context: context,
      builder: (_) => UpdateAvailableDialog(
          installed: result.installed, latest: latest.version),
    );
    if (view == true && context.mounted) {
      await Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => UpdatesScreen(service: updates, initial: result)));
    }
  } catch (error) {
    // A failed background check must never disturb the user.
    debugPrint('Launch update check skipped: $error');
  }
}

/// Launch pop-up: Installed vX → Latest vY, "View Update", "Later".
class UpdateAvailableDialog extends StatelessWidget {
  const UpdateAvailableDialog(
      {super.key, required this.installed, required this.latest});

  final AppVersion installed;
  final AppVersion latest;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(32)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 12),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 84, height: 84,
            decoration: BoxDecoration(color: scheme.primaryContainer,
                borderRadius: BorderRadius.circular(26)),
            child: Icon(Icons.auto_awesome, size: 40,
                color: scheme.onPrimaryContainer),
          ),
          const SizedBox(height: 20),
          Text('Update Available', textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineSmall
                  ?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text('A newer build of DocScanner is ready to download & explore.',
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.onSurfaceVariant)),
          const SizedBox(height: 20),
          Row(children: [
            Expanded(child: _VersionBox(label: 'Installed',
                version: installed.label, highlighted: false)),
            Padding(padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Icon(Icons.arrow_forward, color: scheme.primary)),
            Expanded(child: _VersionBox(label: 'Latest',
                version: latest.label, highlighted: true)),
          ]),
          const SizedBox(height: 20),
          SizedBox(width: double.infinity, child: FilledButton(
            key: const Key('update-view'),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(54),
              shape: const StadiumBorder()),
            onPressed: () => Navigator.pop(context, true),
            child: const Row(mainAxisSize: MainAxisSize.min, children: [
              Text('View Update', style: TextStyle(fontSize: 16,
                  fontWeight: FontWeight.w600)),
              SizedBox(width: 8),
              Icon(Icons.arrow_forward, size: 20),
            ]),
          )),
          const SizedBox(height: 4),
          TextButton(
            key: const Key('update-later'),
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Later', style: TextStyle(fontSize: 16))),
        ]),
      ),
    );
  }
}

class _VersionBox extends StatelessWidget {
  const _VersionBox({required this.label, required this.version,
      required this.highlighted});

  final String label;
  final String version;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
      decoration: BoxDecoration(
        color: highlighted ? scheme.primaryContainer
            : scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(18)),
      child: Column(children: [
        Text(label, style: TextStyle(fontSize: 13,
            color: highlighted ? scheme.onPrimaryContainer
                : scheme.onSurfaceVariant)),
        const SizedBox(height: 2),
        FittedBox(child: Text(version, style: TextStyle(fontSize: 20,
            fontWeight: FontWeight.bold,
            color: highlighted ? scheme.onPrimaryContainer
                : scheme.onSurface))),
      ]),
    );
  }
}

/// Me → Updates: status, What's New, Compare Release Notes, Auto Check.
class UpdatesScreen extends StatefulWidget {
  const UpdatesScreen({super.key, this.service, this.initial});

  final AppUpdateService? service;
  final UpdateCheck? initial;

  @override
  State<UpdatesScreen> createState() => _UpdatesScreenState();
}

class _UpdatesScreenState extends State<UpdatesScreen> {
  late final AppUpdateService _service = widget.service ?? AppUpdateService();
  UpdateCheck? _result;
  String? _error;
  bool _checking = false;
  bool _autoCheck = true;

  @override
  void initState() {
    super.initState();
    _result = widget.initial;
    AppUpdateService.autoCheckEnabled().then((value) {
      if (mounted) setState(() => _autoCheck = value);
    });
    if (_result == null) _check();
  }

  Future<void> _check() async {
    setState(() { _checking = true; _error = null; });
    try {
      final result = await _service.check();
      if (mounted) setState(() => _result = result);
    } on UpdateException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<void> _downloadAndInstall(AppRelease release) async {
    final installed = _result?.installed;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => _UpdateDialogShell(
        icon: Icons.download,
        title: 'Download Update?',
        body: 'DocScanner ${release.version.label} is available'
            '${installed == null ? '' : ' (you have ${installed.label})'}. '
            'The APK${release.apkSize > 0 ? ' (${_size(release.apkSize)})' : ''}'
            ' will be downloaded and Android will ask you to install it.',
        actions: [
          TextButton(key: const Key('update-not-now'),
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Not Now')),
          FilledButton(key: const Key('update-download'),
              style: FilledButton.styleFrom(shape: const StadiumBorder(),
                  minimumSize: const Size(130, 48)),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Download')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final progress = ValueNotifier<double>(0);
    final navigator = Navigator.of(context);
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => PopScope(canPop: false,
          child: _DownloadingDialog(version: release.version,
              progress: progress)),
    );
    String? message;
    try {
      final path = await _service.download(release,
          onProgress: (value) => progress.value = value);
      if (navigator.mounted) navigator.pop();
      final opened = await _service.install(path);
      if (!opened) {
        message = 'Allow "Install unknown apps" for DocScanner, then tap '
            'Download & Install again.';
      }
    } on UpdateException catch (error) {
      if (navigator.mounted) navigator.pop();
      message = error.message;
    } catch (error) {
      if (navigator.mounted) navigator.pop();
      message = 'Update failed: $error';
    } finally {
      progress.dispose();
    }
    if (message != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message)));
    }
  }

  static String _size(int bytes) =>
      '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';

  static String _date(DateTime? date) {
    if (date == null) return '';
    final local = date.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)}';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final result = _result;
    final latest = result?.latest;
    final available = result?.updateAvailable ?? false;
    return Scaffold(
      appBar: AppBar(title: const Text('Updates'), actions: [
        IconButton(
          key: const Key('update-refresh'),
          tooltip: 'Check again',
          onPressed: _checking ? null : _check,
          icon: const Icon(Icons.refresh)),
      ]),
      body: RefreshIndicator(
        onRefresh: _check,
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
            children: [
          _Section(children: [
            _StatusBanner(
              checking: _checking && result == null,
              error: result == null ? _error : null,
              available: available,
              latest: latest?.version,
            ),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: _InfoTile(icon: Icons.smartphone,
                  value: result?.installed.label ?? '—',
                  label: 'Installed', highlighted: false)),
              const SizedBox(width: 12),
              Expanded(child: _InfoTile(icon: Icons.cloud_download_outlined,
                  value: latest?.version.label ?? '—',
                  label: 'Latest Release', highlighted: available)),
            ]),
            if (available && latest != null) ...[
              const SizedBox(height: 12),
              FilledButton.icon(
                key: const Key('update-download-install'),
                style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(56),
                    shape: const StadiumBorder()),
                onPressed: () => _downloadAndInstall(latest),
                icon: const Icon(Icons.download),
                label: Text('Download & Install ${latest.version.label}',
                    style: const TextStyle(fontSize: 16,
                        fontWeight: FontWeight.w600)),
              ),
            ],
          ]),
          if (_error != null && result != null) Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(_error!, style: TextStyle(color: scheme.error))),
          if (latest != null) ...[
            _heading(context, "What's New"),
            _Section(children: [
              _ReleaseNotes(release: latest, date: _date(latest.publishedAt),
                  isNew: available),
            ]),
            const SizedBox(height: 14),
            _Section(children: [
              ListTile(
                key: const Key('update-compare'),
                contentPadding: EdgeInsets.zero,
                leading: const _IconBadge(icon: Icons.difference_outlined),
                title: const Text('Compare Release Notes',
                    style: TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text('Compare installed '
                    '${result!.installed.label} with the latest release',
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                trailing: const Icon(Icons.arrow_forward),
                onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(builder: (_) =>
                        _CompareNotesScreen(result: result))),
              ),
            ]),
          ],
          _heading(context, 'Options'),
          _Section(children: [
            SwitchListTile(
              key: const Key('update-auto-check'),
              contentPadding: EdgeInsets.zero,
              secondary: const _IconBadge(icon: Icons.sync),
              title: const Text('Auto Check For Updates',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              subtitle: const Text(
                  'Automatically check for new releases when app launches'),
              value: _autoCheck,
              onChanged: (value) {
                setState(() => _autoCheck = value);
                AppUpdateService.setAutoCheck(value);
              },
            ),
          ]),
        ]),
      ),
    );
  }

  Widget _heading(BuildContext context, String text) => Padding(
    padding: const EdgeInsets.fromLTRB(8, 22, 8, 10),
    child: Text(text, style: TextStyle(fontSize: 17,
        fontWeight: FontWeight.w600,
        color: Theme.of(context).colorScheme.primary)),
  );
}

class _Section extends StatelessWidget {
  const _Section({required this.children});
  final List<Widget> children;

  @override
  // A Material (not a coloured box) so list tiles inside keep their tap
  // ripple and background painting.
  Widget build(BuildContext context) => Material(
    color: Theme.of(context).colorScheme.surfaceContainerLow,
    borderRadius: BorderRadius.circular(28),
    clipBehavior: Clip.antiAlias,
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children),
    ),
  );
}

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({required this.checking, required this.error,
      required this.available, required this.latest});

  final bool checking;
  final String? error;
  final bool available;
  final AppVersion? latest;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final String title;
    final String subtitle;
    final IconData icon;
    if (checking) {
      title = 'Checking…';
      subtitle = 'Looking for the latest release';
      icon = Icons.sync;
    } else if (error != null) {
      title = 'Could not check';
      subtitle = error!;
      icon = Icons.cloud_off;
    } else if (available && latest != null) {
      title = 'Update Available!';
      subtitle = 'Version ${latest!.label} is ready to download';
      icon = Icons.new_releases;
    } else if (latest == null) {
      title = 'No releases yet';
      subtitle = 'No installable release has been published';
      icon = Icons.info_outline;
    } else {
      title = "You're up to date";
      subtitle = 'DocScanner ${latest!.label} is the latest version';
      icon = Icons.verified_outlined;
    }
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 18),
      decoration: BoxDecoration(color: scheme.primaryContainer,
          borderRadius: BorderRadius.circular(24)),
      child: Row(children: [
        Column(children: [
          Container(
            width: 64, height: 64,
            decoration: BoxDecoration(
              color: scheme.onPrimaryContainer.withValues(alpha: .10),
              borderRadius: BorderRadius.circular(20)),
            child: checking
                ? Padding(padding: const EdgeInsets.all(18),
                    child: CircularProgressIndicator(strokeWidth: 3,
                        color: scheme.onPrimaryContainer))
                : Icon(icon, size: 32, color: scheme.onPrimaryContainer)),
          if (available && latest != null) Container(
            margin: const EdgeInsets.only(top: 8),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            decoration: BoxDecoration(color: scheme.primary,
                borderRadius: BorderRadius.circular(20)),
            child: Text('New ${latest!.label}', style: TextStyle(
                fontSize: 12, fontWeight: FontWeight.w600,
                color: scheme.onPrimary))),
        ]),
        const SizedBox(width: 16),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
            children: [
          Text('DOCSCANNER', style: TextStyle(letterSpacing: 1.4,
              fontSize: 12, fontWeight: FontWeight.w600,
              color: scheme.onPrimaryContainer.withValues(alpha: .75))),
          const SizedBox(height: 2),
          Text(title, style: TextStyle(fontSize: 22,
              fontWeight: FontWeight.bold, color: scheme.onPrimaryContainer)),
          const SizedBox(height: 2),
          Text(subtitle, style: TextStyle(
              color: scheme.onPrimaryContainer.withValues(alpha: .85))),
        ])),
      ]),
    );
  }
}

class _InfoTile extends StatelessWidget {
  const _InfoTile({required this.icon, required this.value,
      required this.label, required this.highlighted});

  final IconData icon;
  final String value;
  final String label;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final foreground = highlighted ? scheme.onPrimaryContainer
        : scheme.onSurface;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: highlighted ? scheme.primaryContainer
            : scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(22)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: foreground.withValues(alpha: .08),
            borderRadius: BorderRadius.circular(12)),
          child: Icon(icon, color: foreground)),
        const SizedBox(height: 12),
        FittedBox(child: Text(value, style: TextStyle(fontSize: 19,
            fontWeight: FontWeight.bold, color: foreground))),
        Text(label, style: TextStyle(fontSize: 13,
            color: foreground.withValues(alpha: .75))),
      ]),
    );
  }
}

class _IconBadge extends StatelessWidget {
  const _IconBadge({required this.icon});
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: 48, height: 48,
      decoration: BoxDecoration(color: scheme.secondaryContainer,
          borderRadius: BorderRadius.circular(16)),
      child: Icon(icon, color: scheme.onSecondaryContainer));
  }
}

class _ReleaseNotes extends StatelessWidget {
  const _ReleaseNotes({required this.release, required this.date,
      required this.isNew});

  final AppRelease release;
  final String date;
  final bool isNew;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        const _IconBadge(icon: Icons.auto_awesome),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
            children: [
          Text(release.version.label, style: const TextStyle(fontSize: 18,
              fontWeight: FontWeight.bold)),
          Text(isNew ? 'New Release' : 'Latest Release',
              style: TextStyle(color: scheme.primary)),
        ])),
        if (date.isNotEmpty) Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(color: scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(20)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.calendar_today_outlined, size: 14,
                color: scheme.onSurfaceVariant),
            const SizedBox(width: 5),
            Text(date, style: TextStyle(fontSize: 13,
                color: scheme.onSurfaceVariant)),
          ])),
      ]),
      const Divider(height: 26),
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: scheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(20)),
        child: ReleaseNotesText(title: release.title, notes: release.notes)),
    ]);
  }
}

/// Renders GitHub release notes: `#` headings, `-`/`*`/`•` bullets, text.
class ReleaseNotesText extends StatelessWidget {
  const ReleaseNotesText({super.key, required this.title,
      required this.notes});

  final String title;
  final String notes;

  static String _clean(String text) => text
      .replaceAll(RegExp(r'\*\*|__|`'), '')
      .replaceAllMapped(RegExp(r'\[([^\]]+)\]\([^)]+\)'), (m) => m.group(1)!)
      .trim();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final lines = notes.split(RegExp(r'\r?\n'));
    final children = <Widget>[
      Text('📢 $title', style: const TextStyle(fontSize: 17,
          fontWeight: FontWeight.bold)),
      const Divider(height: 22),
    ];
    if (notes.trim().isEmpty) {
      children.add(Text('No release notes were provided.',
          style: TextStyle(color: scheme.onSurfaceVariant)));
    }
    for (final raw in lines) {
      final line = raw.trimRight();
      if (line.trim().isEmpty) continue;
      final heading = RegExp(r'^\s*#{1,6}\s+(.*)$').firstMatch(line);
      final bullet = RegExp(r'^\s*(?:[-*•]|\d+[.)])\s+(.*)$').firstMatch(line);
      if (heading != null) {
        children.add(Padding(
          padding: const EdgeInsets.only(top: 6, bottom: 4),
          child: Text(_clean(heading.group(1)!), style: const TextStyle(
              fontWeight: FontWeight.bold, fontSize: 15))));
      } else if (bullet != null) {
        children.add(Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('•  ', style: TextStyle(fontSize: 15)),
            Expanded(child: Text(_clean(bullet.group(1)!),
                style: const TextStyle(fontSize: 15, height: 1.35))),
          ])));
      } else {
        children.add(Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Text(_clean(line), style: const TextStyle(fontSize: 15,
              height: 1.35))));
      }
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children);
  }
}

/// Every release newer than the installed one (or the latest if none).
class _CompareNotesScreen extends StatelessWidget {
  const _CompareNotesScreen({required this.result});
  final UpdateCheck result;

  @override
  Widget build(BuildContext context) {
    final missed = result.missed;
    final shown = missed.isEmpty
        ? [if (result.latest != null) result.latest!] : missed;
    final latest = result.latest?.version.label ?? '';
    return Scaffold(
      appBar: AppBar(title: Text(
          '${result.installed.label} → $latest')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Text(missed.isEmpty
            ? 'You already have the latest release.'
            : '${missed.length} release(s) since your installed version:',
            style: TextStyle(color:
                Theme.of(context).colorScheme.onSurfaceVariant)),
        const SizedBox(height: 12),
        for (final release in shown) Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: _Section(children: [
            _ReleaseNotes(release: release,
                date: _UpdatesScreenState._date(release.publishedAt),
                isNew: release.version.isNewerThan(result.installed)),
          ]),
        ),
      ]),
    );
  }
}

class _UpdateDialogShell extends StatelessWidget {
  const _UpdateDialogShell({required this.icon, required this.title,
      required this.body, required this.actions});

  final IconData icon;
  final String title;
  final String body;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(32)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 26, 24, 20),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 64, height: 64,
            decoration: BoxDecoration(color: scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(20)),
            child: Icon(icon, size: 32, color: scheme.onSurface)),
          const SizedBox(height: 18),
          Text(title, textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineSmall
                  ?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 14),
          Text(body, style: const TextStyle(fontSize: 15, height: 1.4)),
          const SizedBox(height: 20),
          Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            for (final action in actions) Padding(
                padding: const EdgeInsets.only(left: 8), child: action),
          ]),
        ]),
      ),
    );
  }
}

class _DownloadingDialog extends StatelessWidget {
  const _DownloadingDialog({required this.version, required this.progress});

  final AppVersion version;
  final ValueNotifier<double> progress;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(32)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 26, 24, 30),
        child: ValueListenableBuilder<double>(
          valueListenable: progress,
          builder: (context, value, _) => Column(
              mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 64, height: 64,
              decoration: BoxDecoration(color: scheme.primaryContainer,
                  borderRadius: BorderRadius.circular(20)),
              child: Icon(Icons.downloading, size: 32,
                  color: scheme.onPrimaryContainer)),
            const SizedBox(height: 18),
            Text('Downloading ${version.label}', textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 20),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                key: const Key('update-progress'),
                value: value <= 0 ? null : value, minHeight: 8)),
            const SizedBox(height: 10),
            Row(children: [
              Text('${(value * 100).round()}%',
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              const Spacer(),
              Text('Installing when ready…',
                  style: TextStyle(color: scheme.onSurfaceVariant)),
            ]),
          ]),
        ),
      ),
    );
  }
}
