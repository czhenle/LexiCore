import 'package:flutter/material.dart';
import '../../services/supabase_service.dart';
import '../../services/api_service.dart';
import 'result_screen.dart';

const Color _grammarColor = Color(0xFF4DB6AC);
const Color _bg           = Color(0xFFF5F5F7);
const Color _textDark     = Color(0xFF1A1A2E);
const Color _textMid      = Color(0xFF6B7280);

// ─────────────────────────────────────────────────────────────────────────────
// Grammar topics grouped by category — KSSR aligned
// ─────────────────────────────────────────────────────────────────────────────
const Map<String, List<String>> grammarCategories = {
  'Nouns': [
    'Common Nouns',
    'Proper Nouns',
    'Singular and Plural Nouns',
    'Countable and Uncountable Nouns',
    'Collective Nouns',
  ],
  'Pronouns': [
    'Personal Pronouns',
    'Possessive Pronouns',
    'Demonstrative Pronouns',
  ],
  'Verbs': [
    'Action Verbs',
    'Simple Present Tense',
    'Simple Past Tense',
    'Present Continuous Tense',
    'Future Tense',
    'Irregular Verbs',
  ],
  'Adjectives & Adverbs': [
    'Descriptive Adjectives',
    'Comparative and Superlative',
    'Adverbs of Manner',
    'Adverbs of Time',
    'Adverbs of Frequency',
  ],
  'Sentences': [
    'Articles (a, an, the)',
    'Prepositions',
    'Conjunctions',
    'Simple Sentences',
    'Compound Sentences',
    'Punctuation',
  ],
  'Questions': [
    'Yes/No Questions',
    'Wh- Questions',
    'Question Tags',
  ],
};

// ─────────────────────────────────────────────────────────────────────────────
// ENTRY SCREEN — topic checklist
// ─────────────────────────────────────────────────────────────────────────────
class GrammarModuleScreen extends StatefulWidget {
  const GrammarModuleScreen({super.key});

  @override
  State<GrammarModuleScreen> createState() => _GrammarModuleScreenState();
}

class _GrammarModuleScreenState extends State<GrammarModuleScreen> {
  final Set<String> _selected = {};
  int _questionsPerTopic = 3;

  bool get _canStart => _selected.isNotEmpty;

  void _toggle(String topic) {
    setState(() {
      if (_selected.contains(topic)) {
        _selected.remove(topic);
      } else {
        _selected.add(topic);
      }
    });
  }

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
        title: const Text('Grammar',
            style: TextStyle(
                fontWeight: FontWeight.w900,
                color: _grammarColor,
                fontSize: 22)),
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Hero card
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF00796B), Color(0xFF4DB6AC),
                                 Color(0xFF80CBC4)],
                        begin: Alignment.topLeft,
                        end:   Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: _grammarColor.withValues(alpha: 0.3),
                          blurRadius: 16,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.rule_rounded,
                            color: Colors.white, size: 32),
                        const SizedBox(height: 10),
                        const Text('Grammar Practice',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.w900)),
                        const SizedBox(height: 4),
                        Text(
                          _selected.isEmpty
                              ? 'Select topics below to practise'
                              : '${_selected.length} topic${_selected.length > 1 ? 's' : ''} selected',
                          style: const TextStyle(
                              color: Colors.white70, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Questions per topic selector
                  const Text('Questions per topic',
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: _textDark)),
                  const SizedBox(height: 10),
                  Row(
                    children: [3, 5, 10].map((n) {
                      final selected = n == _questionsPerTopic;
                      return GestureDetector(
                        onTap: () =>
                            setState(() => _questionsPerTopic = n),
                        child: Container(
                          margin: const EdgeInsets.only(right: 10),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 20, vertical: 10),
                          decoration: BoxDecoration(
                            color: selected
                                ? _grammarColor
                                : Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: selected
                                  ? _grammarColor
                                  : const Color(0xFFE5E7EB),
                            ),
                          ),
                          child: Text('$n',
                              style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  color: selected
                                      ? Colors.white
                                      : _textMid,
                                  fontSize: 15)),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 24),

                  // Topic checklist by category
                  ...grammarCategories.entries.map((cat) => Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Category header
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Text(cat.key,
                            style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                                color: _textDark)),
                      ),
                      ...cat.value.map((topic) {
                        final isSelected = _selected.contains(topic);
                        return GestureDetector(
                          onTap: () => _toggle(topic),
                          child: Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 12),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? _grammarColor.withValues(alpha: 0.1)
                                  : Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: isSelected
                                    ? _grammarColor
                                    : const Color(0xFFE5E7EB),
                                width: isSelected ? 1.5 : 1,
                              ),
                            ),
                            child: Row(
                              children: [
                                AnimatedContainer(
                                  duration:
                                      const Duration(milliseconds: 200),
                                  width: 22, height: 22,
                                  decoration: BoxDecoration(
                                    shape:  BoxShape.circle,
                                    color:  isSelected
                                        ? _grammarColor
                                        : Colors.transparent,
                                    border: Border.all(
                                      color: isSelected
                                          ? _grammarColor
                                          : const Color(0xFFD1D5DB),
                                      width: 1.5,
                                    ),
                                  ),
                                  child: isSelected
                                      ? const Icon(Icons.check,
                                          color: Colors.white,
                                          size: 13)
                                      : null,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(topic,
                                      style: TextStyle(
                                          fontSize: 14,
                                          color: isSelected
                                              ? _grammarColor
                                              : _textDark,
                                          fontWeight: isSelected
                                              ? FontWeight.w700
                                              : FontWeight.w500)),
                                ),
                              ],
                            ),
                          ),
                        );
                      }),
                      const SizedBox(height: 16),
                    ],
                  )),
                ],
              ),
            ),
          ),

          // Start button (sticky at bottom)
          Container(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 28),
            color: _bg,
            child: Column(
              children: [
                if (_selected.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      '${_selected.length * _questionsPerTopic} questions total',
                      style: TextStyle(
                          fontSize: 13, color: _textMid),
                    ),
                  ),
                SizedBox(
                  width: double.infinity, height: 54,
                  child: ElevatedButton(
                    onPressed: _canStart
                        ? () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => GrammarQuizScreen(
                                  selectedTopics:    _selected.toList(),
                                  questionsPerTopic: _questionsPerTopic,
                                ),
                              ),
                            )
                        : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor:         _grammarColor,
                      disabledBackgroundColor: Colors.grey[300],
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16)),
                    ),
                    child: Text(
                      _canStart ? 'Start practice' : 'Select at least one topic',
                      style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: Colors.white),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// QUIZ SCREEN
