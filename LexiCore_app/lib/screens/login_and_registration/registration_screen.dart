import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../services/supabase_service.dart';
import '../user_profiling/onboarding_profile_screen.dart';

class RegistrationScreen extends StatefulWidget {
  const RegistrationScreen({super.key});

  @override
  State<RegistrationScreen> createState() => _RegistrationScreenState();
}

class _RegistrationScreenState extends State<RegistrationScreen>
    with SingleTickerProviderStateMixin {

  // ✨ Sky Blue Theme
  static const Color _skyBlueLight = Color(0xFFDFF1FF);
  static const Color _skyBlueDark  = Color(0xFF7AC9FA);
  static const Color _navyText     = Color(0xFF003C8F);
  static const Color _starYellow   = Color(0xFFFFD54F);
  static const Color _buttonBlue   = Color(0xFF1E88E5);
  static const Color _divider      = Color(0xFFE5E7EB);
  static const Color _errorRed     = Color(0xFFEF4444);

  final _formKey             = GlobalKey<FormState>();
  final _usernameCtrl        = TextEditingController();
  final _emailCtrl           = TextEditingController();
  final _passwordCtrl        = TextEditingController();
  final _confirmPasswordCtrl = TextEditingController();
  final _supabaseService     = SupabaseService();

  bool _obscurePassword = true;
  bool _obscureConfirm  = true;
  bool _isLoading       = false;
  String? _errorMessage;

  late final AnimationController _animCtrl;
  late final Animation<double>   _fadeAnim;
  late final Animation<Offset>   _slideAnim;

  @override
  void initState() {
    super.initState();
    _passwordCtrl.addListener(() => setState(() {}));
    _animCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 800));
    _fadeAnim  = CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut);
    _slideAnim = Tween<Offset>(
            begin: const Offset(0, 0.07), end: Offset.zero)
        .animate(CurvedAnimation(
            parent: _animCtrl, curve: Curves.easeOutCubic));
    _animCtrl.forward();
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    _usernameCtrl.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmPasswordCtrl.dispose();
    super.dispose();
  }

  Future<void> _register() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() { _isLoading = true; _errorMessage = null; });

    try {
      final response = await _supabaseService.signUp(
        _emailCtrl.text.trim(),
        _passwordCtrl.text,
      );

      if (response.user != null && mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => OnboardingProfileScreen(
              username: _usernameCtrl.text.trim(),
            ),
          ),
        );
      }
    } on AuthException catch (e) {
      setState(() => _errorMessage = e.statusCode == '400'
          ? 'This email is already registered. Try signing in instead.'
          : e.message);
    } catch (e) {
      setState(() => _errorMessage = 'Unexpected error. Please try again.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  int get _pwdScore {
    final p = _passwordCtrl.text;
    int s = 0;
    if (p.length >= 8) s++;
    if (RegExp(r'[A-Z]').hasMatch(p)) s++;
    if (RegExp(r'[0-9]').hasMatch(p)) s++;
    if (RegExp(r'[!@#\$%^&*]').hasMatch(p)) s++;
    return s;
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
            // Sky decorations
            const Positioned(top: 60, right: 30, child: Icon(Icons.star_rounded, color: _starYellow, size: 30)),
            const Positioned(top: 140, left: 20, child: Icon(Icons.cloud_rounded, color: Colors.white, size: 60)),

            SafeArea(
              child: FadeTransition(
                opacity: _fadeAnim,
                child: SlideTransition(
                  position: _slideAnim,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch, // Aligns content to the left
                      children: [
                        const SizedBox(height: 20),
                        _buildTopBar(),
                        const SizedBox(height: 24),
                        _buildWelcomeText(),
                        const SizedBox(height: 24),
                        _buildCard(),
                        const SizedBox(height: 20),
                        _buildSignInRow(),
                        const SizedBox(height: 28),
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

  // Adjusted to drop the "Step 1 of 6" slightly lower than the back button
  Widget _buildTopBar() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.start,
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
        
        // ✨ Step 1 of 6 Indicator (pushed down slightly)
        Padding(
          padding: const EdgeInsets.only(top: 8.0),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(color: _navyText, borderRadius: BorderRadius.circular(20)),
            child: const Text('Step 1 of 6',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
          ),
        ),
      ],
    );
  }

  // The new welcoming headers
  Widget _buildWelcomeText() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Welcome to LexiCore! 👋',
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: _navyText, letterSpacing: -0.5)),
        const SizedBox(height: 8),
        Text('Before we start, let\'s set up your account.',
            style: TextStyle(fontSize: 16, color: _navyText.withValues(alpha: 0.8), fontWeight: FontWeight.w600, height: 1.4)),
      ],
    );
  }

  Widget _buildCard() {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 26, 24, 26),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(30), // Bubbly corners for kids
        boxShadow: [
          BoxShadow(color: _navyText.withValues(alpha: 0.1), blurRadius: 30, offset: const Offset(0, 10)),
        ],
      ),
      child: Form(
        key: _formKey,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Your details', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: _navyText)),
          const SizedBox(height: 18),

          _label('Username'),
          const SizedBox(height: 6),
          _field(controller: _usernameCtrl, hint: 'e.g. HeroAhmad', icon: Icons.face_rounded,
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Username is required' : null),
          const SizedBox(height: 16),

          _label('Email address'),
          const SizedBox(height: 6),
          _field(
            controller: _emailCtrl, hint: 'you@example.com', icon: Icons.mail_rounded,
            keyboardType: TextInputType.emailAddress,
            validator: (v) {
              if (v == null || v.isEmpty) return 'Email is required';
              if (!RegExp(r'^[\w\.-]+@[\w\.-]+\.\w{2,}$').hasMatch(v)) return 'Enter a valid email';
              return null;
            },
          ),
          const SizedBox(height: 16),

          _label('Password'),
          const SizedBox(height: 6),
          _field(
            controller: _passwordCtrl, hint: '••••••••', icon: Icons.lock_rounded, obscure: _obscurePassword,
            validator: (v) {
              if (v == null || v.isEmpty) return 'Password is required';
              if (v.length < 8) return 'Minimum 8 characters';
              return null;
            },
            suffixIcon: IconButton(
              icon: Icon(_obscurePassword ? Icons.visibility_off_rounded : Icons.visibility_rounded, color: _buttonBlue, size: 20),
              onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
            ),
          ),
          const SizedBox(height: 6),
          _passwordStrengthBar(),
          const SizedBox(height: 16),

          _label('Confirm password'),
          const SizedBox(height: 6),
          _field(
            controller: _confirmPasswordCtrl, hint: '••••••••', icon: Icons.lock_rounded, obscure: _obscureConfirm,
            validator: (v) {
              if (v == null || v.isEmpty) return 'Please confirm your password';
              if (v != _passwordCtrl.text) return 'Passwords do not match';
              return null;
            },
            suffixIcon: IconButton(
              icon: Icon(_obscureConfirm ? Icons.visibility_off_rounded : Icons.visibility_rounded, color: _buttonBlue, size: 20),
              onPressed: () => setState(() => _obscureConfirm = !_obscureConfirm),
            ),
          ),

          if (_errorMessage != null) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(color: _errorRed.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(10)),
              child: Row(children: [
                const Icon(Icons.error_outline, color: _errorRed, size: 16),
                const SizedBox(width: 8),
                Expanded(child: Text(_errorMessage!, style: const TextStyle(color: _errorRed, fontSize: 12))),
              ]),
            ),
          ],
          const SizedBox(height: 24),

          // Submit button
          SizedBox(
            width: double.infinity, height: 56,
            child: ElevatedButton(
              onPressed: _isLoading ? null : _register,
              style: ElevatedButton.styleFrom(
                backgroundColor: _buttonBlue,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              ),
              child: _isLoading
                  ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3))
                  : const Text('Create Account', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, letterSpacing: 0.5)),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _passwordStrengthBar() {
    final score = _pwdScore;
    final colors = [Colors.transparent, _errorRed, _starYellow, _buttonBlue, Colors.green];
    final labels = ['', 'Weak', 'Fair', 'Good', 'Super Strong!'];

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: List.generate(4, (i) => Expanded(
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          margin: EdgeInsets.only(right: i < 3 ? 4 : 0),
          height: 6,
          decoration: BoxDecoration(
            color: i < score ? colors[score] : _divider,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
      ))),
      if (_passwordCtrl.text.isNotEmpty) ...[
        const SizedBox(height: 6),
        Text(score > 0 ? labels[score] : '', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: colors[score])),
      ],
    ]);
  }

  Widget _buildSignInRow() {
    return Row(mainAxisAlignment: MainAxisAlignment.center, children: [
      Text('Already have an account? ', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: _navyText.withValues(alpha: 0.7))),
      GestureDetector(
        onTap: () => Navigator.pop(context),
        child: const Text('Sign In', style: TextStyle(fontSize: 14, color: _buttonBlue, fontWeight: FontWeight.w900, decoration: TextDecoration.underline)),
      ),
    ]);
  }

  Widget _label(String text) => Text(text, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: _navyText));

  Widget _field({
    required TextEditingController controller, required String hint, required IconData icon,
    TextInputType keyboardType = TextInputType.text, bool obscure = false, String? Function(String?)? validator, Widget? suffixIcon,
  }) {
    return TextFormField(
      controller: controller, keyboardType: keyboardType, obscureText: obscure, validator: validator,
      style: const TextStyle(fontSize: 15, color: _navyText, fontWeight: FontWeight.w600),
      decoration: InputDecoration(
        hintText: hint, hintStyle: TextStyle(color: _navyText.withValues(alpha: 0.4), fontSize: 14, fontWeight: FontWeight.normal),
        prefixIcon: Icon(icon, color: _buttonBlue, size: 22),
        suffixIcon: suffixIcon,
        filled: true, fillColor: _skyBlueLight.withValues(alpha: 0.3),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: _buttonBlue, width: 2)),
        errorStyle: const TextStyle(fontSize: 12, color: _errorRed, fontWeight: FontWeight.w600),
      ),
    );
  }
}