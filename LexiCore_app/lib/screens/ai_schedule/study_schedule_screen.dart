import 'package:flutter/material.dart';
import '../../services/supabase_service.dart';
import '../../services/api_service.dart';

class StudyScheduleScreen extends StatefulWidget {
  const StudyScheduleScreen({super.key});

  @override
  State<StudyScheduleScreen> createState() => _StudyScheduleScreenState();
}

class _StudyScheduleScreenState extends State<StudyScheduleScreen> {
  static const Color _buttonBlue = Color(0xFF1E88E5);
  static const Color _bg = Color(0xFFF0F8FF);
  static const Color _navyText = Color(0xFF003C8F);
  static const Color _textMid = Color(0xFF003C8F);

  final _supabaseService = SupabaseService();
  final _apiService = ApiService();

  bool _isLoading = true;
  bool _isRegenerating = false;
  String _errorMessage = '';
  Map<String, dynamic>? _plan;

  // Tracks when the schedule was first created — used to compute current week
  DateTime? _scheduleCreatedAt;

  @override
  void initState() {
    super.initState();
    _loadSchedule();
  }

  // ── Current week number based on schedule creation date ───────────────
  int get _currentWeekNumber {
    if (_scheduleCreatedAt == null) return 1;
    final daysSinceStart = DateTime.now()
        .difference(_scheduleCreatedAt!)
        .inDays;
    final week = (daysSinceStart ~/ 7) + 1;
    return week.clamp(1, 4);
  }

