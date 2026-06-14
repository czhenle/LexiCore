import 'package:flutter/material.dart';
import '../../services/supabase_service.dart';
import '../../services/api_service.dart';
import '../../data/curriculum.dart';
import 'result_screen.dart';

const Color _writingColor = Color(0xFFE57373);
const Color _bg           = Color(0xFFF5F5F7);
const Color _textDark     = Color(0xFF1A1A2E);
const Color _textMid      = Color(0xFF6B7280);

// ─────────────────────────────────────────────────────────────────────────────
// ENTRY — choose writing exercise type
// ─────────────────────────────────────────────────────────────────────────────
class WritingModuleScreen extends StatelessWidget {
  const WritingModuleScreen({super.key});

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
        title: const Text('Writing',
            style: TextStyle(
                fontWeight: FontWeight.w900,
                color: _writingColor,
                fontSize: 22)),
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
                    colors: [Color(0xFFB71C1C), Color(0xFFE57373),
                             Color(0xFFEF9A9A)],
                    begin: Alignment.topLeft,
                    end:   Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: _writingColor.withValues(alpha: 0.3),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.edit_rounded,
                        color: Colors.white, size: 36),
                    SizedBox(height: 10),
                    Text('Writing Practice',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.w900)),
                    SizedBox(height: 4),
                    Text(
                      'Choose an exercise type to practise',
                      style: TextStyle(
                          color: Colors.white70, fontSize: 13),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 28),

              const Text('Exercise types',
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: _textDark)),
              const SizedBox(height: 14),

              _exerciseCard(
                context,
                icon:        Icons.format_list_numbered_rounded,
                title:       'Sentence Completion',
                description:
                    'Fill in the blank with the correct word or phrase',
                type:        'completion',
                color:       const Color(0xFFE57373),
              ),
              _exerciseCard(
                context,
                icon:        Icons.sort_rounded,
                title:       'Sentence Ordering',
                description:
                    'Arrange jumbled words into a correct sentence',
                type:        'ordering',
                color:       const Color(0xFFFF9800),
              ),
              _exerciseCard(
                context,
                icon:        Icons.find_replace_rounded,
                title:       'Error Correction',
                description:
                    'Spot the grammar or spelling mistake in each sentence',
                type:        'correction',
                color:       const Color(0xFF9575CD),
              ),
              _exerciseCard(
                context,
                icon:        Icons.auto_fix_high_rounded,
                title:       'Guided Composition',
                description:
                    'Answer questions about a prompt to build a short paragraph',
                type:        'composition',
                color:       const Color(0xFF4DB6AC),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _exerciseCard(
    BuildContext context, {
    required IconData icon,
    required String   title,
    required String   description,
    required String   type,
    required Color    color,
  }) {
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => WritingQuizScreen(exerciseType: type),
        ),
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
                offset: const Offset(0, 4)),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 56, height: 56,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(icon, color: color, size: 28),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: _textDark)),
                  const SizedBox(height: 4),
                  Text(description,
                      style: const TextStyle(
                          fontSize: 12,
                          color: _textMid,
                          height: 1.4)),
                ],
              ),
            ),
            Icon(Icons.arrow_forward_ios_rounded,
                size: 14, color: Colors.grey[400]),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// QUIZ SCREEN
// ─────────────────────────────────────────────────────────────────────────────
class WritingQuizScreen extends StatefulWidget {
  final String exerciseType;

  const WritingQuizScreen({super.key, required this.exerciseType});

  @override
  State<WritingQuizScreen> createState() => _WritingQuizScreenState();
}

class _WritingQuizScreenState extends State<WritingQuizScreen> {
  final _supabaseService = SupabaseService();
  final _apiService      = ApiService();

  bool   _isLoading    = true;
  String _errorMessage = '';

  int     _currentIndex = 0;
  String? _selectedAnswer;
  bool    _hasAnswered  = false;

  List<dynamic>          _questions = [];
  final Map<int, String> _answers   = {};

  late CurriculumUnit _currentUnit;
  int _detectedLevel = 3;

  @override
  void initState() {
    super.initState();
    _loadQuiz();
  }

  Future<void> _loadQuiz() async {
    setState(() { _isLoading = true; _errorMessage = ''; });
    try {
      final profile    = await _supabaseService.getStudentProfile();
      final assessment = await _supabaseService.getAssessmentResults();
      final progress   = await _supabaseService.getModuleProgress();
      final history    =
          await _supabaseService.getQuizHistory(moduleType: 'Writing');

      _detectedLevel = (assessment?['detected_level'] as int?) ??
          (profile?['standard']  as int?) ?? 3;

      final highest   = progress['Writing'] ?? 0;
      final lastScore = history.isNotEmpty
          ? (history.first['score'] as int?) ?? 0
          : 0;

      _currentUnit =
          Curriculum.getNextUnit('Writing', highest, lastScore);

      final data = await _apiService.generateWritingModule(
        _detectedLevel,
        _currentUnit.topic,
        widget.exerciseType,
      );

      if (data != null && data['questions'] != null) {
        setState(() {
          _questions = data['questions'];
          _isLoading = false;
        });
      } else {
        setState(() {
          _isLoading    = false;
          _errorMessage = 'Failed to load questions. Please try again.';
        });
      }
    } catch (e) {
      setState(() {
        _isLoading    = false;
        _errorMessage = 'Something went wrong. Please try again.';
      });
      debugPrint('Writing quiz error: $e');
    }
  }

