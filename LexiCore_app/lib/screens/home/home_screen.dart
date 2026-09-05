import 'dart:convert';

import 'package:flutter/material.dart';
import '../../models/learner_model.dart';
import '../../services/supabase_service.dart';
import '../../services/mastery_service.dart';
import '../../services/notification_service.dart';
import '../../widgets/lexi_nav_bar.dart';
import 'article_screen.dart';
import '../ai_schedule/study_schedule_screen.dart';
import '../modules/module_selection_screen.dart';
import '../modules/vocabulary_module_screen.dart';
import '../modules/grammar_module_screen.dart';
import '../modules/reading_module_screen.dart';
import '../modules/writing_module_screen.dart';
import '../modules/essay_writing_screen.dart';
import '../modules/weekly_assessment_screen.dart';
import '../ai_chatbot/ai_chatbot_screen.dart';
import '../user_profiling/user_profile_screen.dart';
import '../modules/adaptive_practice_screen.dart';
import '../../theme/app_colors.dart';

/// One row in the notification bell's feed — see _showNotifications().
class _Notice {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  const _Notice({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    this.onTap,
  });
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  // Foundation Colors
  static const Color _bg         = AppColors.skyBg; // Soft Sky Blue background
  static const Color _navyText   = AppColors.navy;

  // Vibrant Candy Colors for UI Elements
  static const Color _buttonBlue = AppColors.blue;
  static const Color _starYellow = AppColors.starYellow;
  static const Color _mintGreen  = AppColors.mintGreen;
  static const Color _coralRed   = AppColors.coralRed;
  static const Color _lightblue = AppColors.lightBlue;
  static const Color _brightOrange  = AppColors.brightOrange;

  final _supabaseService = SupabaseService();
  final _mastery = MasteryService();
  MasterySummary? _summary;

  int _selectedIndex = 0;

  String _username      = '';
  bool   _isLoading     = true;
  bool   _todayCompleted = false;

