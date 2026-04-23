import 'package:flutter/material.dart';
import 'screens/home_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const SudaPassDemoApp());
}

class SudaPassDemoApp extends StatelessWidget {
  const SudaPassDemoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SudaPass SP Demo',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        primaryColor: const Color(0xFF1A6B4A),
        scaffoldBackgroundColor: const Color(0xFF0A0E1A),
      ),
      home: const HomeScreen(),
    );
  }
}
