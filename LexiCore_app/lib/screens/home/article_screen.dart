import 'package:flutter/material.dart';
import '../../services/supabase_service.dart';
import '../../services/api_service.dart';

class ArticleScreen extends StatefulWidget {
  const ArticleScreen({super.key});

  @override
  State<ArticleScreen> createState() => _ArticleScreenState();
}

class _ArticleScreenState extends State<ArticleScreen> {
  static const Color _bg = Color(0xFFF0F8FF);
  static const Color _navyText = Color(0xFF003C8F);
  static const Color _buttonBlue = Color(0xFF1E88E5);
  static const Color _brightOrange = Color(0xFFFF9800);

  final _supabaseService = SupabaseService();
  final _apiService = ApiService();

  bool _isLoading = true;
  bool _isRegenerating = false;
  String _errorMessage = '';

  String _articleTitle = '';
  String _articleBody = '';
  String _articleTopic = '';
  int _standard = 3;
  List<Map<String, dynamic>> _hints = [];

  static const int _maxRegenerationsPerDay = 2; // must match the backend cap
  int _regenerationsUsed = 0;
  int get _regenerationsLeft =>
      (_maxRegenerationsPerDay - _regenerationsUsed).clamp(0, _maxRegenerationsPerDay);

  // Cached so "New Story" doesn't need to re-fetch the profile every tap.
  String _grade = 'B';
  String _rate = '{}';
  int? _vocabScore, _grammarScore, _readingScore, _writingScore;

  @override
  void initState() {
    super.initState();
    _loadArticle();
  }

