import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../services/supabase_service.dart';
import '../initialization/landing_screen.dart';

class UserProfile extends StatefulWidget {
  const UserProfile({super.key});

  @override
  State<UserProfile> createState() => _UserProfileState();
}

class _UserProfileState extends State<UserProfile> {
  // ✨ Candy & Sunshine Sky Blue Theme
  static const Color _bg           = Color(0xFFF0F8FF); 
  static const Color _navyText     = Color(0xFF003C8F);
  static const Color _buttonBlue   = Color(0xFF1E88E5);
  static const Color _skyLight     = Color(0xFFDFF1FF);
  static const Color _mintGreen    = Color(0xFF4DB6AC);
  static const Color _coralRed     = Color(0xFFFF5252);
  static const Color _vibrantPurple= Color(0xFFAB47BC);

  final _supabaseService = SupabaseService();
  final _picker          = ImagePicker();

  String  _username    = '';
  String  _email       = '';
  int     _standard    = 1;
  String  _studyTime   = '';
  int     _detectedLevel = 3; // Changed to non-nullable with a default
  String? _imagePath;
  bool    _isLoading   = true;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    try {
      final profile    = await _supabaseService.getStudentProfile();
      final assessment = await _supabaseService.getAssessmentResults();
      final user       = _supabaseService.currentUser;

      setState(() {
        _username      = (profile?['username']       as String?) ?? 'Student';
        _email         = user?.email                             ?? '';
        _standard      = (profile?['standard']       as int?)   ?? 1;
        _studyTime     = (profile?['study_time']     as String?) ?? '';
        _detectedLevel = (assessment?['detected_level'] as int?) ?? _standard;
        _isLoading     = false;
      });
    } catch (e) {
      debugPrint('Profile load error: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _pickImage() async {
    final XFile? image =
        await _picker.pickImage(source: ImageSource.gallery);
    if (image != null) {
      setState(() => _imagePath = image.path);
    }
  }

  // ── Change password dialog ───────────────────────────────────────────────
  void _showChangePasswordDialog() {
    final newPassCtrl     = TextEditingController();
    final confirmPassCtrl = TextEditingController();
    String? error;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setDialog) => AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(28)), // Bubbly dialog
          title: const Text('Change Password',
              style: TextStyle(
                  fontWeight: FontWeight.w900,
                  color: _navyText)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _dialogField(newPassCtrl,
                  'New password', Icons.lock_outline_rounded,
                  obscure: true),
              const SizedBox(height: 16),
              _dialogField(confirmPassCtrl,
                  'Confirm new password', Icons.lock_outline_rounded,
                  obscure: true),
              if (error != null) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: _coralRed.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(error!,
                      style: const TextStyle(
                          color: _coralRed, fontSize: 13, fontWeight: FontWeight.bold)),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('Cancel',
                  style: TextStyle(color: _navyText.withValues(alpha: 0.5), fontWeight: FontWeight.bold)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: _buttonBlue,
                elevation: 0,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20)),
              ),
              onPressed: () async {
                if (newPassCtrl.text.length < 8) {
                  setDialog(() => error =
                      'Password must be at least 8 characters');
                  return;
                }
                if (newPassCtrl.text != confirmPassCtrl.text) {
                  setDialog(
                      () => error = 'Passwords do not match');
                  return;
                }
                try {
                  await Supabase.instance.client.auth
                      .updateUser(UserAttributes(
                          password: newPassCtrl.text));
                  if (ctx.mounted) {
                    Navigator.pop(ctx);
                    _showSnack('Password updated successfully!',
                        success: true);
                  }
                } on AuthException catch (e) {
                  setDialog(() => error = e.message);
                }
              },
              child: const Text('Save',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w800)),
            ),
          ],
        ),
      ),
    );
  }

  // ── Edit profile dialog ──────────────────────────────────────────────────
  void _showEditProfileDialog() {
    final usernameCtrl =
        TextEditingController(text: _username);
    int selectedStandard    = _standard;
    String selectedStudyTime = _studyTime;

    final studyTimes = [
      '15 minutes', '30 minutes', '45 minutes', '1 hour'
    ];

    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setDialog) => AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(28)), // Bubbly dialog
          title: const Text('Edit Profile',
              style: TextStyle(
                  fontWeight: FontWeight.w900,
                  color: _navyText)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _dialogField(usernameCtrl,
                    'Username', Icons.face_rounded),
                const SizedBox(height: 24),
                Text('School standard',
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: _navyText.withValues(alpha: 0.7))),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: List.generate(6, (i) {
                    final std = i + 1;
                    final sel = std == selectedStandard;
                    return GestureDetector(
                      onTap: () => setDialog(
                          () => selectedStandard = std),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        width: 48, height: 48,
                        decoration: BoxDecoration(
                          color: sel ? _buttonBlue : _bg,
                          shape: BoxShape.circle,
                          border: Border.all(color: sel ? _buttonBlue : _skyLight, width: 2),
                        ),
                        child: Center(
                          child: Text('$std',
                              style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w900,
                                  color: sel ? Colors.white : _navyText)),
                        ),
                      ),
                    );
                  }),
                ),
                const SizedBox(height: 24),
                Text('Daily study time',
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: _navyText.withValues(alpha: 0.7))),
                const SizedBox(height: 12),
                ...studyTimes.map((t) {
                  final sel = t == selectedStudyTime;
                  return GestureDetector(
                    onTap: () =>
                        setDialog(() => selectedStudyTime = t),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 14),
                      decoration: BoxDecoration(
                        color: sel
                            ? _buttonBlue.withValues(alpha: 0.1)
                            : _bg,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: sel
                              ? _buttonBlue
                              : _skyLight,
                          width: 2,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.timer_rounded, color: sel ? _buttonBlue : _navyText.withValues(alpha: 0.4), size: 20),
                          const SizedBox(width: 12),
                          Text(t,
                              style: TextStyle(
                                  fontSize: 15,
                                  color: sel ? _buttonBlue : _navyText,
                                  fontWeight: sel
                                      ? FontWeight.w800
                                      : FontWeight.w600)),
                          const Spacer(),
                          if (sel) const Icon(Icons.check_circle_rounded, color: _buttonBlue, size: 20),
                        ],
                      ),
                    ),
                  );
                }),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('Cancel',
                  style: TextStyle(color: _navyText.withValues(alpha: 0.5), fontWeight: FontWeight.bold)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: _buttonBlue,
                elevation: 0,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20)),
              ),
              onPressed: () async {
                try {
                  await _supabaseService.saveStudentProfile(
                    username:  usernameCtrl.text.trim(),
                    age:       selectedStandard + 6,
                    standard:  selectedStandard,
                    studyTime: selectedStudyTime,
                  );
                  setState(() {
                    _username   = usernameCtrl.text.trim();
                    _standard   = selectedStandard;
                    _studyTime  = selectedStudyTime;
                  });
                  if (ctx.mounted) {
                    Navigator.pop(ctx);
                    _showSnack('Profile updated!', success: true);
                  }
                } catch (e) {
                  _showSnack('Failed to save. Try again.');
                }
              },
              child: const Text('Save',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w800)),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _logout() async {
    await _supabaseService.signOut();
    if (mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LandingScreen()),
        (_) => false,
      );
    }
  }

  void _showLogoutConfirm() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(28)),
        title: const Text('Log out?',
            style: TextStyle(fontWeight: FontWeight.w900, color: _navyText, fontSize: 22)),
        content: Text('You will need to sign in again next time to continue learning.', style: TextStyle(color: _navyText.withValues(alpha: 0.7), fontSize: 15, fontWeight: FontWeight.w500)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel',
                style: TextStyle(color: _navyText.withValues(alpha: 0.5), fontWeight: FontWeight.bold)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: _coralRed,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20)),
            ),
            onPressed: () {
              Navigator.pop(context);
              _logout();
            },
            child: const Text('Log out',
                style: TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16)),
          ),
        ],
      ),
    );
  }

  void _showSnack(String message, {bool success = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message, style: const TextStyle(fontWeight: FontWeight.bold)),
      backgroundColor: success
          ? _mintGreen
          : _coralRed,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16)),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        automaticallyImplyLeading: false,
        title: const Text('My Profile',
            style: TextStyle(
                fontWeight: FontWeight.w900,
                color: _navyText,
                fontSize: 24)),
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: _buttonBlue))
          : SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 100),
                child: Column(
                  children: [
                    const SizedBox(height: 20),
                    // ── Avatar ────────────────────────────────────────────
                    Center(
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Container(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: _buttonBlue.withValues(alpha: 0.25),
                                  blurRadius: 25,
                                  spreadRadius: 2,
                                  offset: const Offset(0, 10)
                                ),
                              ],
                            ),
                            child: CircleAvatar(
                              radius: 60,
                              backgroundColor: _skyLight,
                              backgroundImage: _imagePath != null
                                  ? FileImage(File(_imagePath!))
                                  : null,
                              child: _imagePath == null
                                  ? Text(
                                      _username.isNotEmpty
                                          ? _username[0].toUpperCase()
                                          : 'S',
                                      style: const TextStyle(
                                          fontSize: 48,
                                          fontWeight: FontWeight.w900,
                                          color: _buttonBlue))
                                  : null,
                            ),
                          ),
                          Positioned(
                            bottom: 0, right: 0,
                            child: GestureDetector(
                              onTap: _pickImage,
                              child: Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: _buttonBlue,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                      color: Colors.white,
                                      width: 3),
                                ),
                                child: const Icon(
                                    Icons.camera_alt_rounded,
                                    color: Colors.white,
                                    size: 18),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Name + email
                    Text(_username,
                        style: const TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w900,
                            color: _navyText)),
                    const SizedBox(height: 6),
                    Text(_email,
                        style: TextStyle(
                            fontSize: 14, color: _navyText.withValues(alpha: 0.6), fontWeight: FontWeight.bold)),
                    const SizedBox(height: 24),

                    // Badges row
                    Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 12, runSpacing: 12,
                      children: [
                        _badge('Standard $_standard',
                            Icons.school_rounded,
                            _mintGreen),
                        // ✨ Restored the detected level badge
                        _badge('Level $_detectedLevel',
                            Icons.trending_up_rounded,
                            _buttonBlue),
                        if (_studyTime.isNotEmpty)
                          _badge(_studyTime,
                              Icons.timer_rounded,
                              _vibrantPurple),
                      ],
                    ),
                    const SizedBox(height: 40),

                    // ── Menu items ────────────────────────────────────────
                    _menuCard(
                      icon:      Icons.edit_rounded,
                      title:     'Edit Profile',
                      subtitle:  'Update username, standard, study time',
                      iconColor: _buttonBlue,
                      onTap:     _showEditProfileDialog,
                    ),
                    const SizedBox(height: 16),
                    _menuCard(
                      icon:      Icons.lock_rounded,
                      title:     'Change Password',
                      subtitle:  'Keep your account safe',
                      iconColor: _mintGreen,
                      onTap:     _showChangePasswordDialog,
                    ),
                    const SizedBox(height: 16),
                    _menuCard(
                      icon:      Icons.logout_rounded,
                      title:     'Log Out',
                      subtitle:  'See you next time!',
                      iconColor: _coralRed,
                      onTap:     _showLogoutConfirm,
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _badge(String label, IconData icon, Color color) {
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.3), width: 2),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Text(label,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: color)),
        ],
      ),
    );
  }

  Widget _menuCard({
    required IconData icon,
    required String   title,
    required String   subtitle,
    required Color    iconColor,
    required VoidCallback onTap,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24), // Bubbly menu cards
        boxShadow: [
          BoxShadow(
              color: _navyText.withValues(alpha: 0.05),
              blurRadius: 15,
              offset: const Offset(0, 5)),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(24),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: 20, vertical: 16),
            child: Row(children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.15), // Vibrant background
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(icon, color: iconColor, size: 24),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 16,
                            color: _navyText)),
                    const SizedBox(height: 4),
                    Text(subtitle,
                        style: TextStyle(
                            fontSize: 13, color: _navyText.withValues(alpha: 0.6), fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
              Icon(Icons.arrow_forward_ios_rounded,
                  size: 16, color: _navyText.withValues(alpha: 0.3)),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _dialogField(
    TextEditingController ctrl,
    String hint,
    IconData icon, {
    bool obscure = false,
  }) {
    return TextField(
      controller: ctrl,
      obscureText: obscure,
      style: const TextStyle(fontSize: 15, color: _navyText, fontWeight: FontWeight.w600),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(
            color: _navyText.withValues(alpha: 0.4), fontSize: 14),
        prefixIcon: Icon(icon, color: _buttonBlue, size: 20),
        filled: true,
        fillColor: _bg, // Use sky blue inside the white dialog
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: const BorderSide(color: _buttonBlue, width: 2)),
      ),
    );
  }
}