  // Today's task from the stored weekly schedule (see MasteryService's
  // getOrGenerateWeeklySchedule/getTodayTask) — {day, skill, task_label,
  // sub_skill_code} for a normal day, or {type: 'assessment'|'rest', ...}.
  Map<String, dynamic>? _todayTask;
  String? _weekGoal;
  Map<String, int> _progressPercents = const {};

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
    // Once per mount, not per _loadData() — that also runs after every task
    // completion, and re-uploading unchanged reminder settings/re-registering
    // an unchanged FCM token each time is pointless. Neither is awaited: they
    // have nothing to do with drawing this screen. Here rather than on the
    // splash screen because a session is guaranteed by this point, which
    // isn't true there for a brand new sign-up.
    NotificationService().syncSavedReminderPrefs();
    NotificationService().initFcm();
  }

  /// A red dot on the bell whenever there's something worth the student's
  /// attention right now — kept in sync with what _showNotifications()
  /// actually lists, not a separate guess.
  bool get _hasNotifications =>
      !_isLoading && (!_todayCompleted && _todayTask?['type'] != 'rest');

  void _showNotifications() {
    final task = _todayTask;
    final isRestDay = task?['type'] == 'rest';
    final isAssessment = task?['type'] == 'assessment';
    final label = task?['task_label'] as String?;

    final notices = <_Notice>[
      if (!_todayCompleted && !isRestDay && task != null)
        _Notice(
          icon: isAssessment ? Icons.fact_check_rounded : Icons.bolt_rounded,
          color: isAssessment ? AppColors.purple : _brightOrange,
          title: isAssessment ? 'Weekly Assessment ready' : "Today's task is waiting",
          subtitle: label ?? 'Tap to get started',
          onTap: () {
            Navigator.pop(context);
            _startTodayTask(task);
          },
        ),
      if (_todayCompleted)
        _Notice(
          icon: Icons.celebration_rounded,
          color: _mintGreen,
          title: "Today's task is done!",
          subtitle: 'Nice work — come back tomorrow for the next one.',
        ),
      if (isRestDay)
        _Notice(
          icon: Icons.spa_rounded,
          color: _lightblue,
          title: 'Rest day',
          subtitle: 'No task scheduled today — enjoy the break!',
        ),
      _Notice(
        icon: Icons.notifications_active_rounded,
        color: _mintGreen,
        title: 'Study reminders',
        subtitle: 'Set a daily nudge from your Profile',
        onTap: () {
          Navigator.pop(context);
          setState(() => _selectedIndex = 4); // Profile tab
        },
      ),
    ];

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Notifications',
                  style: TextStyle(
                      fontSize: 18, fontWeight: FontWeight.w900, color: _navyText)),
              const SizedBox(height: 12),
              ...notices.map((n) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Material(
                      color: n.color.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(16),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(16),
                        onTap: n.onTap,
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Row(children: [
                            Icon(n.icon, color: n.color, size: 22),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(n.title,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w800,
                                          fontSize: 14,
                                          color: _navyText)),
                                  const SizedBox(height: 2),
                                  Text(n.subtitle,
                                      style: TextStyle(
                                          fontSize: 12,
                                          color: _navyText.withValues(alpha: 0.6))),
                                ],
                              ),
                            ),
                          ]),
                        ),
                      ),
                    ),
                  )),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _loadData() async {
    try {
      // Safety net: re-seeds skill_mastery from the persisted assessment
      // if it's somehow still empty (the one-shot call right after the
      // pre-assessment can fail silently) — a no-op once it has any rows.
      // Without this, masterySummary()/generateStudyPlan() below have
      // nothing to work with and Today's Task/the schedule never appear.
      await _mastery.ensureMasterySeeded();

      final profile    = await _supabaseService.getStudentProfile();
      final assessment = await _supabaseService.getAssessmentResults();
      final summary    = await _mastery.masterySummary();
      final todayTask  = await _mastery.getTodayTask();
      final plan       = await _mastery.getOrGenerateStudyPlan();

      final todayIso = _mastery.todayIso();
      final completedDays = Set<String>.from(
          (plan?['completed_days'] as List?)?.cast<String>() ?? const []);

      if (mounted) {
        setState(() {
          _username      = (profile?['username'] as String?) ?? 'Student';
          _summary       = summary;
          _todayTask     = todayTask;
          _todayCompleted = completedDays.contains(todayIso);
          _weekGoal      = plan?['plan_goal'] as String?;
          _progressPercents = _computeProgressPercents(assessment, profile);
          _isLoading     = false;
        });
      }
    } catch (e) {
      debugPrint('Home load error: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// The progress card's 4 percentages: real assessment scores if the
  /// student completed the test, else their self-evaluation ratings (1-5,
  /// stored as JSON in `student_profiles.rate`) scaled to 0-100 — never the
  /// live mastered-rung average, which is poorly calibrated right after a
  /// fresh seed. `_buildLearningCard()` below is the separate live-mastery
  /// view (updated by ongoing adaptive practice), deliberately distinct
  /// from this assessment/self-eval snapshot.
  Map<String, int> _computeProgressPercents(
      Map<String, dynamic>? assessment, Map<String, dynamic>? profile) {
    const skills = ['Vocabulary', 'Grammar', 'Reading', 'Writing'];
    if (assessment != null) {
      const keys = {
        'Vocabulary': 'vocabulary_score',
        'Grammar': 'grammar_score',
        'Reading': 'reading_score',
        'Writing': 'writing_score',
      };
      return {
        for (final s in skills) s: (assessment[keys[s]] as int?) ?? 0,
      };
    }
    final rateRaw = profile?['rate'] as String?;
    if (rateRaw != null && rateRaw.isNotEmpty) {
      try {
        final ratings = Map<String, dynamic>.from(jsonDecode(rateRaw) as Map);
        return {
          for (final s in skills)
            s: ((int.tryParse(ratings[s]?.toString() ?? '') ?? 0) * 20)
                .clamp(0, 100),
        };
      } catch (_) {
        // fall through to zeros below — malformed/missing self-eval data.
      }
    }
    return {for (final s in skills) s: 0};
  }

  // Navigates directly to the correct module screen based on today's skill.
  // Returns the push's Future so a caller that cares when the session ends
  // (_startTodayTask, to mark today's task complete) can await it — callers
  // that don't (the "choose a skill yourself" button) just don't await it.
  Future<void> _startMission(String skill) {
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
    return Navigator.push(
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
                // Notifications — a quick feed of what needs the student's
                // attention right now (today's task, an available weekly
                // assessment, ...), derived live from what Home already
                // knows rather than a separate stored inbox. Used to be
                // purely decorative (no tap handler at all).
                Padding(
                  padding: const EdgeInsets.only(right: 16),
                  child: GestureDetector(
                    onTap: _showNotifications,
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
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          const Center(
                            child: Icon(Icons.notifications_rounded,
                                color: _starYellow, size: 20),
                          ),
                          if (_hasNotifications)
                            Positioned(
                              top: 6, right: 7,
                              child: Container(
                                width: 8, height: 8,
                                decoration: const BoxDecoration(
                                    color: _coralRed, shape: BoxShape.circle),
                              ),
                            ),
                        ],
                      ),
                    ),
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
          const SizedBox(height: 20),

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
      // WeeklyAssessmentScreen builds its own plan (batch-generated, like
      // the pre-assessment) and orchestrates the quiz + any Writing task —
      // see its doc comment. onCompleted only fires if the WHOLE thing was
      // genuinely finished, not on an early exit from any of its steps.
      //
      // markTodayTaskComplete() is called FROM the callback itself, not
      // after this await resolves — see the doc comment on the Reading
      // branch below for why that distinction is the actual fix for a real
      // bug (the write used to lose a race against Home rebuilding).
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => WeeklyAssessmentScreen(onCompleted: () => _mastery.markTodayTaskComplete()),
        ),
      );
      if (mounted) _loadData();
      return;
    }

    final subSkillCode = task['sub_skill_code'] as String?;
    final skill = (task['skill'] as String?) ?? 'Grammar';

    // Reading always routes to its real module (a real passage + batch-
    // generated questions, grounded together) — the generic one-item
    // adaptive loop below has no passage to ground questions in. Pushed
    // directly (not via _startMission) so onCompleted can gate the
    // completion tick on genuinely finishing the question set.
    //
    // markTodayTaskComplete() fires FROM inside onCompleted, the instant
    // completion is detected — not after this `await Navigator.push`
    // resolves. That used to be a real bug: the module's own ResultScreen
    // ends with a "Back to home" button that does
    // `pushAndRemoveUntil(HomeScreen, (route) => false)`, which force-
    // removes THIS Home screen (the one running this very function) from
    // the stack. The code after the await still technically ran, but it
    // was racing a brand-new HomeScreen's own _loadData() (triggered by
    // being freshly pushed) — which usually read the schedule before the
    // completion write had landed, so the task showed as still incomplete
    // right after finishing it. Starting the write the moment
    // onCompleted fires — well before the student even reaches "Back to
    // home" — removes the race entirely.
    if (skill == 'Reading') {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ReadingModuleScreen(onCompleted: () => _mastery.markTodayTaskComplete()),
        ),
      );
      if (mounted) _loadData();
      return;
    }

    // Writing's only 2 sub-skills ARE the 2 composition modes (see the
    // writing_mode_sub_skills migration) — so a Writing day always means
    // "generate this exact composition task", never a picker. Going through
    // WritingModuleScreen (its mode-CHOOSING screen) would let the student
    // pick a different mode than the one actually targeted, and drops the
    // submit-button/timer UI EssayWritingScreen gives that task. Push it
    // directly instead — same as Vocabulary/Grammar below, adaptive
    // targeting just decided WHICH task, not whether to ask first.
    if (skill == 'Writing') {
      final mode = subSkillCode == 'writing.mode_free' ? 'free' : 'guided';
      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => EssayWritingScreen(
            mode: mode,
            onCompleted: () => _mastery.markTodayTaskComplete(),
          ),
        ),
      );
      if (mounted) _loadData();
      return;
    }

    if (subSkillCode == null) {
      _startMission(skill);
      return;
    }

    final studyMinutes = await _mastery.studentStudyMinutes();
    final count = _mastery.recommendedQueueCount(studyMinutes);
    if (!mounted) return;
    // Only mark today's task complete if the session genuinely finished
    // (onSessionComplete fires from inside _finishQueueSession — the whole
    // queue was answered) — NOT just because the pushed screen eventually
    // got popped. Exiting early via the X button pops the route without
    // ever firing this, so `completed` stays false and the schedule
    // correctly doesn't tick the day off.
    var completed = false;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AdaptivePracticeScreen(
          fixedQueue: [PracticeQueueItem(subSkillCode, count)],
          resultModuleName: skill,
          resultColor: _skillColorMap[skill],
          resultIcon: _skillIconMap[skill],
          // Renders through the same per-module visual style Vocabulary/
          // Grammar's own module screens use (accent app bar, progress
          // bar, card layout) — only the targeting (one weak sub-skill,
          // adaptive rung) differs from picking a topic yourself.
          moduleStyle: true,
          // Fires markTodayTaskComplete() immediately, from inside the
          // callback — not after this await resolves — for the same
          // pushAndRemoveUntil race-condition reason documented on the
          // Reading branch above. `completed` is kept too, only to gate
          // the snackbar below on a genuine finish.
          onSessionComplete: (answered, correct) {
            completed = true;
            _mastery.markTodayTaskComplete();
          },
        ),
      ),
    );
    if (!completed) return;
    if (mounted) {
      // Today's Task deliberately only claims part of the declared study
      // budget (see recommendedQueueCount's doc comment) — nudge the
      // student toward the rest of their time instead of just stopping.
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text(
            "Nice work! Still got time today — try another module from Modules 👇"),
        duration: Duration(seconds: 4),
      ));
      _loadData();
    }
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
          // Skill score bars — real assessment scores once the student has
          // taken the test, else their self-evaluation ratings scaled to a
          // percentage (see _computeProgressPercents). A deliberately
          // static snapshot, not the live mastery map — that's what
          // _buildLearningCard's overall %/pills track instead.
          _scoreBar('Vocabulary', _progressPercents['Vocabulary'] ?? 0, _brightOrange),
          _scoreBar('Grammar',    _progressPercents['Grammar'] ?? 0,    _mintGreen),
          _scoreBar('Reading',    _progressPercents['Reading'] ?? 0,    _lightblue),
          _scoreBar('Writing',    _progressPercents['Writing'] ?? 0,    _coralRed),
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
                  colors: [_starYellow, _brightOrange], // Sunny Yellow to Orange
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