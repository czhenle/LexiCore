import 'package:flutter/material.dart';
import '../../services/supabase_service.dart';
import '../../services/api_service.dart';
import '../../data/curriculum.dart';
import 'result_screen.dart';

class ModuleQuizScreen extends StatefulWidget {
  final String moduleName;
  final IconData moduleIcon;
  final Color moduleColor;

  const ModuleQuizScreen({
    super.key,
    required this.moduleName,
    required this.moduleIcon,
    required this.moduleColor,
  });

  @override
  State<ModuleQuizScreen> createState() => _ModuleQuizScreenState();
}

class _ModuleQuizScreenState extends State<ModuleQuizScreen> {
  final _supabaseService = SupabaseService();
  final _apiService = ApiService();

  bool _isLoading = true;
  String _errorMessage = '';

  int _currentIndex = 0;
  String? _selectedAnswer;
  bool _hasAnswered = false;

  List<dynamic> _questions = [];
  final Map<int, String> _answers = {};

  int _studentStandard = 3;
  late CurriculumUnit _currentUnit;

  @override
  void initState() {
    super.initState();
    _loadQuiz();
  }

  Future<void> _loadQuiz() async {
    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      // Load student profile and progress
      final profile = await _supabaseService.getStudentProfile();
      final progress = await _supabaseService.getModuleProgress();
      final assessment = await _supabaseService.getAssessmentResults();

      _studentStandard = (profile?['standard'] as int?) ?? 3;
      final detectedLevel =
          (assessment?['detected_level'] as int?) ?? _studentStandard;

      // Determine which unit to show based on curriculum progression
      final highestCompleted = progress[widget.moduleName] ?? 0;
      final history = await _supabaseService.getQuizHistory(
        moduleType: widget.moduleName,
      );

      int lastScore = 0;
      if (history.isNotEmpty) {
        lastScore = (history.first['score'] as int?) ?? 0;
      }

      _currentUnit = Curriculum.getNextUnit(
        widget.moduleName,
        highestCompleted,
        lastScore,
      );

      // Generate questions for this specific unit topic
      Map<String, dynamic>? data;
      if (widget.moduleName == 'Vocabulary') {
        data = await _apiService.generateVocabularyModule(
          detectedLevel,
          _currentUnit.topic,
          'meaning',
        );
      } else if (widget.moduleName == 'Grammar') {
        final questions = await _apiService.generateGrammarModule(
          detectedLevel,
          [_currentUnit.topic],
          5,
        );
        if (questions != null) data = {'questions': questions};
      } else if (widget.moduleName == 'Reading') {
        data = await _apiService.generateReadingModule(
          detectedLevel,
          _currentUnit.topic,
        );
      } else if (widget.moduleName == 'Writing') {
        data = await _apiService.generateWritingModule(
          detectedLevel,
          _currentUnit.topic,
          'completion',
        );
      }

      final questions = data?['questions'];
      if (questions != null) {
        setState(() {
          _questions = questions;
          _isLoading = false;
        });
      } else {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Failed to load questions. Please try again.';
        });
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Something went wrong. Please try again.';
      });
      debugPrint('Quiz load error: $e');
    }
  }

  void _selectAnswer(String option) {
    if (_hasAnswered) return; // prevent changing after reveal
    setState(() {
      _selectedAnswer = option;
      _hasAnswered = true;
      _answers[_currentIndex] = option;
    });
  }

  void _nextQuestion() {
    if (_currentIndex < _questions.length - 1) {
      setState(() {
        _currentIndex++;
        _selectedAnswer = _answers[_currentIndex];
        _hasAnswered = _answers.containsKey(_currentIndex);
      });
    } else {
      _finishQuiz();
    }
  }

  Future<void> _finishQuiz() async {
    // Calculate score
    int correct = 0;
    for (int i = 0; i < _questions.length; i++) {
      final given = _answers[i];
      final expected = _questions[i]['correct_answer'] as String?;
      if (given != null && given == expected) correct++;
    }

    final score = _questions.isEmpty
        ? 0
        : ((correct / _questions.length) * 100).round();

    // Save to Supabase
    try {
      await _supabaseService.saveQuizProgress(
        moduleType: widget.moduleName,
        unitNumber: _currentUnit.unitNumber,
        topic: _currentUnit.topic,
        score: score,
      );
    } catch (e) {
      debugPrint('Quiz save error: $e');
    }

    // Navigate to result screen
    if (mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => ResultScreen(
            moduleName: widget.moduleName,
            moduleColor: widget.moduleColor,
            moduleIcon: widget.moduleIcon,
            unitNumber: _currentUnit.unitNumber,
            topic: _currentUnit.topic,
            score: score,
            totalQuestions: _questions.length,
            correctAnswers: correct,
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return _buildLoadingScreen();
    if (_errorMessage.isNotEmpty) return _buildErrorScreen();
    return _buildQuizScreen();
  }

  Widget _buildLoadingScreen() {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: widget.moduleColor),
            const SizedBox(height: 24),
            Text(
              'Loading ${widget.moduleName} questions...',
              style: TextStyle(
                fontSize: 16,
                color: widget.moduleColor,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorScreen() {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.wifi_off_rounded, size: 64, color: widget.moduleColor),
              const SizedBox(height: 16),
              Text(
                _errorMessage,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 15),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _loadQuiz,
                style: ElevatedButton.styleFrom(
                  backgroundColor: widget.moduleColor,
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
      ),
    );
  }

  Widget _buildQuizScreen() {
    final question = _questions[_currentIndex];
    final options = question['options'] as Map<String, dynamic>? ?? {};
    final correct = question['correct_answer'] as String?;
    final imageUrl = question['image_url'] as String?;
    final explanation = question['explanation'] as String?;
    final progress = (_currentIndex + 1) / _questions.length;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(
          children: [
            // Unit info
            Text(
              'Unit ${_currentUnit.unitNumber} — ${_currentUnit.topic}',
              style: TextStyle(
                fontSize: 13,
                color: widget.moduleColor,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: progress,
                backgroundColor: const Color(0xFFDFF1FF),
                valueColor: AlwaysStoppedAnimation(widget.moduleColor),
                minHeight: 5,
              ),
            ),
          ],
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Question counter
              Text(
                'Question ${_currentIndex + 1} of ${_questions.length}',
                style: TextStyle(
                  fontSize: 13,
                  color: Color(0xFF003C8F).withValues(alpha: 0.4),
                  fontWeight: FontWeight.w500,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),

              // Image if present
              if (imageUrl != null) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: Image.network(
                    imageUrl,
                    height: 160,
                    fit: BoxFit.cover,
                    // ignore: unnecessary_underscores
                    errorBuilder: (_, __, _) => const SizedBox.shrink(),
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // Question text
              Text(
                question['question'] ?? '',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF003C8F),
                  height: 1.4,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 28),

              // Answer options
              ...options.entries.map((entry) {
                final isSelected = _selectedAnswer == entry.key;
                final isCorrect = entry.key == correct;

                Color bgColor = const Color(0xFFDFF1FF);
                Color textColor = Color(0xFF003C8F);

                if (_hasAnswered) {
                  if (isCorrect) {
                    bgColor = Colors.green.shade100;
                    textColor = Colors.green.shade800;
                  } else if (isSelected && !isCorrect) {
                    bgColor = Colors.red.shade100;
                    textColor = Colors.red.shade800;
                  }
                } else if (isSelected) {
                  bgColor = widget.moduleColor;
                  textColor = Colors.white;
                }

                return GestureDetector(
                  onTap: () => _selectAnswer(entry.key),
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 16,
                    ),
                    decoration: BoxDecoration(
                      color: bgColor,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white.withValues(alpha: 0.5),
                          ),
                          child: Center(
                            child: Text(
                              entry.key,
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: textColor,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Text(
                            entry.value,
                            style: TextStyle(
                              fontSize: 15,
                              color: textColor,
                              fontWeight: isSelected
                                  ? FontWeight.w600
                                  : FontWeight.normal,
                            ),
                          ),
                        ),
                        if (_hasAnswered && isCorrect)
                          Icon(
                            Icons.check_circle,
                            color: Colors.green.shade700,
                            size: 20,
                          ),
                        if (_hasAnswered && isSelected && !isCorrect)
                          Icon(
                            Icons.cancel,
                            color: Colors.red.shade700,
                            size: 20,
                          ),
                      ],
                    ),
                  ),
                );
              }),

              // Explanation (shown after answering)
              if (_hasAnswered && explanation != null) ...[
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Color(0xFFDFF1FF),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: Color(0xFF7AC9FA)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.info_outline,
                        color: Color(0xFF1E88E5),
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          explanation,
                          style: TextStyle(
                            fontSize: 13,
                            color: Color(0xFF003C8F),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 24),

              // Next button — only active after answering
              ElevatedButton(
                onPressed: _hasAnswered ? _nextQuestion : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: widget.moduleColor,
                  disabledBackgroundColor: Color(
                    0xFF7AC9FA,
                  ).withValues(alpha: 0.5),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
                child: Text(
                  _currentIndex < _questions.length - 1
                      ? 'Next question'
                      : 'See my result',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
