// ignore_for_file: unnecessary_underscores

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../services/supabase_service.dart';
import '../../services/mastery_service.dart';
import '../../services/api_service.dart';
import '../../widgets/generating_status.dart';
import '../../theme/app_colors.dart';
import '../home/home_screen.dart';

enum AssessmentState {
  loading,
  error,
  transition,
  readingPassage,
  quiz,
  saving,
  results,
}

/// Standard-specific composition (per the syllabus breakdown):
///   Standard 1-2: 15 Vocabulary + 15 Grammar + 1 Writing Sample
///   Standard 3-4: + 5 Reading + 1 Writing Sample
///   Standard 5-6: + 7 Reading (2 KBAT) + 1 Writing Sample
/// Reading's exact count (5 vs 7 incl. KBAT) is already handled server-side
/// by the `reading` edge function based on standard — this screen just
/// decides WHETHER to ask for Reading at all.
///
/// The Writing Sample (formerly "Guided Comprehension") used to be an
/// open question grounded in the Reading passage — but that only exists for
/// Standard >=3, and tying a *writing* sample to a *reading* passage was a
/// mismatch anyway (it tested whether they'd understood the passage, not
/// whether they could write). It's now a standalone self-introduction
/// prompt, unrelated to Reading, scaled by standard via a min-word target —
/// available to every standard.
class InitialAssessmentScreen extends StatefulWidget {
  final int standard;

  const InitialAssessmentScreen({super.key, required this.standard});

  @override
  State<InitialAssessmentScreen> createState() =>
      _InitialAssessmentScreenState();
}

class _InitialAssessmentScreenState extends State<InitialAssessmentScreen> {
  final _supabaseService = SupabaseService();
  final _apiService = ApiService();

  static const Color _skyBlueLight = AppColors.skyLight;
  static const Color _skyBlueDark = AppColors.skyDark;
  static const Color _navyText = AppColors.navy;
  static const Color _buttonBlue = AppColors.blue;
  static const Color _starYellow = AppColors.starYellow;
  static const Color _grey = AppColors.darkGrey;

  AssessmentState _currentState = AssessmentState.loading;
  String _errorMessage = '';

  int _currentIndex = 0;
  String? _selectedAnswer;

  List<dynamic> _questions = [];
  late int _studentStandard;
  final Map<int, String> _answers = {};
  Map<String, int> _finalScores = {};

  // Reading article — shown on passage screen before reading questions
  String _articleTitle = '';
  String _articleBody = '';

  // Writing Sample (Standard >=3 only, same as Reading) — a standalone
  // self-introduction prompt (name/age/hobby/why they want to learn
  // English), judged for real via the `grade` edge function. Not grounded
  // in the Reading passage — see the class doc comment for why. A short
  // word-count target is a SUGGESTION, not enforced — this is a quick
  // diagnostic sample, not a full composition, so Submit is never blocked
  // on it and falling short is just noted as feedback, not a hard fail.
  final _guidedAnswerCtrl = TextEditingController();
  bool _gradingGuided = false;
  bool? _guidedCorrect;
  static const _writingSampleWords = {3: 20, 4: 30, 5: 40, 6: 50};

  bool get _wantsReading => _studentStandard >= 3;

  @override
  void initState() {
    super.initState();
    _studentStandard = widget.standard;
    _loadAssessment();
  }

