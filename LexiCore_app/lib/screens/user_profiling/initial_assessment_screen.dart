// ignore_for_file: unnecessary_underscores

import 'package:flutter/material.dart';
import '../../services/supabase_service.dart';
import '../../services/api_service.dart';
import '../home/home_screen.dart';

enum AssessmentState { loading, error, transition, readingPassage, quiz, saving, results }

class InitialAssessmentScreen extends StatefulWidget {
  const InitialAssessmentScreen({super.key});

  @override
  State<InitialAssessmentScreen> createState() =>
      _InitialAssessmentScreenState();
}

class _InitialAssessmentScreenState extends State<InitialAssessmentScreen> {
  final _supabaseService = SupabaseService();
  final _apiService      = ApiService();

  static const Color _skyBlueLight = Color(0xFFDFF1FF);
  static const Color _skyBlueDark  = Color(0xFF7AC9FA);
  static const Color _navyText     = Color(0xFF003C8F);
  static const Color _buttonBlue   = Color(0xFF1E88E5);
  static const Color _starYellow   = Color(0xFFFFD54F);

  AssessmentState _currentState = AssessmentState.loading;
  String _errorMessage = '';

  int     _currentIndex   = 0;
  String? _selectedAnswer;

  List<dynamic>          _questions   = [];
  int                    _studentStandard = 3;
  final Map<int, String> _answers     = {};
  Map<String, int>       _finalScores = {};

  // Reading article — shown on passage screen before reading questions
  String _articleTitle = '';
  String _articleBody  = '';

  @override
  void initState() {
    super.initState();
    _loadAssessment();
  }

  Future<void> _loadAssessment() async {
    final profile    = await _supabaseService.getStudentProfile();
    _studentStandard = (profile?['standard'] as int?) ?? 3;

    // ── 20 questions: 5 per skill ────────────────────────────────────────
    final results = await Future.wait([
      _apiService.generateVocabularyModule(
          _studentStandard, 'Daily Life', 'meaning'),
      _apiService.generateGrammarModule(
          _studentStandard, ['Simple Present Tense'], 5),
      _apiService.generateReadingModule(
          _studentStandard, 'A Short Story'),
      _apiService.generateWritingModule(
          _studentStandard, 'Everyday Tasks', 'completion'),
    ]);

    final List<dynamic> all = [];

    // Vocabulary — Map with 'questions' key
    final vocabData = results[0];
    if (vocabData is Map && vocabData['questions'] != null) {
      final qs = (vocabData['questions'] as List).take(5).toList();
      for (var q in qs) {
        q['type'] = 'Vocabulary';
        all.add(q);
      }
    }

    // Grammar — List directly
    final grammarData = results[1];
    if (grammarData is List) {
      final qs = grammarData.take(5).toList();
      for (var q in qs) {
        q['type'] = 'Grammar';
        all.add(q);
      }
    }

    // Reading — Map with 'body' (article) + 'questions'
    // Inject article body as 'context_text' into each question
    final readingData = results[2];
    if (readingData is Map && readingData['questions'] != null) {
      final articleBody  = readingData['body']  as String? ?? '';
      final articleTitle = readingData['title'] as String? ?? 'Reading Passage';
      _articleTitle = articleTitle;
      _articleBody  = articleBody;
      final qs = (readingData['questions'] as List).take(5).toList();
      for (var q in qs) {
        q['type']         = 'Reading';
        q['context_text'] = articleBody;
        all.add(q);
      }
    }

    // Writing — Map with 'questions' key
    final writingData = results[3];
    if (writingData is Map && writingData['questions'] != null) {
      final qs = (writingData['questions'] as List).take(5).toList();
      for (var q in qs) {
        q['type'] = 'Writing';
        all.add(q);
      }
    }

    if (all.isNotEmpty) {
      // Sort: Vocabulary → Grammar → Reading → Writing
      all.sort((a, b) {
        const order = {
          'Vocabulary': 1, 'Grammar': 2, 'Reading': 3, 'Writing': 4
        };
        return (order[a['type']] ?? 99)
            .compareTo(order[b['type']] ?? 99);
      });

      setState(() {
        _questions    = all;
        _currentState = AssessmentState.transition;
      });
    } else {
      setState(() {
        _currentState = AssessmentState.error;
        _errorMessage =
            'Failed to generate assessment. Please check your internet connection.';
      });
    }
  }

  int _getCurrentStep() {
    if (_questions.isEmpty) return 1;
    switch (_questions[_currentIndex]['type'] as String? ?? 'Vocabulary') {
      case 'Vocabulary': return 1;
      case 'Grammar':    return 2;
      case 'Reading':    return 3;
      case 'Writing':    return 4;
      default:           return 1;
    }
  }

