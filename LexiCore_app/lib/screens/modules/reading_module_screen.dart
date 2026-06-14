import 'package:flutter/material.dart';
import '../../services/supabase_service.dart';
import '../../services/api_service.dart';
import '../../data/curriculum.dart';
import 'result_screen.dart';

const Color _readingColor = Color(0xFF1E88E5);
const Color _textDark     = Color(0xFF1A1A2E);
const Color _textMid      = Color(0xFF6B7280);

// ─────────────────────────────────────────────────────────────────────────────
// STEP 1 — Article reading screen
// ─────────────────────────────────────────────────────────────────────────────
class ReadingModuleScreen extends StatefulWidget {
  const ReadingModuleScreen({super.key});

  @override
  State<ReadingModuleScreen> createState() => _ReadingModuleScreenState();
}

class _ReadingModuleScreenState extends State<ReadingModuleScreen> {
  final _supabaseService = SupabaseService();
  final _apiService      = ApiService();

  bool   _isLoading    = true;
  String _errorMessage = '';

  String _articleTitle = '';
  String _articleBody  = '';
  List<dynamic> _rawQuestions = [];
  late CurriculumUnit _currentUnit;
  int _detectedLevel = 3;

  @override
  void initState() {
    super.initState();
    _loadReading();
  }

  Future<void> _loadReading() async {
    setState(() { _isLoading = true; _errorMessage = ''; });
    try {
      final profile    = await _supabaseService.getStudentProfile();
      final assessment = await _supabaseService.getAssessmentResults();
      final progress   = await _supabaseService.getModuleProgress();
      final history    = await _supabaseService.getQuizHistory(
          moduleType: 'Reading');

      _detectedLevel = (assessment?['detected_level'] as int?) ??
          (profile?['standard']  as int?) ?? 3;

      final highest   = progress['Reading'] ?? 0;
      final lastScore = history.isNotEmpty
          ? (history.first['score'] as int?) ?? 0
          : 0;

      _currentUnit = Curriculum.getNextUnit('Reading', highest, lastScore);

      final data = await _apiService.generateReadingModule(
        _detectedLevel,
        _currentUnit.topic,
      );

      if (data != null) {
        setState(() {
          _articleTitle  = data['title']      as String?   ?? 'Reading Passage';
          _articleBody   = data['body']       as String?   ?? '';
          _rawQuestions  = data['questions']  as List<dynamic>? ?? [];
          _isLoading     = false;
        });
      } else {
        setState(() {
          _isLoading    = false;
          _errorMessage = 'Failed to load article. Please try again.';
        });
      }
    } catch (e) {
      setState(() {
        _isLoading    = false;
        _errorMessage = 'Something went wrong. Please try again.';
      });
      debugPrint('Reading load error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading)               return _loadingScreen();
    if (_errorMessage.isNotEmpty) return _errorScreen();

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: _textDark),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Reading',
                style: TextStyle(
                    fontWeight: FontWeight.w900,
                    color: _readingColor,
                    fontSize: 18)),
            Text('Unit ${_currentUnit.unitNumber} — ${_currentUnit.topic}',
                style: const TextStyle(
                    fontSize: 11,
                    color: _textMid,
                    fontWeight: FontWeight.w500)),
          ],
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Level badge
                    Row(children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: _readingColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text('Standard $_detectedLevel',
                            style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: _readingColor)),
                      ),
                      const SizedBox(width: 8),
                      Text('${_articleBody.split(' ').length} words',
                          style: TextStyle(
                              fontSize: 12, color: _textMid)),
                    ]),
                    const SizedBox(height: 14),

                    // Title
                    Text(_articleTitle,
                        style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                            color: _textDark,
                            height: 1.3)),
                    const SizedBox(height: 16),

                    Container(height: 2,
                        color: _readingColor.withValues(alpha: 0.15)),
                    const SizedBox(height: 16),

                    // Article body
                    Text(_articleBody,
                        style: const TextStyle(
                            fontSize: 16,
                            color: _textDark,
                            height: 1.9,
                            letterSpacing: 0.1)),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),

            // Go to questions button
            Container(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 28),
              color: Colors.white,
              child: SizedBox(
                width: double.infinity, height: 54,
                child: ElevatedButton(
                  onPressed: () => Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ReadingQuestionScreen(
                        articleTitle:  _articleTitle,
                        articleBody:   _articleBody,
                        rawQuestions:  _rawQuestions,
                        currentUnit:   _currentUnit,
                        detectedLevel: _detectedLevel,
                      ),
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _readingColor,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text('I\'ve finished reading',
                          style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
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
        ),
      ),
    );
  }

  Widget _loadingScreen() => Scaffold(
    backgroundColor: Colors.white,
    body: Center(child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const CircularProgressIndicator(color: _readingColor),
        const SizedBox(height: 20),
        Text('Generating your reading article...',
            style: TextStyle(color: _textMid)),
        const SizedBox(height: 6),
        Text('This may take a few seconds',
            style: TextStyle(color: Colors.grey[400], fontSize: 12)),
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
              size: 64, color: _readingColor),
          const SizedBox(height: 16),
          Text(_errorMessage, textAlign: TextAlign.center),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: _loadReading,
            style: ElevatedButton.styleFrom(
              backgroundColor: _readingColor,
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

// ─────────────────────────────────────────────────────────────────────────────
// STEP 2 — Question screen with save/submit/back-to-article
// ─────────────────────────────────────────────────────────────────────────────
class ReadingQuestionScreen extends StatefulWidget {
  final String        articleTitle;
  final String        articleBody;
  final List<dynamic> rawQuestions;
  final CurriculumUnit currentUnit;
  final int           detectedLevel;

  const ReadingQuestionScreen({
    super.key,
    required this.articleTitle,
    required this.articleBody,
    required this.rawQuestions,
    required this.currentUnit,
    required this.detectedLevel,
  });

  @override
  State<ReadingQuestionScreen> createState() =>
      _ReadingQuestionScreenState();
}

class _ReadingQuestionScreenState extends State<ReadingQuestionScreen> {
  final _supabaseService = SupabaseService();

  int     _currentIndex  = 0;
  final bool    _submitted     = false;

  // Saved answers (can change before submit)
  final Map<int, String> _savedAnswers = {};
  String? _currentSelection;

  @override
  void initState() {
    super.initState();
    _currentSelection = _savedAnswers[_currentIndex];
  }

  void _select(String key) {
    if (_submitted) return;
    setState(() => _currentSelection = key);
  }

  // ✨ Added method to handle going back to the previous question
  void _goPrevious() {
    // Save current selection before moving back
    if (_currentSelection != null) {
      _savedAnswers[_currentIndex] = _currentSelection!;
    }
    
    if (_currentIndex > 0) {
      setState(() {
        _currentIndex--;
        _currentSelection = _savedAnswers[_currentIndex];
      });
    }
  }

  void _saveAndNext() {
    if (_currentSelection != null) {
      _savedAnswers[_currentIndex] = _currentSelection!;
    }
    if (_currentIndex < widget.rawQuestions.length - 1) {
      setState(() {
        _currentIndex++;
        _currentSelection = _savedAnswers[_currentIndex];
      });
    }
  }

  void _backToArticle() {
    if (_currentSelection != null) {
      _savedAnswers[_currentIndex] = _currentSelection!;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _ArticleReviewScreen(
          title: widget.articleTitle,
          body:  widget.articleBody,
        ),
      ),
    );
  }

  Future<void> _submit() async {
    // Save current selection
    if (_currentSelection != null) {
      _savedAnswers[_currentIndex] = _currentSelection!;
    }

    int correct = 0;
    for (int i = 0; i < widget.rawQuestions.length; i++) {
      if (_savedAnswers[i] ==
          widget.rawQuestions[i]['correct_answer']) {
        correct++;
      }
    }
    final score = widget.rawQuestions.isEmpty
        ? 0
        : ((correct / widget.rawQuestions.length) * 100).round();

    try {
      await _supabaseService.saveQuizProgress(
        moduleType: 'Reading',
        unitNumber: widget.currentUnit.unitNumber,
        topic:      widget.currentUnit.topic,
        score:      score,
      );
    } catch (e) {
      debugPrint('Save reading error: $e');
    }

    if (mounted) {
      Navigator.of(context).pushReplacement(MaterialPageRoute(
        builder: (_) => ResultScreen(
          moduleName:     'Reading',
          moduleColor:    _readingColor,
          moduleIcon:     Icons.menu_book_rounded,
          unitNumber:     widget.currentUnit.unitNumber,
          topic:          widget.currentUnit.topic,
          score:          score,
          totalQuestions: widget.rawQuestions.length,
          correctAnswers: correct,
        ),
      ));
    }
  }

  void _showSubmitConfirm() {
    final unanswered = widget.rawQuestions.length -
        _savedAnswers.length -
        (_currentSelection != null &&
                !_savedAnswers.containsKey(_currentIndex)
            ? 0
            : 0);

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20)),
        title: const Text('Submit answers?',
            style: TextStyle(fontWeight: FontWeight.w800)),
        content: Text(
          unanswered > 0
              ? 'You have $unanswered unanswered question(s). Are you sure you want to submit?'
              : 'Submit all your answers for checking?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel',
                style: TextStyle(color: Colors.grey[600])),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _submit();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: _readingColor,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('Submit',
                style: TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final q       = widget.rawQuestions[_currentIndex];
    final options  = q['options'] as Map<String, dynamic>? ?? {};
    final progress = (_currentIndex + 1) / widget.rawQuestions.length;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: _textDark),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(children: [
          Text(widget.articleTitle,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontSize: 12,
                  color: _readingColor,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value:           progress,
              backgroundColor: const Color(0xFFE3F2FD),
              valueColor:
                  const AlwaysStoppedAnimation(_readingColor),
              minHeight: 5,
            ),
          ),
        ]),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Answered indicator dots
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(
                        widget.rawQuestions.length,
                        (i) {
                          final answered =
                              _savedAnswers.containsKey(i) ||
                              (i == _currentIndex &&
                                  _currentSelection != null);
                          final current = i == _currentIndex;
                          return Container(
                            width:  current ? 18 : 10,
                            height: 10,
                            margin: const EdgeInsets.only(right: 4),
                            decoration: BoxDecoration(
                              color: current
                                  ? _readingColor
                                  : answered
                                      ? _readingColor
                                          .withValues(alpha: 0.4)
                                      : Colors.grey[200],
                              borderRadius:
                                  BorderRadius.circular(5),
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 16),

                    Text(
                      'Question ${_currentIndex + 1} of ${widget.rawQuestions.length}',
                      style: const TextStyle(
                          fontSize: 13, color: _textMid),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),

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
                      final isSelected =
                          _currentSelection == entry.key ||
                          (_savedAnswers[_currentIndex] == entry.key &&
                              _currentSelection == null);
                      Color bg = const Color(0xFFE3F2FD);
                      Color tc = _textDark;
                      if (isSelected) { bg = _readingColor; tc = Colors.white; }

                      return GestureDetector(
                        onTap: () => _select(entry.key),
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 18, vertical: 14),
                          decoration: BoxDecoration(
                            color: bg,
                            borderRadius:
                                BorderRadius.circular(14),
                          ),
                          child: Row(children: [
                            Container(
                              width: 28, height: 28,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.white
                                    .withValues(alpha: 0.5),
                              ),
                              child: Center(
                                child: Text(entry.key,
                                    style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: tc)),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(entry.value.toString(),
                                  style: TextStyle(
                                      fontSize: 14,
                                      color: tc)),
                            ),
                          ]),
                        ),
                      );
                    }),
                  ],
                ),
              ),
            ),

            // Bottom action bar — ✨ Updated with Previous button
            Container(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border(
                    top: BorderSide(
                        color: Colors.grey[200]!, width: 1)),
              ),
              child: Column(
                children: [
                  Row(children: [
                    // ✨ Previous Question Button
                    Expanded(
                      flex: 1,
                      child: OutlinedButton(
                        onPressed: _currentIndex > 0 ? _goPrevious : null,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: _readingColor,
                          side: BorderSide(
                              color: _readingColor.withValues(alpha: 0.5)),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                        child: const Icon(Icons.arrow_back_rounded, size: 18),
                      ),
                    ),
                    const SizedBox(width: 10),

                    // Back to article
                    Expanded(
                      flex: 2,
                      child: OutlinedButton.icon(
                        onPressed: _backToArticle,
                        icon: const Icon(Icons.article_outlined, size: 16),
                        label: const Text('Article'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: _readingColor,
                          side: BorderSide(
                              color: _readingColor.withValues(alpha: 0.5)),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),

                    // Save + next
                    Expanded(
                      flex: 2,
                      child: ElevatedButton(
                        onPressed: _currentIndex < widget.rawQuestions.length - 1
                            ? _saveAndNext
                            : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _readingColor.withValues(alpha: 0.7),
                          disabledBackgroundColor: Colors.grey[200],
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text('Next',
                                style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold)),
                            SizedBox(width: 4),
                            Icon(Icons.arrow_forward_rounded, size: 16, color: Colors.white),
                          ],
                        ),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 10),

                  // Submit
                  SizedBox(
                    width: double.infinity, height: 48,
                    child: ElevatedButton(
                      onPressed: _showSubmitConfirm,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _readingColor,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                      child: const Text('Submit all answers',
                          style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              color: Colors.white)),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Article review overlay (back to article from questions)
// ─────────────────────────────────────────────────────────────────────────────
class _ArticleReviewScreen extends StatelessWidget {
  final String title;
  final String body;

  const _ArticleReviewScreen({
    required this.title,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: _textDark),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Back to article',
            style: TextStyle(
                color: _readingColor,
                fontWeight: FontWeight.w700,
                fontSize: 16)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Back to questions',
                style: TextStyle(
                    color: _readingColor,
                    fontWeight: FontWeight.w700)),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    color: _textDark,
                    height: 1.3)),
            const SizedBox(height: 16),
            Container(height: 2,
                color: _readingColor.withValues(alpha: 0.15)),
            const SizedBox(height: 16),
            Text(body,
                style: const TextStyle(
                    fontSize: 16,
                    color: _textDark,
                    height: 1.9)),
          ],
        ),
      ),
    );
  }
}