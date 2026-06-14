import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../services/supabase_service.dart';
import 'registration_screen.dart';
import '../home/home_screen.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen>
    with SingleTickerProviderStateMixin {

  // ✨ Sky Blue Theme
  static const Color _skyBlueLight = Color(0xFFDFF1FF);
  static const Color _skyBlueDark  = Color(0xFF7AC9FA);
  static const Color _navyText     = Color(0xFF003C8F);
  static const Color _starYellow   = Color(0xFFFFD54F);
  static const Color _buttonBlue   = Color(0xFF1E88E5);
  static const Color _errorRed     = Color(0xFFEF4444);

  final _emailCtrl    = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _formKey      = GlobalKey<FormState>();
  final _supabaseService = SupabaseService();

  bool    _obscure      = true;
  bool    _isLoading    = false;
  String? _errorMessage;

  late final AnimationController _animCtrl;
  late final Animation<double>   _fadeAnim;
  late final Animation<Offset>   _slideAnim;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 700));
    _fadeAnim  = CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut);
    _slideAnim = Tween<Offset>(
            begin: const Offset(0, 0.08), end: Offset.zero)
        .animate(CurvedAnimation(
            parent: _animCtrl, curve: Curves.easeOutCubic));
    _animCtrl.forward();
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() { _isLoading = true; _errorMessage = null; });

    try {
      await _supabaseService.signIn(
        _emailCtrl.text.trim(),
        _passwordCtrl.text,
      );
      if (mounted) {
        Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => const HomeScreen()));
      }
    } on AuthException catch (e) {
      setState(() => _errorMessage = e.message);
    } catch (_) {
      setState(() => _errorMessage = 'Unexpected error. Please try again.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
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
          fit: StackFit.expand,
          children: [
            // Sky decorations
            const Positioned(top: 80, right: 30, child: Icon(Icons.star_rounded, color: _starYellow, size: 30)),
            const Positioned(top: 150, left: -20, child: Icon(Icons.cloud_rounded, color: Colors.white, size: 80)),
            const Positioned(top: 350, right: -30, child: Icon(Icons.cloud_rounded, color: Colors.white, size: 100)),

            SafeArea(
              child: FadeTransition(
                opacity: _fadeAnim,
                child: SlideTransition(
                  position: _slideAnim,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const SizedBox(height: 20),
                        _buildTopBar(),
                        const SizedBox(height: 30),
                        _buildWelcomeText(),
                        const SizedBox(height: 30),
                        _buildCard(),
                        const SizedBox(height: 24),
                        _buildRegisterRow(),
                        const SizedBox(height: 24),
                      ]
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Row(
      children: [
        // Back Button
        GestureDetector(
          onTap: () => Navigator.pop(context),
          child: Container(
            width: 40, height: 40,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.3),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.arrow_back_ios_new_rounded, color: _navyText, size: 18),
          ),
        ),
      ],
    );
  }

  Widget _buildWelcomeText() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Center(
          child: Container(
            width: 80, height: 80,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(25),
              boxShadow: [BoxShadow(color: _navyText.withValues(alpha: 0.1), blurRadius: 20, offset: const Offset(0, 10))],
            ),
            child: const Icon(Icons.auto_awesome_rounded, size: 40, color: _buttonBlue),
          ),
        ),
        const SizedBox(height: 24),
        const Text('Welcome Back! 👋',
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: _navyText, letterSpacing: -0.5)),
        const SizedBox(height: 8),
        Text('Sign in to continue your learning adventure.',
            style: TextStyle(fontSize: 16, color: _navyText.withValues(alpha: 0.8), fontWeight: FontWeight.w600, height: 1.4)),
      ],
    );
  }

  Widget _buildCard() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(30), // Bubbly corners
        boxShadow: [
          BoxShadow(color: _navyText.withValues(alpha: 0.1), blurRadius: 30, offset: const Offset(0, 10)),
        ],
      ),
      child: Form(
        key: _formKey,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Sign in to your account',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: _navyText)),
          const SizedBox(height: 24),

          _label('Email address'),
          const SizedBox(height: 6),
          _field(
            controller: _emailCtrl,
            hint: 'you@example.com',
            icon: Icons.mail_rounded,
            keyboardType: TextInputType.emailAddress,
            validator: (v) {
              if (v == null || v.isEmpty) return 'Email is required';
              if (!RegExp(r'^[\w\.-]+@[\w\.-]+\.\w{2,}$').hasMatch(v)) {
                return 'Enter a valid email';
              }
              return null;
            },
          ),
          const SizedBox(height: 16),

          _label('Password'),
          const SizedBox(height: 6),
          _field(
            controller: _passwordCtrl,
            hint: '••••••••',
            icon: Icons.lock_rounded,
            obscure: _obscure,
            validator: (v) {
              if (v == null || v.isEmpty) return 'Password is required';
              if (v.length < 6) return 'At least 6 characters';
              return null;
            },
            suffix: IconButton(
              icon: Icon(
                _obscure ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                color: _buttonBlue, size: 20,
              ),
              onPressed: () => setState(() => _obscure = !_obscure),
            ),
          ),

          // Error banner
          if (_errorMessage != null) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: _errorRed.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(children: [
                const Icon(Icons.error_outline, color: _errorRed, size: 16),
                const SizedBox(width: 8),
                Expanded(child: Text(_errorMessage!,
                    style: const TextStyle(color: _errorRed, fontSize: 12))),
              ]),
            ),
          ],

          const SizedBox(height: 24),
          _signInButton(),
        ]),
      ),
    );
  }

  Widget _signInButton() {
    return SizedBox(
      width: double.infinity, height: 56,
      child: ElevatedButton(
        onPressed: _isLoading ? null : _signIn,
        style: ElevatedButton.styleFrom(
          backgroundColor: _buttonBlue,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        ),
        child: _isLoading
            ? const SizedBox(width: 24, height: 24,
                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3))
            : const Text('Log in',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, letterSpacing: 0.5)),
      ),
    );
  }

  Widget _buildRegisterRow() {
    return Row(mainAxisAlignment: MainAxisAlignment.center, children: [
      Text("New to LexiCore? ",
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: _navyText.withValues(alpha: 0.7))),
      GestureDetector(
        onTap: () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => const RegistrationScreen())),
        child: const Text('Sign up',
            style: TextStyle(fontSize: 14, color: _buttonBlue, fontWeight: FontWeight.w900, decoration: TextDecoration.underline)),
      ),
    ]);
  }

  Widget _label(String text) => Text(text,
      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: _navyText));

  Widget _field({
    required TextEditingController controller, required String hint, required IconData icon,
    TextInputType keyboardType = TextInputType.text, bool obscure = false, String? Function(String?)? validator, Widget? suffix,
  }) {
    return TextFormField(
      controller: controller, keyboardType: keyboardType, obscureText: obscure, validator: validator,
      style: const TextStyle(fontSize: 15, color: _navyText, fontWeight: FontWeight.w600),
      decoration: InputDecoration(
        hintText: hint, hintStyle: TextStyle(color: _navyText.withValues(alpha: 0.4), fontSize: 14, fontWeight: FontWeight.normal),
        prefixIcon: Icon(icon, color: _buttonBlue, size: 22),
        suffixIcon: suffix,
        filled: true, fillColor: _skyBlueLight.withValues(alpha: 0.3),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: _buttonBlue, width: 2)),
        errorStyle: const TextStyle(fontSize: 12, color: _errorRed, fontWeight: FontWeight.w600),
      ),
    );
  }
}