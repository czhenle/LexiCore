import 'package:flutter/material.dart';
import '../../services/supabase_service.dart';
import 'initial_assessment_screen.dart';

class OnboardingProfileScreen extends StatefulWidget {
  final String username;

  const OnboardingProfileScreen({super.key, required this.username});

  @override
  State<OnboardingProfileScreen> createState() =>
      _OnboardingProfileScreenState();
}

class _OnboardingProfileScreenState extends State<OnboardingProfileScreen>
    with SingleTickerProviderStateMixin {
  final _supabaseService = SupabaseService();

  // ✨ Sky Blue Theme mapped to the structural layout
  static const Color _bg = Color(0xFFF0F8FF);
  static const Color _skyBlueLight = Color(0xFFDFF1FF);
  static const Color _navyText = Color(0xFF003C8F);
  static const Color _buttonBlue = Color(0xFF1E88E5);
  static const Color _textMid = Color(0xFF6B7280);
  static const Color _card = Colors.white;
  static const Color _divider = Color(0xFFE5E7EB);

  int _selectedStandard = 3;
  String _selectedStudyTime = '15 minutes';
  String _selectedAge = '9';

  bool _isSaving = false;
  String _errorMessage = '';

  final List<String> _studyTimes = [
    '15 minutes',
    '30 minutes',
    '45 minutes',
    '1 hour',
  ];
  final List<String> _ages = ['7', '8', '9', '10', '11', '12'];
  final List<int> _standards = [1, 2, 3, 4, 5, 6];

  late AnimationController _animCtrl;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _fadeAnim = CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut);
    _animCtrl.forward();
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    super.dispose();
  }

  Future<void> _saveAndContinue() async {
    setState(() {
      _isSaving = true;
      _errorMessage = '';
    });

    try {
      await _supabaseService.saveStudentProfile(
        username: widget.username,
        age: int.parse(_selectedAge),
        standard: _selectedStandard,
        studyTime: _selectedStudyTime,
      );

      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const InitialAssessmentScreen()),
        );
      }
    } catch (e) {
      setState(
        () => _errorMessage = 'Failed to save profile. Please try again.',
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: FadeTransition(
          opacity: _fadeAnim,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _header(),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
                  children: [
                    // --- SECTION 1: Personal Info (Age & Standard Dropdowns) ---
                    _section(Icons.person_outline_rounded, 'Personal Info', [
                      Row(
                        children: [
                          Expanded(child: _buildAgeDropdown()),
                          const SizedBox(width: 14),
                          Expanded(child: _buildStandardDropdown()),
                        ],
                      ),
                    ]),
                    const SizedBox(height: 16),

                    // --- SECTION 2: Daily Goal (Selectable Cards) ---
                    _section(Icons.access_time_rounded, 'Daily Goal', [
                      const Text(
                        'How long can you study each day?',
                        style: TextStyle(fontSize: 13, color: _textMid),
                      ),
                      const SizedBox(height: 12),
                      _buildStudyTimeSelector(),
                    ]),

                    if (_errorMessage.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 16, bottom: 8),
                        child: Text(
                          _errorMessage,
                          style: const TextStyle(
                            color: Colors.red,
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
              _bottomBar(),
            ],
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════
  // WIDGET COMPONENTS
  // ═══════════════════════════════════════════════════════

  Widget _header() => Container(
    color: _bg,
    padding: const EdgeInsets.fromLTRB(20, 14, 20, 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            GestureDetector(
              onTap: () async {
                await _supabaseService.signOut();
                if (!mounted) return;
                Navigator.pop(context);
              },
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: _card,
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: [
                    BoxShadow(
                      color: _navyText.withValues(alpha: 0.06),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.arrow_back_ios_new_rounded,
                  size: 16,
                  color: _navyText,
                ),
              ),
            ),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: _navyText,
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Text(
                'Step 2 of 6',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        Text(
          'Hi, ${widget.username}! 👋',
          style: const TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w900,
            color: _navyText,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          "Let's personalise your learning journey.",
          style: TextStyle(
            fontSize: 15,
            color: _textMid,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 10),
      ],
    ),
  );

  Widget _section(IconData icon, String title, List<Widget> children) =>
      Container(
        decoration: BoxDecoration(
          color: _card,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: _navyText.withValues(alpha: 0.04),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: _skyBlueLight,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: _buttonBlue, size: 18),
                ),
                const SizedBox(width: 10),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: _navyText,
                    letterSpacing: -0.3,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Divider(color: _divider, height: 1),
            const SizedBox(height: 16),
            ...children,
          ],
        ),
      );

  // --- Realstic Dropdowns ---
  Widget _labeled(String label, Widget child) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: _textMid,
        ),
      ),
      const SizedBox(height: 8),
      child,
    ],
  );

  Widget _buildAgeDropdown() => _labeled(
    'Age',
    Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
      decoration: BoxDecoration(
        color: _bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _selectedAge,
          isExpanded: true,
          icon: const Icon(
            Icons.keyboard_arrow_down_rounded,
            color: _textMid,
            size: 20,
          ),
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: _navyText,
          ),
          items: _ages
              .map(
                (age) => DropdownMenuItem(value: age, child: Text('$age yrs')),
              )
              .toList(),
          onChanged: (v) => setState(() => _selectedAge = v!),
        ),
      ),
    ),
  );

  Widget _buildStandardDropdown() => _labeled(
    'Standard',
    Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
      decoration: BoxDecoration(
        color: _bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<int>(
          value: _selectedStandard,
          isExpanded: true,
          icon: const Icon(
            Icons.keyboard_arrow_down_rounded,
            color: _textMid,
            size: 20,
          ),
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: _navyText,
          ),
          items: _standards
              .map(
                (std) => DropdownMenuItem(value: std, child: Text('Std $std')),
              )
              .toList(),
          onChanged: (v) => setState(() => _selectedStandard = v!),
        ),
      ),
    ),
  );

  // --- Realistic Goal Selector (from user_profiling_screen) ---
  Widget _buildStudyTimeSelector() => Column(
    children: _studyTimes.map((time) {
      final sel = _selectedStudyTime == time;
      return GestureDetector(
        onTap: () => setState(() => _selectedStudyTime = time),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: sel ? _skyBlueLight.withValues(alpha: 0.5) : _bg,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: sel ? _buttonBlue : _divider, width: 1.5),
          ),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: sel
                      ? _buttonBlue.withValues(alpha: 0.15)
                      : Colors.white,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.timer_rounded,
                  color: sel ? _buttonBlue : _textMid,
                  size: 20,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  time,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: sel ? _buttonBlue : _navyText,
                  ),
                ),
              ),
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: sel ? _buttonBlue : Colors.transparent,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: sel ? _buttonBlue : _textMid.withValues(alpha: 0.4),
                    width: 1.5,
                  ),
                ),
                child: sel
                    ? const Icon(
                        Icons.check_rounded,
                        color: Colors.white,
                        size: 14,
                      )
                    : null,
              ),
            ],
          ),
        ),
      );
    }).toList(),
  );

  Widget _bottomBar() => Container(
    padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
    decoration: BoxDecoration(
      color: _card,
      boxShadow: [
        BoxShadow(
          color: _navyText.withValues(alpha: 0.06),
          blurRadius: 16,
          offset: const Offset(0, -4),
        ),
      ],
    ),
    child: SizedBox(
      width: double.infinity,
      height: 56,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: _buttonBlue,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        onPressed: _isSaving ? null : _saveAndContinue,
        child: _isSaving
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 3,
                ),
              )
            : const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'Continue to Assessment',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                  ),
                  SizedBox(width: 8),
                  Icon(Icons.arrow_forward_rounded, size: 18),
                ],
              ),
      ),
    ),
  );
}