  void _selectAnswer(String key) {
    if (_hasAnswered) return;
    setState(() {
      _selectedAnswer         = key;
      _hasAnswered            = true;
      _answers[_currentIndex] = key;
    });
  }

  void _next() {
    if (_currentIndex < _questions.length - 1) {
      setState(() {
        _currentIndex++;
        _selectedAnswer = _answers[_currentIndex];
        _hasAnswered    = _answers.containsKey(_currentIndex);
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
        moduleType: 'Writing',
        unitNumber: _currentUnit.unitNumber,
        topic:      _currentUnit.topic,
        score:      score,
      );
    } catch (e) {
      debugPrint('Save writing error: $e');
    }

    if (mounted) {
      Navigator.of(context).pushReplacement(MaterialPageRoute(
        builder: (_) => ResultScreen(
          moduleName:     'Writing',
          moduleColor:    _writingColor,
          moduleIcon:     Icons.edit_rounded,
          unitNumber:     _currentUnit.unitNumber,
          topic:          _currentUnit.topic,
          score:          score,
          totalQuestions: _questions.length,
          correctAnswers: correct,
        ),
      ));
    }
  }

  String get _exerciseLabel {
    switch (widget.exerciseType) {
      case 'completion':  return 'Sentence Completion';
      case 'ordering':    return 'Sentence Ordering';
      case 'correction':  return 'Error Correction';
      case 'composition': return 'Guided Composition';
      default:            return 'Writing';
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading)               return _loadingScreen();
    if (_errorMessage.isNotEmpty) return _errorScreen();

    final q           = _questions[_currentIndex];
    final options     = q['options'] as Map<String, dynamic>? ?? {};
    final correct     = q['correct_answer'] as String?;
    final contextText = q['context_text'] as String?;
    final explanation = q['explanation'] as String?;
    final progress    = (_currentIndex + 1) / _questions.length;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(children: [
          Text(_exerciseLabel,
              style: const TextStyle(
                  fontSize: 12,
                  color: _writingColor,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value:           progress,
              backgroundColor: const Color(0xFFFFEBEE),
              valueColor:
                  const AlwaysStoppedAnimation(_writingColor),
              minHeight: 5,
            ),
          ),
        ]),
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

              // Context text (sentence with blank or paragraph)
              if (contextText != null && contextText.isNotEmpty) ...[
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: _writingColor.withValues(alpha: 0.07),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: _writingColor.withValues(alpha: 0.2)),
                  ),
                  child: Text(contextText,
                      style: const TextStyle(
                          fontSize: 15,
                          color: _textDark,
                          height: 1.6,
                          fontStyle: FontStyle.italic)),
                ),
                const SizedBox(height: 16),
              ],

              // Question
              Text(q['question'] ?? '',
                  style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: _textDark,
                      height: 1.4),
                  textAlign: TextAlign.center),
              const SizedBox(height: 24),

              // Options
              ...options.entries.map((entry) {
                final isSelected = _selectedAnswer == entry.key;
                final isCorrect  = entry.key == correct;
                Color bg = const Color(0xFFFFEBEE);
                Color tc = _textDark;
                if (_hasAnswered) {
                  if (isCorrect)       { bg = Colors.green.shade100; tc = Colors.green.shade800; }
                  else if (isSelected) { bg = Colors.red.shade100;   tc = Colors.red.shade800; }
                } else if (isSelected) { bg = _writingColor; tc = Colors.white; }

                return GestureDetector(
                  onTap: () => _selectAnswer(entry.key),
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 18, vertical: 14),
                    decoration: BoxDecoration(
                        color: bg,
                        borderRadius: BorderRadius.circular(14)),
                    child: Row(children: [
                      Container(
                        width: 28, height: 28,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white.withValues(alpha: 0.5),
                        ),
                        child: Center(
                          child: Text(entry.key,
                              style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: tc)),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(child: Text(entry.value.toString(),
                          style: TextStyle(fontSize: 14, color: tc))),
                      if (_hasAnswered && isCorrect)
                        Icon(Icons.check_circle,
                            color: Colors.green.shade700, size: 18),
                      if (_hasAnswered && isSelected && !isCorrect)
                        Icon(Icons.cancel,
                            color: Colors.red.shade700, size: 18),
                    ]),
                  ),
                );
              }),

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
                      Icon(Icons.info_outline,
                          color: Colors.blue.shade700, size: 16),
                      const SizedBox(width: 8),
                      Expanded(child: Text(explanation,
                          style: TextStyle(
                              fontSize: 13,
                              color: Colors.blue.shade800))),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _hasAnswered ? _next : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor:         _writingColor,
                  disabledBackgroundColor: Colors.grey[300],
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                child: Text(
                  _currentIndex < _questions.length - 1
                      ? 'Next question'
                      : 'See my result',
                  style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.white),
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
    body: Center(child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const CircularProgressIndicator(color: _writingColor),
        const SizedBox(height: 20),
        Text('Loading $_exerciseLabel questions...',
            style: TextStyle(color: _textMid)),
      ],
    )),
  );

  Widget _errorScreen() => Scaffold(
    backgroundColor: Colors.white,
    appBar: AppBar(
      leading: IconButton(
        icon: const Icon(Icons.arrow_back),
        onPressed: () => Navigator.pop(context),
      ),
    ),
    body: Center(child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.wifi_off_rounded,
              size: 64, color: _writingColor),
          const SizedBox(height: 16),
          Text(_errorMessage, textAlign: TextAlign.center),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: _loadQuiz,
            style: ElevatedButton.styleFrom(
              backgroundColor: _writingColor,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
            ),
            child: const Text('Try again',
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    )),
  );
}