import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'screens/initialization/splash_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: 'https://cldngeqtuyxwuvtsaocm.supabase.co',
    anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImNsZG5nZXF0dXl4d3V2dHNhb2NtIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzU1NDQzNTgsImV4cCI6MjA5MTEyMDM1OH0.vYL9Cn81OptK7UVyZzbjpLxS_uyzPOiSrLyqQX9X6Nk',
  );

  runApp(const LexiCoreApp());
}

final supabase = Supabase.instance.client;

class LexiCoreApp extends StatelessWidget {
  const LexiCoreApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'LexiCore',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primaryColor: const Color(0xFF1E88E5),
        scaffoldBackgroundColor: const Color(0xFFDFF1FF),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1E88E5),
        ),
      ),
      home: const SplashScreen(),
    );
  }
}