  void _selectAnswer(String option) =>
      setState(() => _selectedAnswer = option);

  void _handleBackPress() {
    if (_currentState == AssessmentState.transition) {
      Navigator.pop(context);
    } else if (_currentState == AssessmentState.readingPassage) {
      // Go back to transition screen
      setState(() => _currentState = AssessmentState.transition);
    } else if (_currentState == AssessmentState.quiz) {
      final currentType =
          _questions[_currentIndex]['type'] as String? ?? '';
      // If on first reading question, go back to passage screen
      if (currentType == 'Reading' &&
          (_currentIndex == 0 ||
              _questions[_currentIndex - 1]['type'] != 'Reading')) {
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
      final nextType =
          _questions[_currentIndex + 1]['type'] as String? ?? '';
      final currentType =
          _questions[_currentIndex]['type'] as String? ?? '';

      // Intercept: if moving from non-Reading → Reading, show passage first
      if (nextType == 'Reading' && currentType != 'Reading') {
        setState(() {
          _currentIndex++;
          _selectedAnswer = null;
          _currentState   = AssessmentState.readingPassage;
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

  Future<void> _finishAssessment() async {
    if (_selectedAnswer != null) {
      _answers[_currentIndex] = _selectedAnswer!;
    }
    setState(() => _currentState = AssessmentState.saving);

    final Map<String, List<bool>> results = {
      'Vocabulary': [], 'Grammar': [], 'Reading': [], 'Writing': [],
    };

    for (int i = 0; i < _questions.length; i++) {
      final type    = (_questions[i]['type']           as String?) ?? 'Grammar';
      final correct = _questions[i]['correct_answer']  as String?;
      final given   = _answers[i];
      if (results.containsKey(type)) {
        results[type]!.add(given != null && given == correct);
      }
    }

    int scorePercent(List<bool> answers) {
      if (answers.isEmpty) return 0;
      return ((answers.where((a) => a).length / answers.length) * 100).round();
    }

    _finalScores = {
      'Vocabulary': scorePercent(results['Vocabulary']!),
      'Grammar':    scorePercent(results['Grammar']!),
      'Reading':    scorePercent(results['Reading']!),
      'Writing':    scorePercent(results['Writing']!),
    };

    try {
      await _supabaseService.saveAssessmentResults(
        vocabularyScore: _finalScores['Vocabulary']!,
        grammarScore:    _finalScores['Grammar']!,
        readingScore:    _finalScores['Reading']!,
        writingScore:    _finalScores['Writing']!,
      );
    } catch (e) {
      debugPrint('Assessment save error: $e');
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
            end:   Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(child: _buildCurrentState()),
      ),
    );
  }

  Widget _buildCurrentState() {
    switch (_currentState) {
      case AssessmentState.loading:        return _buildLoadingScreen();
      case AssessmentState.error:          return _buildErrorScreen();
      case AssessmentState.transition:     return _buildTransitionScreen();
      case AssessmentState.readingPassage: return _buildReadingPassageScreen();
      case AssessmentState.quiz:           return _buildQuestionScreen();
      case AssessmentState.saving:         return _buildSavingScreen();
      case AssessmentState.results:        return _buildResultScreen();
    }
  }

  // ── 1. Loading ──────────────────────────────────────────────────────────
  Widget _buildLoadingScreen() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(color: Colors.white),
          const SizedBox(height: 24),
          const Text('Preparing your assessment...',
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: _navyText)),
          const SizedBox(height: 8),
          Text(
            'Generating questions for Standard $_studentStandard',
            style: TextStyle(
                fontSize: 14, color: _navyText.withValues(alpha: 0.8)),
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
            const Icon(Icons.wifi_off_rounded,
                size: 64, color: Colors.white),
            const SizedBox(height: 16),
            Text(_errorMessage,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 16,
                    color: _navyText,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () {
                setState(
                    () => _currentState = AssessmentState.loading);
                _loadAssessment();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: _buttonBlue,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20)),
              ),
              child: const Text('Try again',
                  style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  // ── 3. Transition ───────────────────────────────────────────────────────
  Widget _buildTransitionScreen() {
    final vocabCount   =
        _questions.where((q) => q['type'] == 'Vocabulary').length;
    final grammarCount =
        _questions.where((q) => q['type'] == 'Grammar').length;
    final readingCount =
        _questions.where((q) => q['type'] == 'Reading').length;
    final writingCount =
        _questions.where((q) => q['type'] == 'Writing').length;

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
              child: const Icon(Icons.arrow_back_ios_new_rounded,
                  color: _navyText, size: 20),
            ),
          ),
          const SizedBox(height: 40),
          const Center(
              child:
                  Icon(Icons.school_rounded, size: 100, color: Colors.white)),
          const SizedBox(height: 40),
          const Text('Now let\'s test your level!',
              style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.w900,
                  color: _navyText,
                  height: 1.2)),
          const SizedBox(height: 16),
          Text(
            'Complete a short 20-question assessment across 4 skills:',
            style: TextStyle(
                fontSize: 16,
                color: _navyText.withValues(alpha: 0.8),
                fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 24),
          _buildCountRow(
              Icons.abc_rounded,      'Vocabulary', vocabCount),
          _buildCountRow(
              Icons.rule_rounded,      'Grammar',    grammarCount),
          _buildCountRow(
              Icons.menu_book_rounded, 'Reading',    readingCount),
          _buildCountRow(
              Icons.edit_rounded,      'Writing',    writingCount),
          const Spacer(),
          SizedBox(
            width: double.infinity, height: 60,
            child: ElevatedButton(
              onPressed: () {
                // Find the first reading question index
                final firstReadingIndex = _questions.indexWhere(
                    (q) => q['type'] == 'Reading');
                if (firstReadingIndex != -1) {
                  // Start from vocab/grammar first, passage shown later
                  setState(() {
                    _currentIndex   = 0;
                    _selectedAnswer = null;
                    _currentState   = AssessmentState.quiz;
                  });
                } else {
                  setState(() {
                    _currentIndex   = 0;
                    _selectedAnswer = null;
                    _currentState   = AssessmentState.quiz;
                  });
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: _buttonBlue,
                elevation: 5,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(30)),
              ),
              child: const Text('Start Assessment',
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.white)),
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
          Icon(icon, color: _starYellow, size: 24),
          const SizedBox(width: 12),
          Text(title,
              style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: _navyText)),
          const Spacer(),
          Text('$count questions',
              style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: Colors.white)),
        ],
      ),
    );
  }

  // ── 3b. Reading Passage Screen ──────────────────────────────────────────
  Widget _buildReadingPassageScreen() {
    final wordCount  = _articleBody.split(' ').length;
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
                  child: const Icon(Icons.arrow_back_ios_new_rounded,
                      color: _navyText, size: 18),
                ),
              ),
              const SizedBox(width: 12),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: _navyText,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text('Step 3 of 4 — Reading',
                    style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 13)),
              ),
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
                topLeft:  Radius.circular(40),
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
                      Row(children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: _buttonBlue.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Text('Reading',
                              style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: _buttonBlue)),
                        ),
                        const SizedBox(width: 10),
                        Icon(Icons.timer_outlined,
                            size: 13,
                            color: _navyText.withValues(alpha: 0.5)),
                        const SizedBox(width: 4),
                        Text('~$readingMin min read',
                            style: TextStyle(
                                fontSize: 12,
                                color: _navyText.withValues(alpha: 0.5))),
                        const SizedBox(width: 10),
                        Text('$wordCount words',
                            style: TextStyle(
                                fontSize: 12,
                                color: _navyText.withValues(alpha: 0.5))),
                      ]),
                      const SizedBox(height: 12),

                      // Title
                      Text(
                        _articleTitle,
                        style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                            color: _navyText,
                            height: 1.3),
                      ),
                      const SizedBox(height: 12),

                      // Gradient accent line
                      Container(
                        height: 3,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              _buttonBlue,
                              _buttonBlue.withValues(alpha: 0.2)
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
                          letterSpacing: 0.1),
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
            width: double.infinity, height: 56,
            child: ElevatedButton(
              onPressed: () => setState(
                  () => _currentState = AssessmentState.quiz),
              style: ElevatedButton.styleFrom(
                backgroundColor: _buttonBlue,
                elevation: 0,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(30)),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text("I've finished reading",
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.white)),
                  SizedBox(width: 8),
                  Icon(Icons.arrow_forward_rounded,
                      color: Colors.white, size: 18),
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
    final question     = _questions[_currentIndex];
    final options      = question['options']      as Map<String, dynamic>? ?? {};
    final imageUrl     = question['image_url']    as String?;
    final questionType = (question['type']        as String?) ?? 'Vocabulary';
    final contextText  = question['context_text'] as String?;
    final currentStep  = _getCurrentStep();

    final questionText =
        (question['question'] as String?)?.isNotEmpty == true
            ? question['question'] as String
            : (question['prompt'] as String?) ?? 'Choose the correct answer:';

    final bool isWriting = questionType == 'Writing';

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
                  child: const Icon(Icons.arrow_back_ios_new_rounded,
                      color: _navyText, size: 18),
                ),
              ),
              Column(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 6),
                    decoration: BoxDecoration(
                      color: _navyText,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text('Step $currentStep of 4',
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 13)),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Q ${_currentIndex + 1} / ${_questions.length}',
                    style: TextStyle(
                        fontSize: 11,
                        color: _navyText.withValues(alpha: 0.7),
                        fontWeight: FontWeight.w600),
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
                topLeft:  Radius.circular(40),
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
                          horizontal: 14, vertical: 5),
                      decoration: BoxDecoration(
                        color: _buttonBlue.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        questionType.toUpperCase(),
                        style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w900,
                            color: _buttonBlue,
                            letterSpacing: 1.5),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // ── Writing: sentence with blank ──────────────────────
                  if (isWriting &&
                      contextText != null &&
                      contextText.isNotEmpty) ...[
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFEBEE)
                            .withValues(alpha: 0.6),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                            color: const Color(0xFFE57373)
                                .withValues(alpha: 0.3)),
                      ),
                      child: Text(
                        contextText,
                        style: const TextStyle(
                            fontSize: 15,
                            color: _navyText,
                            height: 1.5,
                            fontStyle: FontStyle.italic,
                            fontWeight: FontWeight.w600),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // ── Vocabulary: image ─────────────────────────────────
                  if (imageUrl != null) ...[
                    ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: Image.network(
                        imageUrl,
                        height: 160,
                        fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) =>
                            const SizedBox.shrink(),
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
                        height: 1.4),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),

                  // Options
                  ...options.entries.map((entry) {
                    final isSelected = _selectedAnswer == entry.key;
                    return GestureDetector(
                      onTap: () => _selectAnswer(entry.key),
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 14),
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
                              width: 30, height: 30,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: isSelected
                                    ? Colors.white.withValues(alpha: 0.3)
                                    : Colors.white,
                              ),
                              child: Center(
                                child: Text(entry.key,
                                    style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: isSelected
                                            ? Colors.white
                                            : _navyText)),
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Text(
                                entry.value.toString(),
                                style: TextStyle(
                                    fontSize: 15,
                                    color: isSelected
                                        ? Colors.white
                                        : _navyText,
                                    fontWeight: isSelected
                                        ? FontWeight.w700
                                        : FontWeight.w600),
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
                      onPressed: _selectedAnswer == null
                          ? null
                          : _nextQuestion,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _buttonBlue,
                        disabledBackgroundColor: Colors.grey[300],
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(30)),
                      ),
                      child: Text(
                        _currentIndex < _questions.length - 1
                            ? 'Next Question'
                            : 'Submit Assessment',
                        style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.white),
                      ),
                    ),
                  ),
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
          Text('Analysing your results...',
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: _navyText)),
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
          const Text('Assessment Complete!',
              style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                  color: _navyText)),
          const SizedBox(height: 10),
          Text(
            'Here is your baseline profile. Your daily lessons will be adapted to match this level.',
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: 15,
                color: _navyText.withValues(alpha: 0.8),
                fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 40),
          Row(
            children: [
              Expanded(
                  child: _scoreCard(
                      'Vocabulary', _finalScores['Vocabulary'] ?? 0)),
              const SizedBox(width: 16),
              Expanded(
                  child: _scoreCard(
                      'Grammar', _finalScores['Grammar'] ?? 0)),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                  child: _scoreCard(
                      'Reading', _finalScores['Reading'] ?? 0)),
              const SizedBox(width: 16),
              Expanded(
                  child: _scoreCard(
                      'Writing', _finalScores['Writing'] ?? 0)),
            ],
          ),
          const Spacer(),
          SizedBox(
            width: double.infinity, height: 60,
            child: ElevatedButton(
              onPressed: () => Navigator.of(context).pushReplacement(
                MaterialPageRoute(builder: (_) => const HomeScreen()),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: _buttonBlue,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(30)),
              ),
              child: const Text('Go to Dashboard',
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.white)),
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
          BoxShadow(
              color: _navyText.withValues(alpha: 0.1), blurRadius: 10)
        ],
      ),
      child: Column(
        children: [
          Text(title,
              style: TextStyle(
                  fontSize: 13,
                  color: _navyText.withValues(alpha: 0.6),
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text('$score%',
              style: const TextStyle(
                  fontSize: 24,
                  color: _buttonBlue,
                  fontWeight: FontWeight.w900)),
        ],
      ),
    );
  }
}