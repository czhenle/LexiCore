import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'landing_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {

  static const Color _skyBlueLight = Color(0xFFDFF1FF);
  static const Color _skyBlueDark  = Color(0xFF7AC9FA);
  static const Color _navyText     = Color(0xFF003C8F);
  static const Color _starYellow   = Color(0xFFFFD54F);

  late final AnimationController _animCtrl;
  late final Animation<double>   _fadeAnim;
  late final Animation<double>   _scaleAnim;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1000));
    _fadeAnim  = CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut);
    _scaleAnim = Tween<double>(begin: 0.7, end: 1.0).animate(
        CurvedAnimation(parent: _animCtrl, curve: Curves.elasticOut));
    _animCtrl.forward();
    _navigate();
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    super.dispose();
  }

  Future<void> _navigate() async {
    await Future.delayed(const Duration(milliseconds: 2800));
    await Supabase.instance.client.auth.signOut();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const LandingScreen()),
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
            const Positioned(top: 80, left: 50, child: Icon(Icons.star_rounded, color: _starYellow, size: 30)),
            const Positioned(top: 150, right: 60, child: Icon(Icons.star_rounded, color: _starYellow, size: 20)),
            const Positioned(bottom: 200, left: 80, child: Icon(Icons.star_rounded, color: Colors.white, size: 25)),
            const Positioned(bottom: 300, right: 40, child: Icon(Icons.star_rounded, color: _starYellow, size: 40)),

            // --- Fluffy Cloud Accents (Bottom) ---
            Positioned(
              bottom: -50, left: -50,
              child: Container(
                width: 200, height: 200,
                decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withValues(alpha: 0.6)),
              ),
            ),
            Positioned(
              bottom: -80, right: -30,
              child: Container(
                width: 250, height: 250,
                decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withValues(alpha: 0.8)),
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
                      // 💡 PRO TIP: Once you add your image to your assets folder, 
                      // replace this Container with: Image.asset('assets/your_icon.png', width: 140)
                      Container(
                        width: 140, height: 140,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white,
                          boxShadow: [
                            BoxShadow(color: _navyText.withValues(alpha: 0.15), blurRadius: 30, spreadRadius: 5),
                          ],
                        ),
                        child: const Icon(Icons.school_rounded, size: 70, color: _skyBlueDark),
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
                        'AI English Learning',
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
              bottom: 80, left: 0, right: 0,
              child: FadeTransition(
                opacity: _fadeAnim,
                child: Column(
                  children: [
                    const SizedBox(
                      width: 30, height: 30,
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