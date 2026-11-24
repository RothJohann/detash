import 'package:flutter/material.dart';

import 'screens/app_shell_screen.dart';

class GenappTemplateApp extends StatelessWidget {
  const GenappTemplateApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Detash',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF0F4C81)),
        useMaterial3: true,
      ),
      home: const AppShellScreen(),
    );
  }
}
