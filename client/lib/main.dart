import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/registry.dart';
import 'ui/home_page.dart';

/// App-wide theme mode; persisted by [StoryTimeApp] and changed from the
/// settings screen.
final ValueNotifier<ThemeMode> themeModeNotifier =
    ValueNotifier(ThemeMode.system);

const _themePrefKey = 'theme_mode';

ThemeMode _modeFromPref(String? v) => switch (v) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };

String _prefFromMode(ThemeMode m) => switch (m) {
      ThemeMode.light => 'light',
      ThemeMode.dark => 'dark',
      ThemeMode.system => 'system',
    };

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const StoryTimeApp());
}

class StoryTimeApp extends StatefulWidget {
  const StoryTimeApp({super.key});

  @override
  State<StoryTimeApp> createState() => _StoryTimeAppState();
}

class _StoryTimeAppState extends State<StoryTimeApp> {
  @override
  void initState() {
    super.initState();
    _loadTheme();
  }

  Future<void> _loadTheme() async {
    final prefs = await SharedPreferences.getInstance();
    themeModeNotifier.value =
        _modeFromPref(prefs.getString(_themePrefKey));
    themeModeNotifier.addListener(() async {
      await prefs.setString(
          _themePrefKey, _prefFromMode(themeModeNotifier.value));
    });
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeModeNotifier,
      builder: (context, mode, _) => MaterialApp(
        title: 'StoryTime',
        debugShowCheckedModeBanner: false,
        themeMode: mode,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
          useMaterial3: true,
        ),
        darkTheme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.deepPurple,
            brightness: Brightness.dark,
          ),
          useMaterial3: true,
        ),
        home: HomePage(registry: SourceRegistry()),
      ),
    );
  }
}
