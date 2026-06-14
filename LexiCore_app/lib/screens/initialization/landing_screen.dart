import 'package:flutter/material.dart';
import '../login_and_registration/login_screen.dart';
import '../login_and_registration/registration_screen.dart';

class LandingScreen extends StatefulWidget {
  const LandingScreen({super.key});

  @override
  State<LandingScreen> createState() => _LandingScreenState();
}

class _LandingScreenState extends State<LandingScreen>
    with SingleTickerProviderStateMixin {
  // Theme Colors based on the Owl Icon
  static const Color _skyBlueLight = Color(0xFFDFF1FF);
  static const Color _skyBlueDark = Color(0xFF7AC9FA);
  static const Color _navyText = Color(0xFF003C8F);
  static const Color _starYellow = Color(0xFFFFD54F);
  static const Color _buttonBlue = Color(0xFF1E88E5);

  late final AnimationController _animCtrl;
  late final Animation<double> _fadeAnim;
  late final Animation<Offset> _slideAnim;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    _fadeAnim = CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut);
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.1),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _animCtrl, curve: Curves.easeOutCubic));
    _animCtrl.forward();
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        // Seamless, full-screen gradient background
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [_skyBlueDark, _skyBlueLight],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: Stack(
          children: [
            // --- Adjusted Scattered Sky Elements ---
            const Positioned(
              top: 90,
              right: 40,
              child: Icon(Icons.star_rounded, color: _starYellow, size: 32),
            ),
            const Positioned(
              top: 350,
              left: 20,
              child: Icon(Icons.star_rounded, color: Colors.white, size: 20),
            ),
            const Positioned(
              bottom: 180,
              right: -30,
              child: Icon(Icons.cloud_rounded, color: Colors.white, size: 120),
            ),

            SafeArea(
              child: FadeTransition(
                opacity: _fadeAnim,
                child: SlideTransition(
                  position: _slideAnim,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start, // Left-aligns the layout
                    children: [
                      // Pushes the hero section down nicely since the app bar is gone
                      const SizedBox(height: 60),

                      // --- HERO SECTION: Icon + Orbiting Attachments ---
                      Center(
                        child: SizedBox(
                          height: 280,
                          width: double.infinity,
                          child: Stack(
                            alignment: Alignment.center,
                            clipBehavior: Clip.none,
                            children: [
                              // 1. Center Owl Icon
                              Container(
                                width: 160,
                                height: 160,
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(45),
                                  boxShadow: [
                                    BoxShadow(
                                      color: _navyText.withValues(alpha: 0.15),
                                      blurRadius: 30,
                                      spreadRadius: 5,
                                      offset: const Offset(0, 15),
                                    ),
                                  ],
                                ),
                                clipBehavior: Clip.hardEdge,
                                // Todo: Uncomment when image is added to assets
                                // child: Image.asset('assets/icon_image.png', fit: BoxFit.cover),
                                child: const Icon(
                                  Icons.menu_book_rounded,
                                  size: 80,
                                  color: Color(0xFF003C8F),
                                ),
                              ),

                              // 2. Attachments
                              Positioned(
                                top: 20,
                                left: 10,
                                child: _floatingChip(
                                  Icons.auto_awesome_rounded,
                                  'AI-powered',
                                  _starYellow,
                                ),
                              ),
                              Positioned(
                                top: 70,
                                right: 0,
                                child: _floatingChip(
                                  Icons.tune_rounded, // Personalization icon
                                  'Personalization',
                                  _buttonBlue,
                                ),
                              ),
                              Positioned(
                                bottom: 15,
                                left: 30,
                                child: _floatingChip(
                                  Icons.school_rounded,
                                  'Primary School',
                                  _starYellow,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      
                      // Spacing between Hero and Typography
                      const SizedBox(height: 60),

                      // --- TYPOGRAPHY SECTION ---
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 28.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Slogan
                            const Text(
                              'From Practice\nTo Perfection.',
                              style: TextStyle(
                                fontSize: 44,
                                fontWeight: FontWeight.w900,
                                color: _navyText,
                                height: 1.1,
                                letterSpacing: -0.5,
                              ),
                            ),
                            const SizedBox(height: 16), // Adjusted gap
                            // Subtitle
                            Text(
                              'Personalized learning that adapts\nto your pace and goals.',
                              style: TextStyle(
                                fontSize: 16,
                                color: _navyText.withValues(alpha: 0.75),
                                fontWeight: FontWeight.w600,
                                height: 1.4,
                              ),
                            ),
                          ],
                        ),
                      ),

                      // Spacer pushes the button area nicely to the bottom
                      const Spacer(),

                      // --- ACTION AREA ---
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 28.0),
                        child: Column(
                          children: [
                            // Primary Log in Button
                            SizedBox(
                              width: double.infinity,
                              height: 60,
                              child: ElevatedButton(
                                onPressed: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => const AuthScreen(),
                                  ),
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: _buttonBlue,
                                  foregroundColor: Colors.white,
                                  elevation: 5,
                                  shadowColor: _buttonBlue.withValues(alpha: 0.4),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(30),
                                  ),
                                ),
                                child: const Text(
                                  'Log in',
                                  style: TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 24), // Adjusted gap

                            // Sign up text
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  'New to LexiCore? ',
                                  style: TextStyle(
                                    fontSize: 16,
                                    color: _navyText.withValues(alpha: 0.7),
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                GestureDetector(
                                  onTap: () => Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => const RegistrationScreen(),
                                    ),
                                  ),
                                  child: const Text(
                                    'Sign up',
                                    style: TextStyle(
                                      fontSize: 16,
                                      color: _buttonBlue,
                                      fontWeight: FontWeight.w900,
                                      decoration: TextDecoration.underline,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 50), // Comfortable bottom padding
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Floating Chip widget
  Widget _floatingChip(IconData icon, String label, Color iconColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: _navyText.withValues(alpha: 0.08),
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: iconColor),
          const SizedBox(width: 8),
          Text(
            label,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: _navyText,
            ),
          ),
        ],
      ),
    );
  }
}