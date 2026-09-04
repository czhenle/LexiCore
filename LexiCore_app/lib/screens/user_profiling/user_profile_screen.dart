import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../main.dart';
import '../../services/notification_service.dart';
import '../../services/supabase_service.dart';
import '../login_and_registration/login_screen.dart';
import '../../theme/app_colors.dart';

class UserProfile extends StatefulWidget {
  const UserProfile({super.key});

  @override
  State<UserProfile> createState() => _UserProfileState();
}

class _UserProfileState extends State<UserProfile> {
  // ✨ Candy & Sunshine Sky Blue Theme
  static const Color _bg = AppColors.skyBg;
  static const Color _navyText = AppColors.navy;
  static const Color _buttonBlue = AppColors.blue;
  static const Color _skyLight = AppColors.skyLight;
  static const Color _mintGreen = AppColors.mintGreen;
  static const Color _coralRed = AppColors.coralRedBright;

  final _supabaseService = SupabaseService();
  final _picker = ImagePicker();

  String _username = '';
  String _email = '';
  int _standard = 1;
  String _grade = 'A'; // Default grade
  String _rate = '3'; // Default rate
  String _studyTime = '';
  String? _imagePath;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    try {
      final profile = await _supabaseService.getStudentProfile();
      final prefs = await SharedPreferences.getInstance();

      setState(() {
        _username = (profile?['username'] as String?) ?? 'Student';
        _email = _supabaseService.currentUser?.email ?? '';
        _standard = (profile?['standard'] as int?) ?? 1;
        _studyTime = (profile?['study_time'] as String?) ?? '';
        _grade = (profile?['grade'] as String?) ?? 'A';
        _rate = (profile?['rate'] as String?) ?? '3';
        // Locally-persisted, per-device only — there's no photo upload
        // pipeline (no storage bucket) behind this yet, so a picked avatar
        // used to just vanish the next time the app opened even though
        // picking it looked like it worked. Saving the path at least makes
        // it survive restarts on this same device/install.
        final savedPath = prefs.getString('profile_avatar_path');
        _imagePath =
            savedPath != null && File(savedPath).existsSync() ? savedPath : null;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Profile load error: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _pickImage() async {
    final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
    if (image != null) {
      setState(() => _imagePath = image.path);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('profile_avatar_path', image.path);
    }
  }

  // Translates common Supabase Auth failures into messages a student would
  // actually understand, instead of showing the raw exception text (which
  // is written to the debug console either way, so nothing is lost for
  // troubleshooting — see the debugPrint at each call site).
  String _friendlyAuthError(AuthException e) {
    final msg = e.message.toLowerCase();
    if (e.statusCode == '422' || msg.contains('already') || msg.contains('registered')) {
      return 'That email is already in use.';
    }
    if (msg.contains('security purposes') || msg.contains('rate limit')) {
      return "You're trying too often — please wait a minute and try again.";
    }
    if (msg.contains('session') || msg.contains('token')) {
      return 'Your session expired — please log out and back in, then try again.';
    }
    return e.message;
  }

  // ── Change password dialog ───────────────────────────────────────────────
  void _showChangePasswordDialog() {
    final newPassCtrl = TextEditingController();
    final confirmPassCtrl = TextEditingController();
    String? error;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setDialog) => AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(28),
          ), // Bubbly dialog
          title: const Text(
            'Change Password',
            style: TextStyle(fontWeight: FontWeight.w900, color: _navyText),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _dialogField(
                newPassCtrl,
                'New password',
                Icons.lock_outline_rounded,
                obscure: true,
              ),
              const SizedBox(height: 16),
              _dialogField(
                confirmPassCtrl,
                'Confirm new password',
                Icons.lock_outline_rounded,
                obscure: true,
              ),
              if (error != null) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: _coralRed.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    error!,
                    style: const TextStyle(
                      color: _coralRed,
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(
                'Cancel',
                style: TextStyle(
                  color: _navyText.withValues(alpha: 0.5),
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: _buttonBlue,
                elevation: 0,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
              onPressed: () async {
                if (newPassCtrl.text.length < 8) {
                  setDialog(
                    () => error = 'Password must be at least 8 characters',
                  );
                  return;
                }
                if (newPassCtrl.text != confirmPassCtrl.text) {
                  setDialog(() => error = 'Passwords do not match');
                  return;
                }
                try {
                  await Supabase.instance.client.auth.updateUser(
                    UserAttributes(password: newPassCtrl.text),
                  );
                  if (ctx.mounted) {
                    Navigator.pop(ctx);
                    _showSnack('Password updated successfully!', success: true);
                  }
                } on AuthException catch (e) {
                  debugPrint('Password update failed: ${e.statusCode} ${e.message}');
                  setDialog(() => error = _friendlyAuthError(e));
                } catch (e) {
                  debugPrint('Password update failed: $e');
                  setDialog(() => error = 'Could not update your password. Please try again.');
                }
              },
              child: const Text(
                'Save',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Edit profile dialog ──────────────────────────────────────────────────
  void _showEditProfileDialog() {
    final usernameCtrl = TextEditingController(text: _username);
    final emailCtrl = TextEditingController(text: _email);
    int selectedStandard = _standard;
    String selectedStudyTime = _studyTime;
    final selectedGrade = _grade;
    final selectedRate = _rate;
    String? dialogError;
    bool isSaving = false;

    final studyTimes = ['15 minutes', '30 minutes', '45 minutes', '1 hour'];

    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setDialog) => AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(28),
          ), // Bubbly dialog
          title: const Text(
            'Edit Profile',
            style: TextStyle(fontWeight: FontWeight.w900, color: _navyText),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Username',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: _navyText.withValues(alpha: 0.7),
                  ),
                ),
                const SizedBox(height: 12),
                _dialogField(usernameCtrl, 'Username', Icons.face_rounded),
                const SizedBox(height: 24),
                Text(
                  'Email address',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: _navyText.withValues(alpha: 0.7),
                  ),
                ),
                const SizedBox(height: 12),
                _dialogField(
                  emailCtrl,
                  'Email address',
                  Icons.mail_rounded,
                ),
                if (dialogError != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: _coralRed.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      dialogError!,
                      style: const TextStyle(
                        color: _coralRed,
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                Text(
                  'School standard',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: _navyText.withValues(alpha: 0.7),
                  ),
                ),
                const SizedBox(height: 12),
                // 2 rows of 3, instead of a free-flowing Wrap — a fixed
                // grid rather than however many happen to fit per row.
                for (var row = 0; row < 2; row++) ...[
                  if (row > 0) const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: List.generate(3, (col) {
                      final std = row * 3 + col + 1;
                      final sel = std == selectedStandard;
                      return GestureDetector(
                        onTap: () => setDialog(() => selectedStandard = std),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          width: 56,
                          height: 48,
                          decoration: BoxDecoration(
                            color: sel ? _buttonBlue : _bg,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: sel ? _buttonBlue : _skyLight,
                              width: 2,
                            ),
                          ),
                          child: Center(
                            child: Text(
                              '$std',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                                color: sel ? Colors.white : _navyText,
                              ),
                            ),
                          ),
                        ),
                      );
                    }),
                  ),
                ],
                const SizedBox(height: 24),
                Text(
                  'Daily study time',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: _navyText.withValues(alpha: 0.7),
                  ),
                ),
                const SizedBox(height: 12),
                ...studyTimes.map((t) {
                  final sel = t == selectedStudyTime;
                  return GestureDetector(
                    onTap: () => setDialog(() => selectedStudyTime = t),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                      decoration: BoxDecoration(
                        color: sel ? _buttonBlue.withValues(alpha: 0.1) : _bg,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: sel ? _buttonBlue : _skyLight,
                          width: 2,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.timer_rounded,
                            color: sel
                                ? _buttonBlue
                                : _navyText.withValues(alpha: 0.4),
                            size: 20,
                          ),
                          const SizedBox(width: 12),
                          Text(
                            t,
                            style: TextStyle(
                              fontSize: 15,
                              color: sel ? _buttonBlue : _navyText,
                              fontWeight: sel
                                  ? FontWeight.w800
                                  : FontWeight.w600,
                            ),
                          ),
                          const Spacer(),
                          if (sel)
                            const Icon(
                              Icons.check_circle_rounded,
                              color: _buttonBlue,
                              size: 20,
                            ),
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
              child: Text(
                'Cancel',
                style: TextStyle(
                  color: _navyText.withValues(alpha: 0.5),
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: _buttonBlue,
                elevation: 0,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
              onPressed: isSaving
                  ? null
                  : () async {
                      final newEmail = emailCtrl.text.trim();
                      if (newEmail.isEmpty ||
                          !RegExp(
                            r'^[\w\.-]+@[\w\.-]+\.\w{2,}$',
                          ).hasMatch(newEmail)) {
                        setDialog(
                          () => dialogError = 'Enter a valid email address',
                        );
                        return;
                      }

                      setDialog(() {
                        isSaving = true;
                        dialogError = null;
                      });

                      final emailChanged = newEmail != _email;
                      if (emailChanged) {
                        try {
                          await _supabaseService.updateEmail(newEmail);
                        } on AuthException catch (e) {
                          // Logged regardless of which friendly message is
                          // shown — this used to be swallowed with zero
                          // logging anywhere, so a real failure was
                          // undiagnosable even for us.
                          debugPrint('Email update failed: ${e.statusCode} ${e.message}');
                          setDialog(() {
                            isSaving = false;
                            dialogError = _friendlyAuthError(e);
                          });
                          return;
                        } catch (e) {
                          debugPrint('Email update failed: $e');
                          setDialog(() {
                            isSaving = false;
                            dialogError = 'Could not update email. Try again.';
                          });
                          return;
                        }
                      }

                      try {
                        await _supabaseService.saveStudentProfile(
                          username: usernameCtrl.text.trim(),
                          age: selectedStandard + 6,
                          standard: selectedStandard,
                          studyTime: selectedStudyTime,
                          grade: selectedGrade,
                          rate: selectedRate,
                        );
                        setState(() {
                          _username = usernameCtrl.text.trim();
                          _standard = selectedStandard;
                          _studyTime = selectedStudyTime;
                          // Fixes a real bug: this used to never update, so
                          // the NEXT time Edit Profile was opened, the email
                          // field still pre-filled with the stale old
                          // address, and saving again (even with nothing
                          // touched) treated it as another email change and
                          // re-called updateEmail.
                          if (emailChanged) _email = newEmail;
                        });
                        if (ctx.mounted) {
                          Navigator.pop(ctx);
                          _showSnack(
                            emailChanged
                                ? 'Profile updated! Check both your old and new email inbox to confirm the email change.'
                                : 'Profile updated!',
                            success: true,
                          );
                        }
                      } catch (e) {
                        // Also used to be swallowed silently — logged now so
                        // a genuine save failure (RLS, a bad column value,
                        // ...) is actually diagnosable instead of just "some
                        // error".
                        debugPrint('Profile save failed: $e');
                        setDialog(() {
                          isSaving = false;
                          dialogError = 'Failed to save. Try again.';
                        });
                      }
                    },
              child: const Text(
                'Save',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
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
        MaterialPageRoute(builder: (_) => const AuthScreen()),
        (_) => false,
      );
    }
  }

  void _showFontSizeDialog() {
    const options = {'Small': 0.9, 'Medium': 1.0, 'Large': 1.2};
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Font Size',
            style: TextStyle(fontWeight: FontWeight.w900, color: _navyText)),
        content: StatefulBuilder(
          builder: (ctx, setDialog) => Column(
            mainAxisSize: MainAxisSize.min,
            children: options.entries.map((e) {
              final sel = (gFontScale.value - e.value).abs() < 0.01;
              return GestureDetector(
                onTap: () async {
                  gFontScale.value = e.value;
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.setDouble('font_scale', e.value);
                  setDialog(() {});
                },
                child: Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    color: sel
                        ? _buttonBlue.withValues(alpha: 0.12)
                        : _bg,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                        color: sel ? _buttonBlue : Colors.transparent,
                        width: 1.5),
                  ),
                  child: Row(children: [
                    Text(e.key,
                        style: TextStyle(
                            fontSize: 15 * e.value,
                            fontWeight: FontWeight.w800,
                            color: _navyText)),
                    const Spacer(),
                    if (sel)
                      const Icon(Icons.check_circle, color: _buttonBlue),
                  ]),
                ),
              );
            }).toList(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Done',
                style: TextStyle(fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
  }

  Future<void> _showReminderDialog() async {
    final prefs = await SharedPreferences.getInstance();
    bool enabled = prefs.getBool('reminder_enabled') ?? true;
    int hour = prefs.getInt('reminder_hour') ?? 17;
    int minute = prefs.getInt('reminder_minute') ?? 0;

    String formatTime(int h, int m) {
      final period = h >= 12 ? 'PM' : 'AM';
      final h12 = h % 12 == 0 ? 12 : h % 12;
      return '$h12:${m.toString().padLeft(2, '0')} $period';
    }

    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialog) => AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
          title: const Text(
            'Study Reminder',
            style: TextStyle(fontWeight: FontWeight.w900, color: _navyText),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Daily reminder',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: _navyText,
                      ),
                    ),
                  ),
                  Switch(
                    value: enabled,
                    activeColor: _buttonBlue,
                    onChanged: (v) async {
                      setDialog(() => enabled = v);
                      await prefs.setBool('reminder_enabled', v);
                      if (v) {
                        await NotificationService().scheduleDailyReminder(
                          hour: hour,
                          minute: minute,
                        );
                      } else {
                        await NotificationService().cancelDailyReminder();
                      }
                    },
                  ),
                ],
              ),
              const SizedBox(height: 8),
              GestureDetector(
                onTap: !enabled
                    ? null
                    : () async {
                        final picked = await showTimePicker(
                          context: ctx,
                          initialTime: TimeOfDay(hour: hour, minute: minute),
                        );
                        if (picked == null) return;
                        setDialog(() {
                          hour = picked.hour;
                          minute = picked.minute;
                        });
                        await prefs.setInt('reminder_hour', hour);
                        await prefs.setInt('reminder_minute', minute);
                        await NotificationService().scheduleDailyReminder(
                          hour: hour,
                          minute: minute,
                        );
                      },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  decoration: BoxDecoration(
                    color: enabled ? _bg : Colors.grey.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: _skyLight, width: 2),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.access_time_rounded,
                        color: enabled
                            ? _buttonBlue
                            : _navyText.withValues(alpha: 0.3),
                        size: 20,
                      ),
                      const SizedBox(width: 12),
                      Text(
                        formatTime(hour, minute),
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: enabled
                              ? _navyText
                              : _navyText.withValues(alpha: 0.3),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Done',
                  style: TextStyle(fontWeight: FontWeight.w800)),
            ),
          ],
        ),
      ),
    );
  }

  void _showLogoutConfirm() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        title: const Text(
          'Log out?',
          style: TextStyle(
            fontWeight: FontWeight.w900,
            color: _navyText,
            fontSize: 22,
          ),
        ),
        content: Text(
          'You will need to sign in again next time to continue learning.',
          style: TextStyle(
            color: _navyText.withValues(alpha: 0.7),
            fontSize: 15,
            fontWeight: FontWeight.w500,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'Cancel',
              style: TextStyle(
                color: _navyText.withValues(alpha: 0.5),
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: _coralRed,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
            ),
            onPressed: () {
              Navigator.pop(context);
              _logout();
            },
            child: const Text(
              'Log out',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 16,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showSnack(String message, {bool success = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: success ? _mintGreen : _coralRed,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        automaticallyImplyLeading: false,
        title: const Text(
          'My Profile',
          style: TextStyle(
            fontWeight: FontWeight.w900,
            color: _navyText,
            fontSize: 24,
          ),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: _buttonBlue))
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
                                  offset: const Offset(0, 10),
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
                                        color: _buttonBlue,
                                      ),
                                    )
                                  : null,
                            ),
                          ),
                          Positioned(
                            bottom: 0,
                            right: 0,
                            child: GestureDetector(
                              onTap: _pickImage,
                              child: Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: _buttonBlue,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: Colors.white,
                                    width: 3,
                                  ),
                                ),
                                child: const Icon(
                                  Icons.camera_alt_rounded,
                                  color: Colors.white,
                                  size: 18,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Name + email
                    Text(
                      _username,
                      style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w900,
                        color: _navyText,
                      ),
                    ),
                    if (_email.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        _email,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: _navyText.withValues(alpha: 0.6),
                        ),
                      ),
                    ],
                    const SizedBox(height: 20),

                    // ── At-a-glance stats ─────────────────────────────────
                    // The screen used to only show these values buried
                    // inside the Edit Profile dialog — a profile page should
                    // show a student's own info directly, not hide it
                    // behind an edit form.
                    _statsRow(),
                    const SizedBox(height: 24),

                    // ── Menu items ────────────────────────────────────────
                    _menuCard(
                      icon: Icons.edit_rounded,
                      title: 'Edit Profile',
                      subtitle: 'Update username, standard, study time',
                      iconColor: _buttonBlue,
                      onTap: _showEditProfileDialog,
                    ),
                    const SizedBox(height: 16),
                    _menuCard(
                      icon: Icons.lock_rounded,
                      title: 'Change Password',
                      subtitle: 'Keep your account safe',
                      iconColor: _mintGreen,
                      onTap: _showChangePasswordDialog,
                    ),
                    const SizedBox(height: 16),
                    _menuCard(
                      icon: Icons.format_size_rounded,
                      title: 'Font Size',
                      subtitle: 'Adjust the font size for better readability',
                      iconColor: _buttonBlue,
                      onTap: _showFontSizeDialog,
                    ),
                    const SizedBox(height: 16),
                    _menuCard(
                      icon: Icons.notifications_active_rounded,
                      title: 'Study Reminder',
                      subtitle: 'Get a daily nudge to finish your task',
                      iconColor: _mintGreen,
                      onTap: _showReminderDialog,
                    ),
                    const SizedBox(height: 16),
                    _menuCard(
                      icon: Icons.logout_rounded,
                      title: 'Log Out',
                      subtitle: 'See you next time!',
                      iconColor: _coralRed,
                      onTap: _showLogoutConfirm,
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _statsRow() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: _navyText.withValues(alpha: 0.05),
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Row(
        children: [
          _statItem(Icons.school_rounded, 'Standard', 'Std $_standard', _buttonBlue),
          _statDivider(),
          _statItem(Icons.timer_rounded, 'Study Time', _studyTime.isEmpty ? '—' : _studyTime, _mintGreen),
          _statDivider(),
          _statItem(Icons.grade_rounded, 'Grade', _grade, const Color(0xFFFFA726)),
        ],
      ),
    );
  }

  Widget _statDivider() => Container(width: 1, height: 40, color: _skyLight);

  Widget _statItem(IconData icon, String label, String value, Color color) {
    return Expanded(
      child: Column(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 6),
          Text(value,
              style: const TextStyle(
                  fontSize: 15, fontWeight: FontWeight.w900, color: _navyText)),
          const SizedBox(height: 2),
          Text(label,
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: _navyText.withValues(alpha: 0.5))),
        ],
      ),
    );
  }

  Widget _menuCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color iconColor,
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
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(24),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: iconColor.withValues(
                      alpha: 0.15,
                    ), // Vibrant background
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(icon, color: iconColor, size: 24),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 16,
                          color: _navyText,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 13,
                          color: _navyText.withValues(alpha: 0.6),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.arrow_forward_ios_rounded,
                  size: 16,
                  color: _navyText.withValues(alpha: 0.3),
                ),
              ],
            ),
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
      style: const TextStyle(
        fontSize: 15,
        color: _navyText,
        fontWeight: FontWeight.w600,
      ),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(
          color: _navyText.withValues(alpha: 0.4),
          fontSize: 14,
        ),
        prefixIcon: Icon(icon, color: _buttonBlue, size: 20),
        filled: true,
        fillColor: _bg, // Use sky blue inside the white dialog
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: _buttonBlue, width: 2),
        ),
      ),
    );
  }
}