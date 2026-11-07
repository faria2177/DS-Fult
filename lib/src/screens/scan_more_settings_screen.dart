import 'package:doclens/doclens.dart';
import 'package:flutter/material.dart';

import '../theme.dart';

class ScanMoreSettingsScreen extends StatelessWidget {
  const ScanMoreSettingsScreen({super.key, required this.settings});

  final ReferenceScanSettings settings;

  @override
  Widget build(BuildContext context) => Theme(
        data: ThemeData.dark(useMaterial3: true).copyWith(
          colorScheme: ColorScheme.fromSeed(
            seedColor: dsTeal,
            brightness: Brightness.dark,
          ),
        ),
        child: Scaffold(
          backgroundColor: const Color(0xFF1B1B1F),
          appBar: AppBar(
            title: const Text('Scan', style: TextStyle(fontSize: 18)),
            backgroundColor: const Color(0xFF2A2A2E),
            surfaceTintColor: Colors.transparent,
          ),
          body: AnimatedBuilder(
            animation: settings,
            builder: (context, _) => ListView(children: [
              _toggle(
                'Auto Adjust Borders',
                'Auto adjust borders when batch scanning',
                'autoAdjustBorders',
              ),
              _toggle(
                'Adjust After Each Scan',
                'Adjust borders when batch scanning',
                'adjustAfterEachScan',
              ),
              _toggle('Start with Camera', null, 'startWithCamera'),
              _toggle(
                'Use System Camera',
                'You can only use single mode scanning if it is turned on',
                'useSystemCamera',
              ),
              _toggle(
                'Import from Gallery',
                'The settings will be applied when you use single mode scanning.',
                'importFromGallery',
              ),
              _toggle(
                'Save Scans to Gallery After Scanning',
                null,
                'saveScansToGallery',
              ),
              _toggle(
                'Double-Focus',
                'Refocus the image before each capture. This may reduce capture speed.',
                'doubleFocus',
              ),
            ]),
          ),
        ),
      );

  Widget _toggle(String title, String? description, String key) => Material(
        color: const Color(0xFF2A2A2E),
        child: Column(children: [
          SwitchListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            title: Text(title, style: const TextStyle(fontSize: 15)),
            subtitle: description == null
                ? null
                : Text(description, style: const TextStyle(
                    color: Color(0xFF99999E), fontSize: 12)),
            value: settings.flag(key),
            onChanged: (value) => settings.setFlag(key, value),
          ),
          const Divider(color: Color(0xFF39393D), height: 1, indent: 20, endIndent: 20),
        ]),
      );
}
