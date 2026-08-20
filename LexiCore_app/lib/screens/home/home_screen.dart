import 'package:flutter/material.dart';
import '../../models/learner_model.dart';
import '../../services/supabase_service.dart';
import '../../services/mastery_service.dart';
import '../../widgets/lexi_nav_bar.dart';
import 'article_screen.dart';
import '../ai_schedule/study_schedule_screen.dart';
import '../modules/module_selection_screen.dart';
import '../modules/vocabulary_module_screen.dart';
import '../modules/grammar_module_screen.dart';
import '../modules/reading_module_screen.dart';
import '../modules/writing_module_screen.dart';
import '../ai_chatbot/ai_chatbot_screen.dart';
import '../user_profiling/user_profile_screen.dart';
import '../modules/adaptive_practice_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  // Foundation Colors
  static const Color _bg         = Color(0xFFF0F8FF); // Soft Sky Blue background
  static const Color _navyText   = Color(0xFF003C8F);
  
  // Vibrant Candy Colors for UI Elements
  static const Color _buttonBlue = Color(0xFF1E88E5);
  static const Color _starYellow = Color(0xFFFFD54F);
  static const Color _mintGreen  = Color(0xFF4DB6AC);
  static const Color _coralRed   = Color(0xFFE57373);
  static const Color _lightblue = Color(0xFF64B5F6);
  static const Color _brightOrange  = Color(0xFFFF9800);

  final _supabaseService = SupabaseService();
  final _mastery = MasteryService();
  MasterySummary? _summary;

  int _selectedIndex = 0;

  String _username      = '';
  int    _detectedLevel = 3;
  bool   _isLoading     = true;

  // Today's task from the stored weekly schedule (see MasteryService's
  // getOrGenerateWeeklySchedule/getTodayTask) — {day, skill, task_label,
  // sub_skill_code} for a normal day, or {type: 'assessment'|'rest', ...}.
  Map<String, dynamic>? _todayTask;
  String? _weekGoal;

  static const Map<String, Color> _skillColorMap = {
    'Vocabulary': _brightOrange,
    'Grammar': _mintGreen,
    'Reading': _lightblue,
    'Writing': _coralRed,
  };
  static const Map<String, IconData> _skillIconMap = {
    'Vocabulary': Icons.abc_rounded,
    'Grammar': Icons.rule_rounded,
    'Reading': Icons.menu_book_rounded,
    'Writing': Icons.edit_rounded,
  };

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final profile    = await _supabaseService.getStudentProfile();
      final assessment = await _supabaseService.getAssessmentResults();
      final summary    = await _mastery.masterySummary();
      final todayTask  = await _mastery.getTodayTask();
      final plan       = await _mastery.getOrGenerateWeeklySchedule();

      if (mounted) {
        setState(() {
          _username      = (profile?['username']         as String?) ?? 'Student';
          _detectedLevel = (assessment?['detected_level'] as int?)   ?? 3;
          _summary       = summary;
          _todayTask     = todayTask;
          _weekGoal      = plan?['week_goal'] as String?;
          _isLoading     = false;
        });
      }
    } catch (e) {
      debugPrint('Home load error: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// Live per-skill score (0-100) from the mastery map, the same source of
  /// truth `_buildLearningCard()` already uses — falls back to 0 until the
  /// student has any skill_mastery data yet.
  double _liveScore(String skill) {
    final avg = _summary?.avgRungBySkill[skill];
    return avg == null ? 0 : avg / 5 * 100;
  }

  String get _weaknessSkill {
    final scores = {
      for (final s in const ['Vocabulary', 'Grammar', 'Reading', 'Writing'])
        s: _liveScore(s),
    };
    return scores.entries.reduce((a, b) => a.value <= b.value ? a : b).key;
  }
  
  // Navigates directly to the correct module screen based on today's skill
  void _startMission(String skill) {
    Widget destination;
    switch (skill) {
      case 'Vocabulary':
        destination = const VocabularyModuleScreen();
        break;
      case 'Grammar':
        destination = const GrammarModuleScreen();
        break;
      case 'Reading':
        destination = const ReadingModuleScreen();
        break;
      case 'Writing':
        destination = const WritingModuleScreen();
        break;
      default:
        destination = const VocabularyModuleScreen();
    }
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => destination),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      _buildHomeView(),
      const StudyScheduleScreen(),
      const ModuleSelectionScreen(),
      const AiChatbotScreen(),
      const UserProfile(),
    ];

    return Scaffold(
      backgroundColor: _bg,
      extendBody: false,
      appBar: _selectedIndex == 0
          ? AppBar(
              backgroundColor: Colors.transparent,
              elevation: 0,
              centerTitle: false,
              automaticallyImplyLeading: false,
              title: Row(
                children: [
                Image.asset('assets/icon_image.png', width: 32, height: 32, fit: BoxFit.contain),
              const SizedBox(width: 10),
              const Text(
                'LexiCore',
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  color: _buttonBlue,
                  fontSize: 26,
                  letterSpacing: 0.5,
                ),
              ),
              ],
              ),
              actions: [
                // Notification / info icon
                Padding(
                  padding: const EdgeInsets.only(right: 16),
                  child: Container(
                    width: 38, height: 38,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                            color: Colors.black.withValues(alpha: 0.07),
                            blurRadius: 8)
                      ],
                    ),
                    child: const Icon(Icons.notifications_rounded,
                        color: _starYellow, size: 20),
                  ),
                ),
              ],
            )
          : null,
      body: SafeArea(bottom: false, child: pages[_selectedIndex]),
      bottomNavigationBar: LexiNavBar(
        selectedIndex: _selectedIndex,
        onTap: (i) => setState(() => _selectedIndex = i),
      ),
    );
  }

  Widget _buildHomeView() {
    if (_isLoading) {
      return const Center(
          child: CircularProgressIndicator(color: _buttonBlue));
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 100),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Greeting
          Text(
            'Hello, $_username 👋',
            style: const TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w900,
              color: _navyText,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Level $_detectedLevel learner — keep it up!',
            style: TextStyle(fontSize: 15, color: _navyText.withValues(alpha: 0.7), fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 28),

          // ── Today's Task: progress, strengths, weaknesses, start ──
          _sectionLabel('Today\'s Task'),
          const SizedBox(height: 12),
          _buildLearningCard(),
          const SizedBox(height: 28),

          // ── Card 2: Dashboard ─────────────────────────────────────────
          _sectionLabel('Your Progress'),
          const SizedBox(height: 12),
          _buildDashboardCard(),
          const SizedBox(height: 28),

          // ── Card 3: Article ───────────────────────────────────────────
          _sectionLabel('Daily Reading'),
          const SizedBox(height: 12),
          _buildArticleCard(),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  // ── My Learning: strengths / weaknesses / progress ──────────────────────
  // Turns the internal ability/rung into a friendly, human-readable level.
  String _levelWord(double overall) {
    final avgRung = overall * 5;
    if (avgRung < 1.5) return 'Just starting 🌱';
    if (avgRung < 2.5) return 'Growing 🌿';
    if (avgRung < 3.5) return 'Doing well 💪';
    return 'Strong ⭐';
  }

  Widget _buildLearningCard() {
    final s = _summary;
    final boxShadow = [
      BoxShadow(
          color: _buttonBlue.withValues(alpha: 0.08),
          blurRadius: 12,
          offset: const Offset(0, 4)),
    ];
    if (s == null) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: boxShadow),
        child: const Row(children: [
          Text('🗺️', style: TextStyle(fontSize: 32)),
          SizedBox(width: 14),
          Expanded(
            child: Text('Finish your quiz to unlock your learning map!',
                style: TextStyle(
                    color: _navyText,
                    fontSize: 15,
                    fontWeight: FontWeight.w700)),
          ),
        ]),
      );
    }
    final pct = (s.overall * 100).round();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: boxShadow),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Text('⭐', style: TextStyle(fontSize: 20)),
            const SizedBox(width: 8),
            Text('You\'ve mastered $pct%',
                style: const TextStyle(
                    color: _navyText,
                    fontSize: 16,
                    fontWeight: FontWeight.w900)),
          ]),
          Padding(
            padding: const EdgeInsets.only(top: 2, left: 28),
            child: Text(_levelWord(s.overall),
                style: TextStyle(
                    color: _navyText.withValues(alpha: 0.65),
                    fontSize: 13,
                    fontWeight: FontWeight.w700)),
          ),
          if (_weekGoal != null) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: _brightOrange.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: _brightOrange.withValues(alpha: 0.3)),
              ),
              child: Row(children: [
                const Text('🎯', style: TextStyle(fontSize: 16)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(_weekGoal!,
                      style: TextStyle(
                          color: Colors.orange.shade900,
                          fontSize: 13,
                          fontWeight: FontWeight.w700)),
                ),
              ]),
            ),
          ],
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: LinearProgressIndicator(
              value: s.overall.clamp(0.0, 1.0),
              minHeight: 12,
              backgroundColor: _bg,
              valueColor: const AlwaysStoppedAnimation(_mintGreen),
            ),
          ),
          const SizedBox(height: 18),
          Row(children: [
            Expanded(child: _skillPill('💪', 'Strong', s.strongest, _mintGreen)),
            const SizedBox(width: 12),
            Expanded(child: _skillPill('🎯', 'Focus on', s.weakest, _brightOrange)),
          ]),
          const SizedBox(height: 16),
          ..._todayTaskAction(s),
          const SizedBox(height: 6),
          Center(
            child: TextButton(
              onPressed: () => _startMission(s.weakest),
              child: const Text('Or choose a skill yourself',
                  style: TextStyle(
                      color: _navyText,
                      fontWeight: FontWeight.w700,
                      fontSize: 13)),
            ),
          ),
        ],
      ),
    );
  }

  /// The card's primary action, driven by today's entry in the stored
  /// weekly schedule rather than just "practise your weakest skill" —
  /// Thursday saying "Write: Free Composition" means tapping the button
  /// launches that specific sub-skill, not a generic session.
  List<Widget> _todayTaskAction(MasterySummary s) {
    final task = _todayTask;
    if (task == null) {
      // Fallback if no schedule could be generated yet.
      return [
        SizedBox(
          width: double.infinity,
          height: 48,
          child: ElevatedButton.icon(
            onPressed: () => Navigator.push(context,
                MaterialPageRoute(
                    builder: (_) => AdaptivePracticeScreen(focusSkill: s.weakest))),
            style: ElevatedButton.styleFrom(
              backgroundColor: _brightOrange,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
            ),
            icon: const Icon(Icons.bolt_rounded, size: 20),
            label: Text('Start Practice — ${s.weakest}',
                style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
          ),
        ),
      ];
    }

    final type = task['type'] as String?;
    if (type == 'rest') {
      return const [
        Center(
          child: Text('Enjoy your rest day! 🌤️ See you tomorrow.',
              style: TextStyle(
                  color: _navyText, fontWeight: FontWeight.w700, fontSize: 14)),
        ),
      ];
    }

    final label = task['task_label'] as String? ?? 'Start today\'s task';
    final skill = task['skill'] as String?;
    final color = _skillColorMap[skill] ?? _brightOrange;
    final icon = type == 'assessment'
        ? Icons.fact_check_rounded
        : (_skillIconMap[skill] ?? Icons.bolt_rounded);

    return [
      SizedBox(
        width: double.infinity,
        height: 48,
        child: ElevatedButton.icon(
          onPressed: () => _startTodayTask(task),
          style: ElevatedButton.styleFrom(
            backgroundColor: color,
            foregroundColor: Colors.white,
            elevation: 0,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          ),
          icon: Icon(icon, size: 20),
          label: Text(label,
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
        ),
      ),
    ];
  }

  Future<void> _startTodayTask(Map<String, dynamic> task) async {
    final type = task['type'] as String?;
    if (type == 'assessment') {
      final queue = await _mastery.buildWeeklyAssessmentQueue();
      if (queue.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('Finish a few practice sessions first, then come back for your weekly assessment!')));
        }
        return;
      }
      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => AdaptivePracticeScreen(
            fixedQueue: queue,
            resultModuleName: 'Weekly Assessment',
            resultColor: const Color(0xFF6A1B9A),
            resultIcon: Icons.fact_check_rounded,
            onSessionComplete: (answered, correct) {
              _mastery.saveWeeklyCheckin(itemsAnswered: answered, itemsCorrect: correct);
            },
          ),
        ),
      );
      await _mastery.markTodayTaskComplete();
      if (mounted) _loadData();
      return;
    }

    final subSkillCode = task['sub_skill_code'] as String?;
    final skill = (task['skill'] as String?) ?? 'Grammar';
    if (subSkillCode == null) {
      _startMission(skill);
      return;
    }

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AdaptivePracticeScreen(
          fixedQueue: [PracticeQueueItem(subSkillCode, 8)],
          resultModuleName: skill,
          resultColor: _skillColorMap[skill],
          resultIcon: _skillIconMap[skill],
        ),
      ),
    );
    await _mastery.markTodayTaskComplete();
    if (mounted) _loadData();
  }

  Widget _skillPill(String emoji, String label, String skill, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$emoji $label',
              style: TextStyle(
                  color: color, fontSize: 12, fontWeight: FontWeight.w800)),
          const SizedBox(height: 2),
          Text(skill,
              style: const TextStyle(
                  color: _navyText, fontSize: 15, fontWeight: FontWeight.w900)),
        ],
      ),
    );
  }

  // ── Card 2: Dashboard ──────────────────────────────────────────────────
  Widget _buildDashboardCard() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
              color: _navyText.withValues(alpha: 0.05),
              blurRadius: 15,
              offset: const Offset(0, 5)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Skill score bars with Candy Colors! Sourced from the live mastery
          // map (same source as the learning card above) rather than the
          // static one-time assessment score, so this never drifts out of
          // sync with actual practice.
          _scoreBar('Vocabulary', _liveScore('Vocabulary').round(), _brightOrange),
          _scoreBar('Grammar',    _liveScore('Grammar').round(),    _mintGreen),
          _scoreBar('Reading',    _liveScore('Reading').round(),    _lightblue),
          _scoreBar('Writing',    _liveScore('Writing').round(),    _coralRed),
          const SizedBox(height: 16),

          // Divider
          Container(height: 2, color: const Color(0xFFF0F8FF)),
          const SizedBox(height: 16),

          // Strength / Weakness row
          const SizedBox(height: 18),

          // Recommendation (Mint Green)
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: _mintGreen.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                  color: _mintGreen.withValues(alpha: 0.3), width: 2),
            ),
            child: Row(
              children: [
                const Icon(Icons.tips_and_updates_rounded,
                    color: _mintGreen, size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Focus on $_weaknessSkill to level up faster!',
                    style: TextStyle(
                        fontSize: 14,
                        color: Colors.teal.shade800,
                        fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Card 3: Article ────────────────────────────────────────────────────
  Widget _buildArticleCard() {
    return GestureDetector(
      onTap: () => Navigator.push(context,
          MaterialPageRoute(builder: (_) => const ArticleScreen())),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(28),
          boxShadow: [
            BoxShadow(
                color: _navyText.withValues(alpha: 0.05),
                blurRadius: 15,
                offset: const Offset(0, 5)),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 76, height: 76,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFFFD54F), Color(0xFFFF9800)], // Sunny Yellow to Orange
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(22),
              ),
              child: const Icon(Icons.menu_book_rounded,
                  color: Colors.white, size: 36),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Daily Reading',
                      style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          color: _navyText)),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: _brightOrange.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Text('Read now',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: _brightOrange)),
                  ),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios_rounded,
                size: 18, color: _brightOrange),
          ],
        ),
      ),
    );
  }

  Widget _scoreBar(String label, int score, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label,
                  style: TextStyle(
                      fontSize: 14,
                      color: _navyText.withValues(alpha: 0.8),
                      fontWeight: FontWeight.w800)),
              Text('$score%',
                  style: TextStyle(
                      fontSize: 14,
                      color: color,
                      fontWeight: FontWeight.w900)),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: score / 100,
              backgroundColor: _bg, // Sky blue background for the track
              valueColor: AlwaysStoppedAnimation(color),
              minHeight: 10, // Thicker bars for kids
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionLabel(String text) => Text(
    text,
    style: const TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w900,
        color: _navyText),
  );
}