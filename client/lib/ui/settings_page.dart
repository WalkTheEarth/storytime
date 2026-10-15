import 'package:flutter/material.dart';

import '../main.dart';

/// Settings: theme (system/light/dark) + about.
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  static const _modes = [
    (ThemeMode.system, Icons.brightness_auto, 'System default',
        'Follow the device light/dark setting'),
    (ThemeMode.light, Icons.light_mode, 'Light', 'Always light'),
    (ThemeMode.dark, Icons.dark_mode, 'Dark', 'Always dark'),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text('Appearance',
                style: TextStyle(fontWeight: FontWeight.bold)),
          ),
          ValueListenableBuilder<ThemeMode>(
            valueListenable: themeModeNotifier,
            builder: (context, current, _) => RadioGroup<ThemeMode>(
              groupValue: current,
              onChanged: (v) {
                if (v != null) themeModeNotifier.value = v;
              },
              child: Column(
                children: [
                  for (final (mode, icon, title, subtitle) in _modes)
                    RadioListTile<ThemeMode>(
                      secondary: Icon(icon),
                      title: Text(title),
                      subtitle: Text(subtitle),
                      value: mode,
                    ),
                ],
              ),
            ),
          ),
          const Divider(),
          const ListTile(
            leading: Icon(Icons.info_outline),
            title: Text('StoryTime'),
            subtitle: Text(
              'Open-source multi-source novel reader.\n'
              'All book content belongs to its authors and platforms.',
            ),
          ),
        ],
      ),
    );
  }
}
