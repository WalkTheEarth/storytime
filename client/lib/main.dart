import 'package:flutter/material.dart';

import 'core/registry.dart';
import 'ui/home_page.dart';

void main() {
  runApp(const StoryTimeApp());
}

class StoryTimeApp extends StatelessWidget {
  const StoryTimeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'StoryTime',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: HomePage(registry: SourceRegistry()),
    );
  }
}
