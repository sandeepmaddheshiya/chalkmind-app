import 'package:flutter/material.dart';
import '../features/home/home_screen.dart';
import 'theme/theme.dart';

class BoardFlowApp extends StatelessWidget {
  const BoardFlowApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BoardFlow Whiteboard',
      debugShowCheckedModeBanner: false,
      theme: BoardTheme.lightTheme(),
      darkTheme: BoardTheme.darkTheme(),
      themeMode: ThemeMode.system,
      home: const HomeScreen(),
    );
  }
}