  @override
  void dispose() {
    _guidedAnswerCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadAssessment() async {
    setState(() => _currentState = AssessmentState.loading);

    // Vocabulary/Grammar now go through `generate` at a fixed diagnostic
    // rung (2/3) — there's no mastery yet to target adaptively, so every
    // item is requested at a flat difficulty rather than a ladder. Reading
    // stays on the legacy passage+MCQ generator for now (Part 4 of the
    // Pipeline-1 migration gives Reading its own passage-per-session
    // mechanism; pre-assessment will move onto it once that lands).
    //
    // Each group of 5 is ONE batch call (count:5), not 5 separate parallel
    // calls — those used to send byte-for-byte identical prompts (same
    // skill/sub_skill/rung/format/standard, empty recent_errors) with
    // nothing to tell them apart, so the model had no reason to make them
    // different and came back with the same question every time. The batch
    // prompt explicitly asks for distinct items, and there's no per-item
    // adaptivity to lose here anyway — nothing in a diagnostic assessment
    // depends on how an earlier item in it was answered.
    final vocabFutures = [
      for (final format in const ['vocab_meaning_mcq', 'vocab_context_mcq', 'vocab_synonyms_mcq'])
        _fetchAssessmentBatch(
          skill: 'Vocabulary',
          subSkill: 'vocab.assessment_$format',
          subSkillName: 'Vocabulary',
          format: format,
          count: 5,
        ),
    ];
    final grammarTopics = ['Nouns and Articles', 'Verb Tenses', 'Sentence Structure'];
    final grammarFutures = [
      for (var t = 0; t < grammarTopics.length; t++)
        _fetchAssessmentBatch(
          skill: 'Grammar',
          subSkill: 'grammar.assessment_$t',
          subSkillName: grammarTopics[t],
          format: 'gap_fill',
          count: 5,
        ),
    ];
    final readingFuture =
        _wantsReading ? _apiService.generateReadingModule(_studentStandard, 'A Short Story') : null;

    final vocabResults = await Future.wait(vocabFutures);
    final grammarResults = await Future.wait(grammarFutures);
    final readingData = readingFuture != null ? await readingFuture : null;

    final List<dynamic> all = [];

    for (final group in vocabResults) {
      for (final item in group) {
        item['skill'] = 'Vocabulary';
        all.add(item);
      }
    }
    for (final group in grammarResults) {
      for (final item in group) {
        item['skill'] = 'Grammar';
        all.add(item);
      }
    }

    // Reading (Standard >= 3) — 5, or 5+2 KBAT for Standard 5-6.
    if (_wantsReading && readingData is Map && readingData?['questions'] != null) {
      final reading = Map<String, dynamic>.from(readingData as Map);
      final articleBody = reading['body'] as String? ?? '';
      final articleTitle = reading['title'] as String? ?? 'Reading Passage';
      _articleTitle = articleTitle;
      _articleBody = articleBody;
      for (var q in (reading['questions'] as List)) {
        q['skill'] = 'Reading';
        q['context_text'] = articleBody;
        all.add(q);
      }
    }

    if (all.isEmpty) {
      setState(() {
        _currentState = AssessmentState.error;
        _errorMessage =
            'Failed to generate assessment. Please check your internet connection.';
      });
      return;
    }

    // Writing Sample (Standard >= 3, same gate as Reading) — a standalone
    // self-introduction prompt, NOT grounded in the Reading passage (see
    // class doc comment). Built locally, no generate call needed.
    if (_wantsReading) {
      all.add(_buildWritingSampleItem());
    }

    all.sort((a, b) {
      const order = {'Vocabulary': 1, 'Grammar': 2, 'Reading': 3};
      return (order[a['skill']] ?? 99).compareTo(order[b['skill']] ?? 99);
    });

    setState(() {
      _questions = all;
      _currentState = AssessmentState.transition;
    });
  }

  /// A standalone self-introduction writing prompt — name, age, a hobby,
  /// and why they want to learn English. Built locally (no `generate` call)
  /// since the wording doesn't need to vary, only the suggested word count
  /// does, by standard. Graded for real via `grade`, same as any other open
  /// item — see the min_words/word-count field comment for why it's a
  /// suggestion, not an enforced minimum.
  Map<String, dynamic> _buildWritingSampleItem() {
    final words = _writingSampleWords[_studentStandard] ?? 30;
    return {
      'question': 'Write a short introduction about yourself. Include your '
          'name, age, a hobby you enjoy, and why you want to learn English. '
          "(You can write about $words words — it's okay if it's a little "
          'more or less!)',
      'answer': 'My name is Aisha. I am 9 years old. I like drawing '
          'pictures. I want to learn English so I can read more '
          'storybooks and talk to more people.',
      'explanation': 'A good introduction names all four things: your '
          'name, your age, a hobby, and why you want to learn English.',
      'min_words': words,
      'rung': 4,
      'skill': 'Writing',
      'is_guided_comprehension': true,
    };
  }

  /// A batch of Vocabulary/Grammar assessment items via `generate`'s
  /// count>1 path — all `count` items come from ONE call, with the model
  /// explicitly told to make them genuinely distinct, instead of `count`
  /// separate parallel calls sharing an identical prompt (which is what
  /// this used to be, and why every item in a group came back the same).
  /// Fixed diagnostic rung (2 for Standard 1-2, 3 for Standard 3-6) since
  /// there's no mastery yet to target adaptively.
  Future<List<Map<String, dynamic>>> _fetchAssessmentBatch({
    required String skill,
    required String subSkill,
    required String subSkillName,
    required String format,
    required int count,
  }) async {
    final rung = _studentStandard <= 2 ? 2 : 3;
    try {
      final res = await Supabase.instance.client.functions.invoke('generate', body: {
        'skill': skill,
        'sub_skill': subSkill,
        'sub_skill_name': subSkillName,
        'rung': rung,
        'format': format,
        'standard': _studentStandard,
        'target_difficulty': 1000.0 + (_studentStandard - 3) * 80.0,
        'recent_errors': <String>[],
        'count': count,
      });
      final data = res.data;
      final raw = data is Map ? data['items'] as List? : null;
      if (raw == null) return [];
      return raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } catch (e) {
      debugPrint('Assessment batch fetch failed ($skill/$subSkill): $e');
      return [];
    }
  }

  void _selectAnswer(String option) => setState(() => _selectedAnswer = option);

  void _handleBackPress() {
    if (_currentState == AssessmentState.transition) {
      Navigator.pop(context);
    } else if (_currentState == AssessmentState.readingPassage) {
      // Go back to transition screen
      setState(() => _currentState = AssessmentState.transition);
    } else if (_currentState == AssessmentState.quiz) {
      final currentType = _questions[_currentIndex]['skill'] as String? ?? '';
      // If on first reading question, go back to passage screen
      if (currentType == 'Reading' &&
          (_currentIndex == 0 ||
              _questions[_currentIndex - 1]['skill'] != 'Reading')) {
        setState(() => _currentState = AssessmentState.readingPassage);
      } else if (_currentIndex > 0) {
        setState(() {
          _currentIndex--;
          _selectedAnswer = _answers[_currentIndex];
        });
      } else {
        setState(() => _currentState = AssessmentState.transition);
      }
    }
  }

  void _nextQuestion() {
    if (_selectedAnswer != null) {
      _answers[_currentIndex] = _selectedAnswer!;
    }

    if (_currentIndex < _questions.length - 1) {
      final nextType = _questions[_currentIndex + 1]['skill'] as String? ?? '';
      final currentType = _questions[_currentIndex]['skill'] as String? ?? '';

      // Intercept: if moving from non-Reading → Reading, show passage first
      if (nextType == 'Reading' && currentType != 'Reading') {
        setState(() {
          _currentIndex++;
          _selectedAnswer = null;
          _currentState = AssessmentState.readingPassage;
        });
        return;
      }

      setState(() {
        _currentIndex++;
        _selectedAnswer = _answers[_currentIndex];
      });
    } else {
      _finishAssessment();
    }
  }

  /// The guided-comprehension question has no A/B/C/D — it's judged by the
  /// `grade` edge function instead of exact match.
  Future<void> _submitGuidedComprehension() async {
    final typed = _guidedAnswerCtrl.text.trim();
    if (typed.isEmpty || _gradingGuided) return;
    setState(() => _gradingGuided = true);

    final q = _questions[_currentIndex];
    try {
      final res = await Supabase.instance.client.functions.invoke('grade', body: {
        'question': q['question'],
        'student_response': typed,
        'model_answer': q['answer'],
        'explanation': q['explanation'],
        'sub_skill_name': 'Writing Sample',
        'rung': q['rung'],
        'standard': _studentStandard,
        // A suggestion, not a requirement — grade/index.ts already treats
        // a shortfall as feedback ("mistakes"), not an automatic fail.
        'min_words': q['min_words'],
      });
      final data = res.data;
      _guidedCorrect = (data is Map && data['correct'] == true);
    } catch (e) {
      debugPrint('Writing sample grading failed: $e');
      _guidedCorrect = false; // conservative default — never dead-ends
    }
    _answers[_currentIndex] = typed;
    if (!mounted) return;
    setState(() => _gradingGuided = false);
    _nextQuestion();
  }

  Future<void> _finishAssessment() async {
    if (_selectedAnswer != null) {
      _answers[_currentIndex] = _selectedAnswer!;
    }
    setState(() => _currentState = AssessmentState.saving);

    final Map<String, List<bool>> results = {
      'Vocabulary': [],
      'Grammar': [],
      if (_wantsReading) 'Reading': [],
    };

    for (int i = 0; i < _questions.length; i++) {
      final q = _questions[i];
      // Guided Comprehension is a different sub-skill from the Reading MCQs
      // — it gets its own pass/fail result card (see _guidedCorrect below)
      // instead of quietly moving Reading's percentage up or down.
      if (q['is_guided_comprehension'] == true) continue;
      final type = (q['skill'] as String?) ?? 'Grammar';
      if (!results.containsKey(type)) continue;
      final correct = q['correct_answer'] as String?;
      final given = _answers[i];
      results[type]!.add(given != null && given == correct);
    }

    int scorePercent(List<bool> answers) {
      if (answers.isEmpty) return 0;
      return ((answers.where((a) => a).length / answers.length) * 100).round();
    }

    _finalScores = {
      'Vocabulary': scorePercent(results['Vocabulary']!),
      'Grammar': scorePercent(results['Grammar']!),
      if (_wantsReading) 'Reading': scorePercent(results['Reading']!),
      // The Writing Sample's pass/fail is the only Writing signal the
      // assessment has — coarse (one item), same caveat as every other
      // score here, but a real number beats the neutral-50 default
      // seedMasteryFromAssessment() falls back to when a skill is missing
      // entirely, which is what silently happened before this. Excluded
      // from the results screen's score cards (see _buildResultScreen) —
      // still shown there as its own pass/fail card instead, since
      // dressing one item up as "100%"/"0%" would overstate it.
      if (_wantsReading) 'Writing': (_guidedCorrect == true) ? 100 : 40,
    };

    // Each step gets its own try/catch — these used to share one, so a
    // failure in the first (saveAssessmentResults) silently skipped the
    // other two entirely, leaving skill_mastery empty and the progress
    // bar/schedule/Today's Task with nothing to show, with no error visible
    // anywhere (the results screen still reads its own local _finalScores,
    // so it looked like everything succeeded either way). Independent now,
    // so one failing doesn't take the others down with it — and
    // MasteryService.ensureMasterySeeded() (called from HomeScreen) is a
    // second safety net if seeding still doesn't make it through here.
    try {
      await _supabaseService.saveAssessmentResults(
        vocabularyScore: _finalScores['Vocabulary']!,
        grammarScore: _finalScores['Grammar']!,
        readingScore: _finalScores['Reading'], // null for Standard 1-2
        writingScore: _finalScores['Writing'], // null for Standard 1-2
      );
    } catch (e) {
      debugPrint('saveAssessmentResults failed: $e');
    }
    try {
      // Seed the per-sub-skill mastery map that drives adaptive practice.
      // Skills missing from _finalScores (Reading/Writing for Standard 1-2)
      // fall back to seedMasteryFromAssessment's own neutral 50.
      await _supabaseService.seedMasteryFromAssessment(
        skillScores: _finalScores,
        standard: _studentStandard,
      );
    } catch (e) {
      debugPrint('seedMasteryFromAssessment failed: $e');
    }
    try {
      // Build the study plan immediately — Home shouldn't need the student
      // to finish separate module quizzes first to get one.
      await MasteryService().generateStudyPlan();
    } catch (e) {
      debugPrint('generateStudyPlan failed: $e');
    }

    if (mounted) setState(() => _currentState = AssessmentState.results);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [_skyBlueDark, _skyBlueLight],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(child: _buildCurrentState()),
      ),
    );
  }

  Widget _buildCurrentState() {
    switch (_currentState) {
      case AssessmentState.loading:
        return _buildLoadingScreen();
      case AssessmentState.error:
        return _buildErrorScreen();
      case AssessmentState.transition:
        return _buildTransitionScreen();
      case AssessmentState.readingPassage:
        return _buildReadingPassageScreen();
      case AssessmentState.quiz:
        return _buildQuestionScreen();
      case AssessmentState.saving:
        return _buildSavingScreen();
      case AssessmentState.results:
        return _buildResultScreen();
    }
  }

  // ── 1. Loading ──────────────────────────────────────────────────────────
  Widget _buildLoadingScreen() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const GeneratingStatus(
            color: Colors.white,
            label: 'Preparing your assessment…',
            // The vocab_context_mcq batch (one of several run in parallel via
            // Future.wait) measured 42-115s on its own — since overall wait is
            // whichever parallel call finishes LAST, that one call alone can
            // make the whole assessment take up to ~2 minutes, not 30-60s.
            estimate: 'about 1-2 minutes',
          ),
          const SizedBox(height: 8),
          Text(
            'Generating questions for Standard $_studentStandard',
            style: TextStyle(
              fontSize: 14,
              color: _navyText.withValues(alpha: 0.8),
            ),
          ),
        ],
      ),
    );
  }

  // ── 2. Error ────────────────────────────────────────────────────────────
  Widget _buildErrorScreen() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.wifi_off_rounded, size: 64, color: Colors.white),
            const SizedBox(height: 16),
            Text(
              _errorMessage,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 16,
                color: _navyText,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _loadAssessment,
              style: ElevatedButton.styleFrom(
                backgroundColor: _buttonBlue,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
              child: const Text(
                'Try again',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── 3. Transition ───────────────────────────────────────────────────────
  Widget _buildTransitionScreen() {
    final vocabCount = _questions.where((q) => q['skill'] == 'Vocabulary').length;
    final grammarCount = _questions.where((q) => q['skill'] == 'Grammar').length;
    // Reading and Guided Comprehension are broken out separately — the
    // guided item is a single open-response question, not another reading
    // MCQ, and lumping it silently into "Reading" hid that from the intro.
    final readingCount = _questions
        .where((q) => q['skill'] == 'Reading' && q['is_guided_comprehension'] != true)
        .length;
    final guidedCount =
        _questions.where((q) => q['is_guided_comprehension'] == true).length;
    // Guided Comprehension isn't a 4th skill for the "across N skills" line
    // — it's a Reading sub-type — so it's folded back in here, even though
    // it gets its own row in the breakdown below.
    final skillCount = [vocabCount, grammarCount, readingCount + guidedCount]
        .where((c) => c > 0)
        .length;

    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: _handleBackPress,
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.3),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.arrow_back_ios_new_rounded,
                color: _navyText,
                size: 20,
              ),
            ),
          ),
          const SizedBox(height: 40),
          const Center(
            child: Icon(Icons.school_rounded, size: 100, color: Colors.white),
          ),
          const SizedBox(height: 40),
          const Text(
            'Now let\'s test your level!',
            style: TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.w900,
              color: _navyText,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Please complete a short ${_questions.length}-question assessment across $skillCount skills:',
            style: TextStyle(
              fontSize: 16,
              color: _navyText.withValues(alpha: 0.8),
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 24),
          _buildCountRow(Icons.abc_rounded, 'Vocabulary', vocabCount),
          _buildCountRow(Icons.rule_rounded, 'Grammar', grammarCount),
          _buildCountRow(Icons.menu_book_rounded, 'Reading', readingCount),
          _buildCountRow(
              Icons.edit_note_rounded, 'Writing Sample', guidedCount),
          const Spacer(),
          SizedBox(
            width: double.infinity,
            height: 60,
            child: ElevatedButton(
              onPressed: () {
                setState(() {
                  _currentIndex = 0;
                  _selectedAnswer = null;
                  _currentState = AssessmentState.quiz;
                });
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: _buttonBlue,
                elevation: 5,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(30),
                ),
              ),
              child: const Text(
                'Start Assessment',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildCountRow(IconData icon, String title, int count) {
    if (count == 0) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Icon(icon, color: _grey, size: 24),
          const SizedBox(width: 12),
          Text(
            title,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: _navyText,
            ),
          ),
          const Spacer(),
          Text(
            '$count questions',
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: Colors.black54,
            ),
          ),
        ],
      ),
    );
  }

  // ── 3b. Reading Passage Screen ──────────────────────────────────────────
  Widget _buildReadingPassageScreen() {
    final wordCount = _articleBody.split(' ').length;
    final readingMin = (wordCount / 200).ceil();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Top bar
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          child: Row(
            children: [
              GestureDetector(
                onTap: _handleBackPress,
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.3),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.arrow_back_ios_new_rounded,
                    color: _navyText,
                    size: 18,
                  ),
                ),
              ),
              const SizedBox(width: 12),
            ],
          ),
        ),

        // Article card
        Expanded(
          child: Container(
            margin: const EdgeInsets.only(top: 10),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(40),
                topRight: Radius.circular(40),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Article header
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Meta row
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: _buttonBlue.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Text(
                              'Reading',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: _buttonBlue,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Icon(
                            Icons.timer_outlined,
                            size: 13,
                            color: _navyText.withValues(alpha: 0.5),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '~$readingMin min read',
                            style: TextStyle(
                              fontSize: 12,
                              color: _navyText.withValues(alpha: 0.5),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            '$wordCount words',
                            style: TextStyle(
                              fontSize: 12,
                              color: _navyText.withValues(alpha: 0.5),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      // Title
                      Text(
                        _articleTitle,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                          color: _navyText,
                          height: 1.3,
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Gradient accent line
                      Container(
                        height: 3,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              _buttonBlue,
                              _buttonBlue.withValues(alpha: 0.2),
                            ],
                          ),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(height: 4),
                    ],
                  ),
                ),

                // Scrollable article body
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
                    child: Text(
                      _articleBody,
                      style: const TextStyle(
                        fontSize: 16,
                        color: _navyText,
                        height: 1.9,
                        letterSpacing: 0.1,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),

        // I've finished reading button
        Container(
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 28),
          child: SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton(
              onPressed: () =>
                  setState(() => _currentState = AssessmentState.quiz),
              style: ElevatedButton.styleFrom(
                backgroundColor: _buttonBlue,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(30),
                ),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    "I've finished reading",
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  SizedBox(width: 8),
                  Icon(
                    Icons.arrow_forward_rounded,
                    color: Colors.white,
                    size: 18,
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ── 4. Question screen ──────────────────────────────────────────────────
  Widget _buildQuestionScreen() {
    final question = _questions[_currentIndex];
    final isGuidedComprehension = question['is_guided_comprehension'] == true;
    final options = question['options'] as Map<String, dynamic>? ?? {};
    // The vocabulary function returns base64 (`image_b64`), never a URL —
    // gpt-image models don't support response_format:"url".
    final imageB64 = question['image_b64'] as String?;
    final questionType = (question['skill'] as String?) ?? 'Vocabulary';

    final questionText = (question['question'] as String?)?.isNotEmpty == true
        ? question['question'] as String
        : (question['prompt'] as String?) ?? 'Choose the correct answer:';

    final isLast = _currentIndex == _questions.length - 1;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Top bar
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              GestureDetector(
                onTap: _handleBackPress,
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.3),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.arrow_back_ios_new_rounded,
                    color: _navyText,
                    size: 18,
                  ),
                ),
              ),
              Column(
                children: [
                  const SizedBox(height: 4),
                  Text(
                    'Q ${_currentIndex + 1} / ${_questions.length}',
                    style: TextStyle(
                      fontSize: 11,
                      color: _navyText.withValues(alpha: 0.7),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),

        // Progress bar
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: LinearProgressIndicator(
              value: (_currentIndex + 1) / _questions.length,
              backgroundColor: Colors.white.withValues(alpha: 0.3),
              valueColor: const AlwaysStoppedAnimation(_starYellow),
              minHeight: 8,
            ),
          ),
        ),
        const SizedBox(height: 20),

        // Question card
        Expanded(
          child: Container(
            margin: const EdgeInsets.only(top: 10),
            padding: const EdgeInsets.all(24),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(40),
                topRight: Radius.circular(40),
              ),
            ),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Skill badge
                  Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: _buttonBlue.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        isGuidedComprehension
                            ? 'WRITING SAMPLE'
                            : questionType.toUpperCase(),
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w900,
                          color: _buttonBlue,
                          letterSpacing: 1.5,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // ── Vocabulary: image ─────────────────────────────────
                  if (imageB64 != null) ...[
                    ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: Image.memory(
                        base64Decode(imageB64),
                        height: 160,
                        fit: BoxFit.contain,
                        errorBuilder: (_, _, _) => const SizedBox.shrink(),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // ── Vocabulary: the fill-in-the-blank sentence itself
                  // (vocab_context_mcq) — the "question" field only ever
                  // holds the generic instruction ("Choose the best word to
                  // complete the sentence."), the sentence with its blank is
                  // a separate context_text field the model returns. Guarded
                  // to Vocabulary only — Reading questions ALSO carry
                  // context_text, but theirs is the whole passage, not a
                  // short sentence, and belongs on the earlier reading-
                  // passage screen, not repeated inline on every question.
                  if (questionType == 'Vocabulary' &&
                      (question['context_text'] as String?) != null) ...[
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: _buttonBlue.withValues(alpha: 0.07),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                            color: _buttonBlue.withValues(alpha: 0.2)),
                      ),
                      child: Text(
                        question['context_text'] as String,
                        style: const TextStyle(
                          fontSize: 16,
                          color: _navyText,
                          fontStyle: FontStyle.italic,
                          height: 1.5,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // Question text
                  Text(
                    questionText,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: _navyText,
                      height: 1.4,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),

                  if (isGuidedComprehension) ...[
                    // Open-response answer box — judged by the `grade`
                    // Edge Function, not exact match.
                    TextField(
                      controller: _guidedAnswerCtrl,
                      maxLines: 5,
                      enabled: !_gradingGuided,
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        hintText: 'Write your answer in your own words…',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      height: 56,
                      child: ElevatedButton(
                        onPressed: (_gradingGuided ||
                                _guidedAnswerCtrl.text.trim().isEmpty)
                            ? null
                            : _submitGuidedComprehension,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _buttonBlue,
                          disabledBackgroundColor: Colors.grey[300],
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(30),
                          ),
                        ),
                        child: _gradingGuided
                            ? const SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 3,
                                ),
                              )
                            : Text(
                                isLast ? 'Submit Assessment' : 'Next Question',
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                      ),
                    ),
                  ] else ...[
                    // Options
                    ...options.entries.map((entry) {
                      final isSelected = _selectedAnswer == entry.key;
                      return GestureDetector(
                        onTap: () => _selectAnswer(entry.key),
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 14,
                          ),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? _buttonBlue
                                : _skyBlueLight.withValues(alpha: 0.3),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: isSelected
                                  ? _buttonBlue
                                  : _skyBlueDark.withValues(alpha: 0.3),
                            ),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 30,
                                height: 30,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: isSelected
                                      ? Colors.white.withValues(alpha: 0.3)
                                      : Colors.white,
                                ),
                                child: Center(
                                  child: Text(
                                    entry.key,
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: isSelected
                                          ? Colors.white
                                          : _navyText,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Text(
                                  entry.value.toString(),
                                  style: TextStyle(
                                    fontSize: 15,
                                    color: isSelected ? Colors.white : _navyText,
                                    fontWeight: isSelected
                                        ? FontWeight.w700
                                        : FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }),
                    const SizedBox(height: 24),

                    // Next / Submit
                    SizedBox(
                      height: 56,
                      child: ElevatedButton(
                        onPressed: _selectedAnswer == null ? null : _nextQuestion,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _buttonBlue,
                          disabledBackgroundColor: Colors.grey[300],
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(30),
                          ),
                        ),
                        child: Text(
                          isLast ? 'Submit Assessment' : 'Next Question',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ── 5. Saving ───────────────────────────────────────────────────────────
  Widget _buildSavingScreen() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(color: Colors.white),
          SizedBox(height: 24),
          Text(
            'Checking your answers...',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: _navyText,
            ),
          ),
        ],
      ),
    );
  }

  // ── 6. Results ──────────────────────────────────────────────────────────
  Widget _buildResultScreen() {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.stars_rounded, size: 100, color: _starYellow),
          const SizedBox(height: 20),
          const Text(
            'Assessment Complete!',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w900,
              color: _navyText,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Congratulations! You\'ve completed the assessment.\nHere are your scores:',
            textAlign: TextAlign.start,
            style: TextStyle(
              fontSize: 15,
              color: _navyText.withValues(alpha: 0.8),
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 20),
          Wrap(
            spacing: 16,
            runSpacing: 16,
            children: [
              // 'Writing' is excluded here even though _finalScores now
              // carries it (needed for saveAssessmentResults/
              // seedMasteryFromAssessment) — it's shown below as its own
              // pass/fail card instead, since dressing up a single item as
              // a percentage ("100%"/"0%") would overstate it.
              ..._finalScores.entries
                  .where((e) => e.key != 'Writing')
                  .map((e) => SizedBox(
                        width: 140,
                        child: _scoreCard(e.key, e.value),
                      )),
              if (_guidedCorrect != null)
                SizedBox(width: 140, child: _guidedResultCard()),
            ],
          ),
          const SizedBox(height: 20),
          Text(
            'Click the button below to go to your dashboard and start your learning journey!',
            textAlign: TextAlign.start,
            style: TextStyle(
              fontSize: 15,
              color: _navyText.withValues(alpha: 0.8),
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          SizedBox(
            width: double.infinity,
            height: 60,
            child: ElevatedButton(
              onPressed: () => Navigator.of(context).pushReplacement(
                MaterialPageRoute(builder: (_) => const HomeScreen()),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: _buttonBlue,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(30),
                ),
              ),
              child: const Text(
                'Go to Dashboard',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _scoreCard(String title, int score) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(color: _navyText.withValues(alpha: 0.1), blurRadius: 10),
        ],
      ),
      child: Column(
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 13,
              color: _navyText.withValues(alpha: 0.6),
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '$score%',
            style: const TextStyle(
              fontSize: 24,
              color: _buttonBlue,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }

  /// A single pass/fail card for the guided-comprehension question — kept
  /// distinct from _scoreCard's percentages, since one item dressed up as
  /// "100%"/"0%" would overstate what a single question actually shows.
  Widget _guidedResultCard() {
    final correct = _guidedCorrect == true;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(color: _navyText.withValues(alpha: 0.1), blurRadius: 10),
        ],
      ),
      child: Column(
        children: [
          Text(
            'Writing Sample',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              color: _navyText.withValues(alpha: 0.6),
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Icon(
            correct ? Icons.check_circle_rounded : Icons.info_rounded,
            color: correct ? Colors.green : Colors.orange,
            size: 26,
          ),
          const SizedBox(height: 4),
          Text(
            correct ? 'Correct' : 'Needs practice',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w900,
              color: correct ? Colors.green : Colors.orange,
            ),
          ),
        ],
      ),
    );
  }
}
