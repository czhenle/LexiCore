import 'package:flutter/material.dart';
import '../../services/supabase_service.dart';
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

  int _selectedIndex = 0;

  String _username      = '';
  int    _detectedLevel = 3;
  int    _vocabScore    = 0;
  int    _grammarScore  = 0;
  int    _readingScore  = 0;
  int    _writingScore  = 0;
  bool   _isLoading     = true;

  // Today's task from schedule (if saved)
  Map<String, dynamic>? _todayTask;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final profile    = await _supabaseService.getStudentProfile();
      final assessment = await _supabaseService.getAssessmentResults();
      final today      = await _supabaseService.getTodayTask();

      if (mounted) {
        setState(() {
          _username      = (profile?['username']         as String?) ?? 'Student';
          _detectedLevel = (assessment?['detected_level'] as int?)   ?? 3;
          _vocabScore    = (assessment?['vocabulary_score'] as int?)  ?? 0;
          _grammarScore  = (assessment?['grammar_score']   as int?)   ?? 0;
          _readingScore  = (assessment?['reading_score']   as int?)   ?? 0;
          _writingScore  = (assessment?['writing_score']   as int?)   ?? 0;
          _todayTask     = today;
          _isLoading     = false;
        });
      }
    } catch (e) {
      debugPrint('Home load error: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String get _weaknessSkill {
    final scores = {
      'Vocabulary': _vocabScore,
      'Grammar':    _grammarScore,
      'Reading':    _readingScore,
      'Writing':    _writingScore,
    };
    return scores.entries.reduce((a, b) => a.value <= b.value ? a : b).key;
  }

  String get _strengthSkill {
    final scores = {
      'Vocabulary': _vocabScore,
      'Grammar':    _grammarScore,
      'Reading':    _readingScore,
      'Writing':    _writingScore,
    };
    return scores.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
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
              title: const Text(
                'LexiCore',
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  color: _buttonBlue,
                  fontSize: 26,
                  letterSpacing: 0.5,
                ),
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

          // ── Card 1: Today's Task ──────────────────────────────────────
          _sectionLabel('Today\'s Task'),
          const SizedBox(height: 12),
          _buildTodayTaskCard(),
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

  // ── Card 1: Today's Task ────────────────────────────────────────────────
  Widget _buildTodayTaskCard() {
    final hasTask = _todayTask != null;
    final skill    = hasTask
        ? (_todayTask!['skill'] as String? ?? _weaknessSkill)
        : _weaknessSkill;
    final task     = hasTask
        ? (_todayTask!['task'] as String? ??
            'Practise your $_weaknessSkill skills')
        : 'Practise your $_weaknessSkill skills';
    final duration = hasTask
        ? (_todayTask!['duration'] as String? ?? '15 mins')
        : '15 mins';

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        // Vibrant Purple to Pink gradient for excitement
        gradient: const LinearGradient(
          colors: [Color(0xFF7AC9FA), Color(0xFF1E88E5), Color(0xFFDFF1FF)], 
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: _buttonBlue.withValues(alpha: 0.3),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.star_rounded,
                    color: Colors.white, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Today\'s focus',
                        style: TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                            fontWeight: FontWeight.w700)),
                    Text(skill,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w900)),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.timer_rounded,
                        color: Colors.white, size: 14),
                    const SizedBox(width: 6),
                    Text(duration,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w800)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            task,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w500,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(
              onPressed: () => _startMission(skill),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: _buttonBlue,
                elevation: 0,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20)),
              ),
              child: const Text(
                'Start Mission',
                style: TextStyle(
                    fontWeight: FontWeight.w900, fontSize: 16),
              ),
            ),
          ),
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
          // Skill score bars with Candy Colors!
          _scoreBar('Vocabulary', _vocabScore,  _brightOrange),
          _scoreBar('Grammar',    _grammarScore, _mintGreen),
          _scoreBar('Reading',    _readingScore, _lightblue),
          _scoreBar('Writing',    _writingScore, _coralRed),
          const SizedBox(height: 16),

          // Divider
          Container(height: 2, color: const Color(0xFFF0F8FF)),
          const SizedBox(height: 16),

          // Strength / Weakness row
          Row(
            children: [
              Expanded(child: _statBadge('Strength',   _strengthSkill,
                  Icons.emoji_events_rounded, Colors.green)),
              const SizedBox(width: 12),
              Expanded(child: _statBadge('Needs focus', _weaknessSkill,
                  Icons.fitness_center_rounded, _coralRed)),
            ],
          ),
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
                  const SizedBox(height: 6),
                  Text(
                    'Fun stories tailored to Level $_detectedLevel',
                    style: TextStyle(
                        fontSize: 13,
                        color: _navyText.withValues(alpha: 0.6),
                        fontWeight: FontWeight.w600,
                        height: 1.3),
                  ),
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

  Widget _statBadge(
      String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        // Added a slightly stronger colored border so it pops against the white card
        border: Border.all(color: color.withValues(alpha: 0.3), width: 2), 
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: color), // Colored icon
              const SizedBox(width: 6),
              Text(label,
                  style: TextStyle(
                      fontSize: 12,
                      color: color, // Colored text
                      fontWeight: FontWeight.w800)),
            ],
          ),
          const SizedBox(height: 6),
          Text(value,
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                  color: color)), // Colored value text
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