  Future<void> _loadArticle() async {
    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });
    try {
      final profile = await _supabaseService.getStudentProfile();
      final assessment = await _supabaseService.getAssessmentResults();

      //1. Extract required profile fields with fallbacks
      _standard = profile?['standard'] as int? ?? 3;
      _grade = profile?['grade'] as String? ?? 'B';
      _rate = profile?['rate'] as String? ?? '{}';

      //2. Extract assessment scores (null if assessment was skipped)
      _vocabScore = assessment?['vocabulary_score'] as int?;
      _grammarScore = assessment?['grammar_score'] as int?;
      _readingScore = assessment?['reading_score'] as int?;
      _writingScore = assessment?['writing_score'] as int?;

      //3. Call the API service method with all 7 parameters
      final data = await _apiService.generateArticle(
        _standard,
        _grade,
        _rate,
        _vocabScore,
        _grammarScore,
        _readingScore,
        _writingScore,
      );

      // The function returns { success, is_new, source, article: {...} }
      // (or { success:false, message } on failure) — unwrap it here.
      final article =
          (data != null && data['success'] == true) ? data['article'] : null;

      if (article != null) {
        setState(() {
          _applyArticle(article);
          _isLoading = false;
        });
      } else {
        setState(() {
          _isLoading = false;
          _errorMessage =
              (data?['message'] as String?) ?? 'Could not load article.';
        });
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Something went wrong.';
      });
    }
  }

  void _applyArticle(Map article) {
    _articleTitle = article['title'] as String? ?? 'Today\'s Reading';
    _articleTopic = article['topic'] as String? ?? 'General';
    _articleBody = article['body'] as String? ?? '';
    _hints = List<Map<String, dynamic>>.from(article['hints'] as List? ?? []);
    _regenerationsUsed = (article['regenerations'] as int?) ?? 0;
  }

  /// "New Story" — unlike the initial load, a failure here must NOT wipe
  /// the article already on screen. It either swaps in a new story, or
  /// shows a small message (cap reached / network hiccup) while keeping
  /// today's story visible.
  Future<void> _regenerate() async {
    if (_isRegenerating || _regenerationsLeft <= 0) return;
    setState(() => _isRegenerating = true);

    final data = await _apiService.generateArticle(
      _standard,
      _grade,
      _rate,
      _vocabScore,
      _grammarScore,
      _readingScore,
      _writingScore,
      force: true,
    );

    if (!mounted) return;

    final ok = data != null && data['success'] == true;
    final article = ok ? data['article'] : null;

    if (article != null) {
      setState(() {
        _applyArticle(article);
        _isRegenerating = false;
      });
    } else {
      // Cap reached or a transient error — the function still sends back
      // today's article in `data['article']`, so re-sync the count even
      // though the story itself doesn't change.
      final fallbackArticle = data?['article'];
      setState(() {
        if (fallbackArticle is Map) {
          _regenerationsUsed =
              (fallbackArticle['regenerations'] as int?) ?? _regenerationsUsed;
        }
        _isRegenerating = false;
      });
      final message = (data?['message'] as String?) ??
          'Could not get a new story right now. Try again in a moment!';
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message)),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return _buildLoadingScreen();
    if (_errorMessage.isNotEmpty) return _buildErrorScreen();
    return _buildArticleScreen();
  }

  Widget _buildLoadingScreen() {
    return Scaffold(
      backgroundColor: _bg,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(color: _brightOrange),
            const SizedBox(height: 20),
            Text(
              'Writing your story...',
              style: TextStyle(
                color: _navyText.withValues(alpha: 0.6),
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorScreen() {
    return Scaffold(
      backgroundColor: _bg,
      appBar: _appBar('Daily Article'),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.book_rounded, size: 64, color: _brightOrange),
            const SizedBox(height: 16),
            Text(_errorMessage, style: const TextStyle(color: _navyText)),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _loadArticle,
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

  Widget _buildArticleScreen() {
    return Scaffold(
      backgroundColor: _bg,
      appBar: _appBar('Story Time'),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 120),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: _brightOrange.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                _articleTopic,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                  color: _brightOrange,
                ),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              _articleTitle,
              style: const TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w900,
                color: _navyText,
                height: 1.2,
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                const Icon(
                  Icons.auto_awesome_rounded,
                  size: 16,
                  color: _brightOrange,
                ),
                const SizedBox(width: 6),
              ],
            ),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(30),
                boxShadow: [
                  BoxShadow(
                    color: _navyText.withValues(alpha: 0.05),
                    blurRadius: 20,
                  ),
                ],
              ),
              child: Text(
                _articleBody,
                style: const TextStyle(
                  fontSize: 17,
                  color: _navyText,
                  height: 1.8,
                  letterSpacing: 0.3,
                ),
              ),
            ),
            const SizedBox(height: 32),
            if (_hints.isNotEmpty) _buildHintsSection(),
          ],
        ),
      ),
      bottomSheet: _buildBottomBar(),
    );
  }

  Widget _buildHintsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Words to Learn 💡',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w900,
            color: _navyText,
          ),
        ),
        const SizedBox(height: 16),
        ..._hints.map(
          (hint) => Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: _brightOrange.withValues(alpha: 0.1),
                width: 2,
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: _brightOrange.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.wordpress_outlined,
                    color: _brightOrange,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        hint['word'] ?? '',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                          color: _navyText,
                        ),
                      ),
                      Text(
                        hint['meaning'] ?? '',
                        style: TextStyle(
                          fontSize: 14,
                          color: _navyText.withValues(alpha: 0.6),
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBottomBar() {
    final capped = _regenerationsLeft <= 0;
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
      color: _bg,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            capped
                ? 'Come back tomorrow for a new story! 🌙'
                : '$_regenerationsLeft new ${_regenerationsLeft == 1 ? 'story' : 'stories'} left today',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: _navyText.withValues(alpha: 0.55),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton(
              onPressed: (capped || _isRegenerating) ? null : _regenerate,
              style: ElevatedButton.styleFrom(
                backgroundColor: _buttonBlue,
                disabledBackgroundColor: _buttonBlue.withValues(alpha: 0.4),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(25),
                ),
                elevation: 5,
                shadowColor: _buttonBlue.withValues(alpha: 0.4),
              ),
              child: _isRegenerating
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2.5),
                    )
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.refresh_rounded, color: Colors.white),
                        const SizedBox(width: 10),
                        Text(
                          capped ? 'No stories left' : 'New Story',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }

  AppBar _appBar(String title) => AppBar(
    backgroundColor: Colors.transparent,
    elevation: 0,
    leading: IconButton(
      icon: const Icon(Icons.arrow_back_ios_new_rounded, color: _navyText),
      onPressed: () => Navigator.pop(context),
    ),
    title: Text(
      title,
      style: const TextStyle(
        fontWeight: FontWeight.w900,
        color: _navyText,
        fontSize: 20,
      ),
    ),
  );
}