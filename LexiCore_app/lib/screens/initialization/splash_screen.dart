import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../services/notification_service.dart';
import '../../services/supabase_service.dart';
import '../login_and_registration/login_screen.dart';
import '../user_profiling/onboarding_profile_screen.dart';
import '../home/home_screen.dart';
import '../../theme/app_colors.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  static const Color _skyBlueLight = AppColors.skyLight;
  static const Color _skyBlueDark = AppColors.skyDark;
  static const Color _navyText = AppColors.navy;
  static const Color _starYellow = AppColors.starYellow;

  late final AnimationController _animCtrl;
  late final Animation<double> _fadeAnim;
  late final Animation<double> _scaleAnim;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    _fadeAnim = CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut);
    _scaleAnim = Tween<double>(
      begin: 0.7,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _animCtrl, curve: Curves.elasticOut));
    _animCtrl.forward();
    _navigate();
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    super.dispose();
  }

  Future<void> _navigate() async {
    await Future.delayed(const Duration(milliseconds: 1800)); // brand moment
    if (!mounted) return;

    await NotificationService().init();
    await _applyReminderPreference();

    final session = Supabase.instance.client.auth.currentSession;

    // Not logged in -> login screen.
    if (session == null) {
      _replace(const AuthScreen());
      return;
    }

    // Logged in but did NOT tick "Remember me" -> sign out, show login.
    final prefs = await SharedPreferences.getInstance();
    final remember = prefs.getBool('remember_me') ?? false;
    if (!remember) {
      await Supabase.instance.client.auth.signOut();
      if (!mounted) return;
      _replace(const AuthScreen());
      return;
    }

    // Remembered + valid session -> straight in (Home, or finish onboarding).
    final profile = await SupabaseService().getStudentProfile();
    if (!mounted) return;
    _replace(
      profile == null ? const OnboardingProfileScreen() : const HomeScreen(),
    );
  }

  void _replace(Widget page) => Navigator.of(
    context,
  ).pushReplacement(MaterialPageRoute(builder: (_) => page));

  // Applies the saved reminder preference on every cold start (defaults to
  // ON at 17:00 the first time, since the preference key is absent). The
  // profile screen's "Study Reminder" dialog re-applies immediately on
  // change, so this only matters for the boot-time re-schedule.
  Future<void> _applyReminderPreference() async {
    final prefs = await SharedPreferences.getInstance();
    final enabled = prefs.getBool('reminder_enabled') ?? true;
    if (!enabled) {
      await NotificationService().cancelDailyReminder();
      return;
    }
    final hour = prefs.getInt('reminder_hour') ?? 17;
    final minute = prefs.getInt('reminder_minute') ?? 0;
    await NotificationService().scheduleDailyReminder(
      hour: hour,
      minute: minute,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [_skyBlueDark, _skyBlueLight],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: Stack(
          children: [
            // --- Decorative Background Stars ---
            const Positioned(
              top: 80,
              left: 50,
              child: Icon(Icons.star_rounded, color: _starYellow, size: 30),
            ),
            const Positioned(
              top: 150,
              right: 60,
              child: Icon(Icons.star_rounded, color: _starYellow, size: 20),
            ),
            const Positioned(
              bottom: 200,
              left: 80,
              child: Icon(Icons.star_rounded, color: Colors.white, size: 25),
            ),
            const Positioned(
              bottom: 300,
              right: 40,
              child: Icon(Icons.star_rounded, color: _starYellow, size: 40),
            ),

            // --- Fluffy Cloud Accents (Bottom) ---
            Positioned(
              bottom: -50,
              left: -50,
              child: Container(
                width: 200,
                height: 200,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.6),
                ),
              ),
            ),
            Positioned(
              bottom: -80,
              right: -30,
              child: Container(
                width: 250,
                height: 250,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.8),
                ),
              ),
            ),

            // --- Centre Content ---
            Center(
              child: FadeTransition(
                opacity: _fadeAnim,
                child: ScaleTransition(
                  scale: _scaleAnim,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: Image.asset(
                          'assets/icon_image.png',
                          width: 140,
                          height: 140,
                          fit: BoxFit.cover,
                        ),
                      ),
                      const SizedBox(height: 24),

                      // App name
                      const Text(
                        'LexiCore',
                        style: TextStyle(
                          fontSize: 42,
                          fontWeight: FontWeight.w900,
                          color: _navyText,
                          letterSpacing: 1.0,
                        ),
                      ),
                      const SizedBox(height: 8),

                      // Subtitle
                      const Text(
                        'AI-Powered English Learning Assistant',
                        style: TextStyle(
                          fontSize: 16,
                          color: _navyText,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // --- Bottom Loader ---
            Positioned(
              bottom: 80,
              left: 0,
              right: 0,
              child: FadeTransition(
                opacity: _fadeAnim,
                child: Column(
                  children: [
                    const SizedBox(
                      width: 30,
                      height: 30,
                      child: CircularProgressIndicator(
                        color: _navyText,
                        strokeWidth: 3.0,
                        strokeCap: StrokeCap.round,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Preparing your lessons...',
                      style: TextStyle(
                        fontSize: 14,
                        color: _navyText.withValues(alpha: 0.7),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