  // ── Load: retrieve saved plan first, only generate if none exists ─────
  Future<void> _loadSchedule() async {
    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      final saved = await _supabaseService.getSavedSchedule();

      if (saved != null) {
        final createdAtStr = saved['_created_at'] as String?;
        setState(() {
          _plan = saved;
          _scheduleCreatedAt = createdAtStr != null
              ? DateTime.tryParse(createdAtStr)
              : DateTime.now();
          _isLoading = false;
        });
        return;
      }

      // No plan saved yet — generate one for first-time user
      // Keep _isLoading = true while generating so UI shows loading screen
      await _generateAndSave();
    } catch (e) {
      debugPrint('Schedule load error: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isRegenerating = false;
          _errorMessage = 'Something went wrong. Please try again.';
        });
      }
    }
  }

  // ── Generate a new plan and save it to Supabase ───────────────────────
  Future<void> _generateAndSave({String? modifier}) async {
    try {
      final profile = await _supabaseService.getStudentProfile();
      final assessment = await _supabaseService.getAssessmentResults();

      if (profile == null || assessment == null) {
        if (mounted) {
          setState(() {
            _isLoading = false;
            _isRegenerating = false;
            _errorMessage =
                'Profile data not found. Please complete the assessment first.';
          });
        }
        return;
      }

      final standard = (profile['standard'] as int?) ?? 3;
      final detectedLevel = (assessment['detected_level'] as int?) ?? standard;
      final studyTime = (profile['study_time'] as String?) ?? '30 minutes';
      final vocabScore = (assessment['vocabulary_score'] as int?) ?? 0;
      final grammarScore = (assessment['grammar_score'] as int?) ?? 0;
      final readingScore = (assessment['reading_score'] as int?) ?? 0;
      final writingScore = (assessment['writing_score'] as int?) ?? 0;

      final scores = {
        'Vocabulary': vocabScore,
        'Grammar': grammarScore,
        'Reading': readingScore,
        'Writing': writingScore,
      };
      final strength = scores.entries
          .reduce((a, b) => a.value >= b.value ? a : b)
          .key;
      final weakness = scores.entries
          .reduce((a, b) => a.value <= b.value ? a : b)
          .key;

      String adjustedStudyTime = studyTime;
      if (modifier == 'more') adjustedStudyTime = _increaseTime(studyTime);
      if (modifier == 'less') adjustedStudyTime = _decreaseTime(studyTime);
      if (modifier == 'shorten') adjustedStudyTime = _decreaseTime(studyTime);
      if (modifier == 'lengthen') adjustedStudyTime = _increaseTime(studyTime);

      final plan = await _apiService.generateSchedule(
        standard,
        adjustedStudyTime,
        strength,
        weakness,
        detectedLevel: detectedLevel,
        vocabScore: vocabScore,
        grammarScore: grammarScore,
        readingScore: readingScore,
        writingScore: writingScore,
        modifier: modifier,
      );

      if (plan != null) {
        await _supabaseService.saveStudySchedule(plan);
        final now = DateTime.now();
        setState(() {
          _plan = plan;
          _scheduleCreatedAt = now;
          _isLoading = false;
          _isRegenerating = false;
        });
      } else {
        setState(() {
          _isLoading = false;
          _isRegenerating = false;
          _errorMessage = 'Failed to generate schedule. Please try again.';
        });
      }
    } catch (e) {
      debugPrint('Schedule generate error: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isRegenerating = false;
          _errorMessage = 'Failed to generate schedule. Please try again.';
        });
      }
    }
  }

  // ── Regenerate options sheet ──────────────────────────────────────────
  void _showRegenerateOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true, // Allow sheet to take up more than half the screen
      builder: (ctx) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        // SingleChildScrollView ensures it never overflows, even on tiny screens
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            24, 
            20, 
            24, 
            MediaQuery.of(ctx).padding.bottom + 24
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: const Color(0xFF7AC9FA).withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'Adjust your plan',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF003C8F),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Choose how you\'d like to update your schedule',
                style: TextStyle(
                  fontSize: 13,
                  color: const Color(0xFF003C8F).withValues(alpha: 0.6),
                ),
              ),
              const SizedBox(height: 30),
              _regenerateOption(
                icon: Icons.flash_on_rounded,
                color: const Color(0xFF1E88E5),
                title: 'More practice',
                subtitle: 'Increase intensity — I want to improve faster',
                onTap: () {
                  Navigator.pop(context);
                  _triggerRegenerate('more');
                },
              ),
              _regenerateOption(
                icon: Icons.self_improvement_rounded,
                color: const Color(0xFF4DB6AC),
                title: 'Less practice',
                subtitle: 'Current plan feels too heavy',
                onTap: () {
                  Navigator.pop(context);
                  _triggerRegenerate('less');
                },
              ),
              _regenerateOption(
                icon: Icons.compress_rounded,
                color: const Color(0xFF64B5F6),
                title: 'Shorten sessions',
                subtitle: 'Keep same topics but reduce daily time',
                onTap: () {
                  Navigator.pop(context);
                  _triggerRegenerate('shorten');
                },
              ),
              _regenerateOption(
                icon: Icons.expand_rounded,
                color: const Color(0xFF1E88E5),
                title: 'Lengthen sessions',
                subtitle: 'I have more time — make sessions longer',
                onTap: () {
                  Navigator.pop(context);
                  _triggerRegenerate('lengthen');
                },
              ),
              _regenerateOption(
                icon: Icons.refresh_rounded,
                color: Colors.grey,
                title: 'Fresh start',
                subtitle: 'Generate a completely new plan',
                onTap: () {
                  Navigator.pop(context);
                  _triggerRegenerate(null);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _triggerRegenerate(String? modifier) {
    setState(() {
      _isRegenerating = true;
      _errorMessage = '';
    });
    _generateAndSave(modifier: modifier);
  }

  String _increaseTime(String current) {
    const order = ['15 minutes', '30 minutes', '45 minutes', '1 hour'];
    final i = order.indexOf(current);
    return i < order.length - 1 ? order[i + 1] : order.last;
  }

  String _decreaseTime(String current) {
    const order = ['15 minutes', '30 minutes', '45 minutes', '1 hour'];
    final i = order.indexOf(current);
    return i > 0 ? order[i - 1] : order.first;
  }

  // ── Build ─────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        automaticallyImplyLeading: false,
        title: const Text(
          'Study Schedule',
          style: TextStyle(
            fontWeight: FontWeight.w900,
            color: Color(0xFF003C8F),
            fontSize: 22,
          ),
        ),
        actions: [
          if (!_isLoading)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: GestureDetector(
                onTap: _isRegenerating ? null : _showRegenerateOptions,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: _buttonBlue.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: _buttonBlue.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _isRegenerating
                            ? Icons.hourglass_empty_rounded
                            : Icons.tune_rounded,
                        color: _buttonBlue,
                        size: 16,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        _isRegenerating ? 'Updating...' : 'Adjust',
                        style: const TextStyle(
                          color: _buttonBlue,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
      body: _isLoading
          ? _buildLoadingView()
          : _errorMessage.isNotEmpty
          ? _buildErrorView()
          : _isRegenerating
          ? _buildRegeneratingView()
          : _buildPlanView(),
    );
  }

  Widget _buildLoadingView() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(color: _buttonBlue),
          SizedBox(height: 16),
          Text(
            'Building your personalised plan...',
            style: TextStyle(color: _textMid),
          ),
        ],
      ),
    );
  }

  Widget _buildRegeneratingView() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(color: _buttonBlue),
          SizedBox(height: 16),
          Text(
            'Adjusting your schedule...',
            style: TextStyle(color: _textMid, fontSize: 15),
          ),
          SizedBox(height: 6),
          Text(
            'This takes about 10 seconds',
            style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.calendar_today_outlined,
              size: 64,
              color: _buttonBlue,
            ),
            const SizedBox(height: 16),
            Text(
              _errorMessage,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 15),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _loadSchedule,
              style: ElevatedButton.styleFrom(
                backgroundColor: _buttonBlue,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
              child: const Text(
                'Try again',
                style: TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlanView() {
    final weeks = (_plan?['weeks'] as List<dynamic>?) ?? [];
    final summary = (_plan?['summary'] as String?) ?? '';

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 100),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Current week indicator
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: _buttonBlue.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _buttonBlue.withValues(alpha: 0.2)),
            ),
            child: Row(
              children: [
                const Icon(Icons.today_rounded, color: _buttonBlue, size: 16),
                const SizedBox(width: 8),
                Text(
                  'You are currently on Week $_currentWeekNumber',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: _buttonBlue,
                  ),
                ),
              ],
            ),
          ),

          // Summary banner
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [
                  Color(0xFF7AC9FA),
                  Color(0xFF1E88E5),
                  Color(0xFFDFF1FF),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: _buttonBlue.withValues(alpha: 0.25),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(
                      Icons.auto_awesome_rounded,
                      color: Colors.white,
                      size: 16,
                    ),
                    SizedBox(width: 6),
                    Text(
                      'Your 4-week personalised plan',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  summary,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Week cards — pass weekNum to each
          ...weeks.map((week) => _buildWeekCard(week)),
        ],
      ),
    );
  }

  Widget _buildWeekCard(dynamic week) {
    final weekNum = week['week'] as int? ?? 0;
    final focus = week['focus'] as String? ?? '';
    final tasks = (week['daily_tasks'] as List<dynamic>?) ?? [];

    final isCurrentWeek = weekNum == _currentWeekNumber;

    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: isCurrentWeek
            ? Border.all(color: _buttonBlue.withValues(alpha: 0.4), width: 1.5)
            : null,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Week header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: isCurrentWeek
                  ? _buttonBlue.withValues(alpha: 0.12)
                  : _buttonBlue.withValues(alpha: 0.05),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(20),
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: isCurrentWeek ? _buttonBlue : Colors.grey[400],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'Week $weekNum',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    focus,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: _navyText,
                    ),
                  ),
                ),
                if (isCurrentWeek)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: _buttonBlue,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Text(
                      'Current',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
              ],
            ),
          ),

          // Daily tasks — pass weekNum so highlight logic is week-aware
          ...tasks.map((task) => _buildTaskRow(task, weekNum)),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _buildTaskRow(dynamic task, int weekNum) {
    final skill = task['skill'] as String? ?? '';
    final day = task['day'] as String? ?? '';
    final taskText = task['task'] as String? ?? '';
    final duration = task['duration'] as String? ?? '';
    final color = _skillColor(skill);

    final days = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ];
    final todayName = days[DateTime.now().weekday - 1];
    final isCurrentWeek = weekNum == _currentWeekNumber;

    // Only highlight if BOTH week matches AND day name matches
    final isToday =
        isCurrentWeek && day.toLowerCase() == todayName.toLowerCase();

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: isToday
            ? _buttonBlue.withValues(alpha: 0.05)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(18),
        border: isToday
            ? Border.all(color: _buttonBlue.withValues(alpha: 0.2))
            : null,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Day column
          SizedBox(
            width: 68,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  day,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: isToday ? _buttonBlue : _textMid,
                  ),
                ),
                if (isToday)
                  Container(
                    margin: const EdgeInsets.only(top: 2),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: _buttonBlue,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text(
                      'Today',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
              ],
            ),
          ),

          // Skill badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              skill,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ),
          const SizedBox(width: 10),

          // Task + duration
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  taskText,
                  style: const TextStyle(
                    fontSize: 13,
                    color: _navyText,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 2),
                Text(duration, style: TextStyle(fontSize: 11, color: _textMid)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _regenerateOption({
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: 0.15)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: _navyText,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: TextStyle(fontSize: 12, color: _textMid),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.arrow_forward_ios_rounded,
              size: 14,
              color: Colors.grey[400],
            ),
          ],
        ),
      ),
    );
  }

  Color _skillColor(String skill) {
    switch (skill) {
      case 'Vocabulary':
        return const Color(0xFF1E88E5);
      case 'Grammar':
        return const Color(0xFF4DB6AC);
      case 'Reading':
        return const Color(0xFF64B5F6);
      case 'Writing':
        return const Color(0xFFE57373);
      default:
        return _buttonBlue;
    }
  }
}
