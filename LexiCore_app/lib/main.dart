import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'screens/initialization/splash_screen.dart';
import 'theme/app_colors.dart';

/// Must be a top-level (or static) function — FCM calls it in its own
/// isolate when a push arrives while the app is backgrounded/killed. There's
/// nothing to actually do here: FCM displays the notification itself in that
/// state. This only needs to exist and re-initialise Firebase for that
/// delivery path to work at all.
@pragma('vm:entry-point')
Future<void> _firebaseBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // On Android this reads android/app/google-services.json via the
  // com.google.gms.google-services Gradle plugin — no firebase_options.dart
  // needed for an Android-only setup.
  await Firebase.initializeApp();
  FirebaseMessaging.onBackgroundMessage(_firebaseBackgroundHandler);

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
        primaryColor: AppColors.blue,
        scaffoldBackgroundColor: AppColors.skyLight,
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppColors.blue,
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