// ─────────────────────────────────────────────────────────────────────────────
class GrammarQuizScreen extends StatefulWidget {
  final List<String> selectedTopics;
  final int          questionsPerTopic;

  const GrammarQuizScreen({
    super.key,
    required this.selectedTopics,
    required this.questionsPerTopic,
  });

  @override
  State<GrammarQuizScreen> createState() => _GrammarQuizScreenState();
}

class _GrammarQuizScreenState extends State<GrammarQuizScreen> {
  final _supabaseService = SupabaseService();
  final _apiService      = ApiService();

  bool   _isLoading    = true;
  String _errorMessage = '';

  int     _currentIndex = 0;
  String? _selectedAnswer;
  bool    _hasAnswered  = false;

  List<dynamic>          _questions = [];
  final Map<int, String> _answers   = {};
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
      _detectedLevel   = (assessment?['detected_level'] as int?) ??
          (profile?['standard']  as int?) ?? 3;

      final allQuestions = await _apiService.generateGrammarModule(
        _detectedLevel,
        widget.selectedTopics,
        widget.questionsPerTopic,
      );

      if (allQuestions != null && allQuestions.isNotEmpty) {
        setState(() {
          _questions = allQuestions;
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
      debugPrint('Grammar quiz error: $e');
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
        moduleType: 'Grammar',
        unitNumber: 1,
        topic:      widget.selectedTopics.join(', '),
        score:      score,
      );
    } catch (e) {
      debugPrint('Save error: $e');
    }

    if (mounted) {
      Navigator.of(context).pushReplacement(MaterialPageRoute(
        builder: (_) => ResultScreen(
          moduleName:     'Grammar',
          moduleColor:    _grammarColor,
          moduleIcon:     Icons.rule_rounded,
          unitNumber:     1,
          topic:          widget.selectedTopics.length == 1
              ? widget.selectedTopics.first
              : '${widget.selectedTopics.length} topics',
          score:          score,
          totalQuestions: _questions.length,
          correctAnswers: correct,
        ),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading)               return _loadingScreen();
    if (_errorMessage.isNotEmpty) return _errorScreen();

    final q           = _questions[_currentIndex];
    final options     = q['options'] as Map<String, dynamic>? ?? {};
    final correct     = q['correct_answer'] as String?;
    final topicLabel  = q['topic'] as String? ?? '';
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
          Text(topicLabel,
              style: const TextStyle(
                  fontSize: 12,
                  color: _grammarColor,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value:           progress,
              backgroundColor: const Color(0xFFE0F2F1),
              valueColor:      const AlwaysStoppedAnimation(_grammarColor),
              minHeight:       5,
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
              Text('Question ${_currentIndex + 1} of ${_questions.length}',
                  style: const TextStyle(fontSize: 13, color: _textMid),
                  textAlign: TextAlign.center),
              const SizedBox(height: 20),

              Text(q['question'] ?? '',
                  style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: _textDark,
                      height: 1.4),
                  textAlign: TextAlign.center),
              const SizedBox(height: 28),

              ...options.entries.map((entry) {
                final isSelected = _selectedAnswer == entry.key;
                final isCorrect  = entry.key == correct;
                Color bg = const Color(0xFFE0F2F1);
                Color tc = _textDark;
                if (_hasAnswered) {
                  if (isCorrect)       { bg = Colors.green.shade100; tc = Colors.green.shade800; }
                  else if (isSelected) { bg = Colors.red.shade100;   tc = Colors.red.shade800; }
                } else if (isSelected) { bg = _grammarColor; tc = Colors.white; }

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
                        child: Center(child: Text(entry.key,
                            style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: tc))),
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
                  backgroundColor:         _grammarColor,
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
        const CircularProgressIndicator(color: _grammarColor),
        const SizedBox(height: 20),
        Text('Generating ${widget.selectedTopics.length * widget.questionsPerTopic} questions...',
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
              size: 64, color: _grammarColor),
          const SizedBox(height: 16),
          Text(_errorMessage, textAlign: TextAlign.center),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: _loadQuiz,
            style: ElevatedButton.styleFrom(
              backgroundColor: _grammarColor,
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