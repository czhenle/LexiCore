import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'screens/initialization/splash_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: 'https://cldngeqtuyxwuvtsaocm.supabase.co',
    publishableKey: 'sb_publishable_NJvrBZXKXKoeGp4e-GzI3A_yIkohgjh',
  );

  final prefs = await SharedPreferences.getInstance();
  gFontScale.value = prefs.getDouble('font_scale') ?? 1.0;

  runApp(const LexiCoreApp());
}

final supabase = Supabase.instance.client;

/// App-wide text scale (accessibility). Set from the Profile screen.
final gFontScale = ValueNotifier<double>(1.0);

class LexiCoreApp extends StatelessWidget {
  const LexiCoreApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<double>(
      valueListenable: gFontScale,
      builder: (context, scale, _) => MaterialApp(
      title: 'LexiCore',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primaryColor: const Color(0xFF1E88E5),
        scaffoldBackgroundColor: const Color(0xFFDFF1FF),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1E88E5),
        ),
      ),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: const SplashScreen(),
      ),
    );
  }
}