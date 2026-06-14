// ignore_for_file: unnecessary_underscores

import 'package:flutter/material.dart';
import '../../services/supabase_service.dart';
import '../../services/api_service.dart';
import '../../data/curriculum.dart';
import 'result_screen.dart';

// ── Palette ───────────────────────────────────────────────────────────────────
const Color _vocabColor = Color(0xFFFF9800);
const Color _bg = Color(0xFFF5F5F7);
const Color _textDark = Color(0xFF1A1A2E);
const Color _textMid = Color(0xFF6B7280);

// ─────────────────────────────────────────────────────────────────────────────
// ENTRY SCREEN — choose practice mode
// ─────────────────────────────────────────────────────────────────────────────
class VocabularyModuleScreen extends StatelessWidget {
  const VocabularyModuleScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: _textDark),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Vocabulary',
          style: TextStyle(
            fontWeight: FontWeight.w900,
            color: _vocabColor,
            fontSize: 22,
          ),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Hero
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [
                      Color(0xFFE65100),
                      Color(0xFFFF9800),
                      Color(0xFFFFB74D),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: _vocabColor.withValues(alpha: 0.3),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.abc_rounded, color: Colors.white, size: 40),
                    SizedBox(height: 12),
                    Text(
                      'Vocabulary Practice',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    SizedBox(height: 6),
                    Text(
                      'Choose how you want to practise words today',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 28),

              const Text(
                'Select a practice mode',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: _textDark,
                ),
              ),
              const SizedBox(height: 14),

              _modeCard(
                context,
                icon: Icons.image_search_rounded,
                title: 'Guess the Image',
                description: 'Look at a picture and choose the correct word',
                mode: 'image',
                tag: 'Visual',
                tagColor: const Color(0xFFFF9800),
              ),
              _modeCard(
                context,
                icon: Icons.menu_book_rounded,
                title: 'Word Meaning',
                description: 'Read a definition and choose the matching word',
                mode: 'meaning',
                tag: 'Reading',
                tagColor: const Color(0xFF64B5F6),
              ),
              _modeCard(
                context,
                icon: Icons.edit_note_rounded,
                title: 'Word in Context',
                description:
                    'Fill in the blank — choose the word that best fits the sentence',
                mode: 'context',
                tag: 'Writing',
                tagColor: const Color(0xFF4DB6AC),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _modeCard(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String description,
    required String mode,
    required String tag,
    required Color tagColor,
  }) {
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => VocabularyQuizScreen(mode: mode)),
      ),
      child: Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: tagColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(icon, color: tagColor, size: 28),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: _textDark,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: tagColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          tag,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: tagColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    description,
                    style: const TextStyle(
                      fontSize: 12,
                      color: _textMid,
                      height: 1.4,
                    ),
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
}

// ─────────────────────────────────────────────────────────────────────────────
// QUIZ SCREEN
// ─────────────────────────────────────────────────────────────────────────────
class VocabularyQuizScreen extends StatefulWidget {
  final String mode; // 'image' | 'meaning' | 'context'

  const VocabularyQuizScreen({super.key, required this.mode});

  @override
  State<VocabularyQuizScreen> createState() => _VocabularyQuizScreenState();
}

class _VocabularyQuizScreenState extends State<VocabularyQuizScreen> {
  final _supabaseService = SupabaseService();
  final _apiService = ApiService();

  bool _isLoading = true;
  String _errorMessage = '';

  int _currentIndex = 0;
  String? _selectedAnswer;
  bool _hasAnswered = false;

  List<dynamic> _questions = [];
  final Map<int, String> _answers = {};

  late CurriculumUnit _currentUnit;
  int _detectedLevel = 3;

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
      final profile = await _supabaseService.getStudentProfile();
      final assessment = await _supabaseService.getAssessmentResults();
      final progress = await _supabaseService.getModuleProgress();
      final history = await _supabaseService.getQuizHistory(
        moduleType: 'Vocabulary',
      );

      _detectedLevel =
          (assessment?['detected_level'] as int?) ??
          (profile?['standard'] as int?) ??
          3;

      final highest = progress['Vocabulary'] ?? 0;
      final lastScore = history.isNotEmpty
          ? (history.first['score'] as int?) ?? 0
          : 0;

      _currentUnit = Curriculum.getNextUnit('Vocabulary', highest, lastScore);

      final data = await _apiService.generateVocabularyModule(
        _detectedLevel,
        _currentUnit.topic,
        widget.mode,
      );

      if (data != null && data['questions'] != null) {
        setState(() {
          _questions = data['questions'];
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
      debugPrint('Vocab quiz error: $e');
    }
  }

  void _selectAnswer(String key) {
    if (_hasAnswered) return;
    setState(() {
      _selectedAnswer = key;
      _hasAnswered = true;
      _answers[_currentIndex] = key;
    });
  }

  void _next() {
    if (_currentIndex < _questions.length - 1) {
      setState(() {
        _currentIndex++;
        _selectedAnswer = _answers[_currentIndex];
        _hasAnswered = _answers.containsKey(_currentIndex);
      });
    } else {
      _finish();
    }
  }

  Future<void> _finish() async {
    int correct = 0;
    for (int i = 0; i < _questions.length; i++) {
      if (_answers[i] == _questions[i]['correct_answer']) correct++;
    }
    final score = _questions.isEmpty
        ? 0
        : ((correct / _questions.length) * 100).round();

    try {
      await _supabaseService.saveQuizProgress(
        moduleType: 'Vocabulary',
        unitNumber: _currentUnit.unitNumber,
        topic: _currentUnit.topic,
        score: score,
      );
    } catch (e) {
      debugPrint('Save error: $e');
    }

    if (mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => ResultScreen(
            moduleName: 'Vocabulary',
            moduleColor: _vocabColor,
            moduleIcon: Icons.abc_rounded,
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
    if (_isLoading) return _loadingScreen();
    if (_errorMessage.isNotEmpty) return _errorScreen();

    final q = _questions[_currentIndex];
    final options = q['options'] as Map<String, dynamic>? ?? {};
    final correct = q['correct_answer'] as String?;
    final imageUrl = q['image_url'] as String?;
    final contextText = q['context_text'] as String?;
    final explanation = q['explanation'] as String?;
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
            Text(
              'Unit ${_currentUnit.unitNumber} — ${_currentUnit.topic}',
              style: const TextStyle(
                fontSize: 12,
                color: _vocabColor,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: progress,
                backgroundColor: const Color(0xFFFFF3E0),
                valueColor: const AlwaysStoppedAnimation(_vocabColor),
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
              Text(
                'Question ${_currentIndex + 1} of ${_questions.length}',
                style: const TextStyle(fontSize: 13, color: _textMid),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),

              // Image (guess mode)
              if (imageUrl != null) ...[
                Container(
                  height: 220,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF8F0),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: _vocabColor.withValues(alpha: 0.2),
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: Image.network(
                      imageUrl,
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => Center(
                        child: Icon(
                          Icons.image_not_supported_outlined,
                          size: 48,
                          color: _vocabColor.withValues(alpha: 0.3),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],
              
              // Context sentence (context mode)
              if (contextText != null) ...[
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: _vocabColor.withValues(alpha: 0.07),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: _vocabColor.withValues(alpha: 0.2),
                    ),
                  ),
                  child: Text(
                    contextText,
                    style: const TextStyle(
                      fontSize: 15,
                      color: _textDark,
                      fontStyle: FontStyle.italic,
                      height: 1.5,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // Question
              Text(
                q['question'] ?? '',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: _textDark,
                  height: 1.4,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),

              // Options
              ...options.entries.map((entry) {
                final isSelected = _selectedAnswer == entry.key;
                final isCorrect = entry.key == correct;
                Color bg = const Color(0xFFFFF3E0);
                Color tc = _textDark;
                if (_hasAnswered) {
                  if (isCorrect) {
                    bg = Colors.green.shade100;
                    tc = Colors.green.shade800;
                  } else if (isSelected) {
                    bg = Colors.red.shade100;
                    tc = Colors.red.shade800;
                  }
                } else if (isSelected) {
                  bg = _vocabColor;
                  tc = Colors.white;
                }

                return GestureDetector(
                  onTap: () => _selectAnswer(entry.key),
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 14,
                    ),
                    decoration: BoxDecoration(
                      color: bg,
                      borderRadius: BorderRadius.circular(14),
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
                                color: tc,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            entry.value.toString(),
                            style: TextStyle(fontSize: 14, color: tc),
                          ),
                        ),
                        if (_hasAnswered && isCorrect)
                          Icon(
                            Icons.check_circle,
                            color: Colors.green.shade700,
                            size: 18,
                          ),
                        if (_hasAnswered && isSelected && !isCorrect)
                          Icon(
                            Icons.cancel,
                            color: Colors.red.shade700,
                            size: 18,
                          ),
                      ],
                    ),
                  ),
                );
              }),

              // Explanation
              if (_hasAnswered && explanation != null) ...[
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.blue.shade100),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.info_outline,
                        color: Colors.blue.shade700,
                        size: 16,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          explanation,
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.blue.shade800,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _hasAnswered ? _next : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _vocabColor,
                  disabledBackgroundColor: Colors.grey[300],
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
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

  Widget _loadingScreen() => Scaffold(
    backgroundColor: Colors.white,
    body: Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(color: _vocabColor),
          const SizedBox(height: 20),
          Text(
            'Loading Vocabulary questions...',
            style: TextStyle(color: _textMid),
          ),
        ],
      ),
    ),
  );

  Widget _errorScreen() => Scaffold(
    backgroundColor: Colors.white,
    appBar: AppBar(
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
            const Icon(Icons.wifi_off_rounded, size: 64, color: _vocabColor),
            const SizedBox(height: 16),
            Text(_errorMessage, textAlign: TextAlign.center),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _loadQuiz,
              style: ElevatedButton.styleFrom(
                backgroundColor: _vocabColor,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
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
