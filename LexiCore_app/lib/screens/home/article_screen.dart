import 'package:flutter/material.dart';
import '../../services/supabase_service.dart';
import '../../services/api_service.dart';

class ArticleScreen extends StatefulWidget {
  const ArticleScreen({super.key});

  @override
  State<ArticleScreen> createState() => _ArticleScreenState();
}

class _ArticleScreenState extends State<ArticleScreen> {
  static const Color _bg         = Color(0xFFF0F8FF); 
  static const Color _navyText   = Color(0xFF003C8F);
  static const Color _buttonBlue = Color(0xFF1E88E5);
  static const Color _brightOrange = Color(0xFFFF9800);

  final _supabaseService = SupabaseService();
  final _apiService = ApiService();

  bool _isLoading = true;
  String _errorMessage = '';

  String _articleTitle = '';
  String _articleBody = '';
  String _articleTopic = '';
  int _detectedLevel = 3;
  List<Map<String, dynamic>> _hints = [];

  @override
  void initState() {
    super.initState();
    _loadArticle();
  }

  Future<void> _loadArticle() async {
    setState(() { _isLoading = true; _errorMessage = ''; });
    try {
      final profile = await _supabaseService.getStudentProfile();
      final assessment = await _supabaseService.getAssessmentResults();
      final standard = (profile?['standard'] as int?) ?? 3;
      _detectedLevel = (assessment?['detected_level'] as int?) ?? standard;
      final data = await _apiService.generateArticle(_detectedLevel);

      if (data != null) {
        setState(() {
          _articleTitle = data['title'] as String? ?? 'Today\'s Reading';
          _articleTopic = data['topic'] as String? ?? 'General';
          _articleBody = data['body'] as String? ?? '';
          _hints = List<Map<String, dynamic>>.from(data['hints'] as List? ?? []);
          _isLoading = false;
        });
      } else {
        setState(() { _isLoading = false; _errorMessage = 'Could not load article.'; });
      }
    } catch (e) {
      setState(() { _isLoading = false; _errorMessage = 'Something went wrong.'; });
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
            Text('Writing your story...', style: TextStyle(color: _navyText.withValues(alpha: 0.6), fontWeight: FontWeight.bold)),
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
              style: ElevatedButton.styleFrom(backgroundColor: _buttonBlue, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20))),
              child: const Text('Try again', style: TextStyle(color: Colors.white)),
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
              decoration: BoxDecoration(color: _brightOrange.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(20)),
              child: Text(_articleTopic, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: _brightOrange)),
            ),
            const SizedBox(height: 14),
            Text(_articleTitle, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: _navyText, height: 1.2)),
            const SizedBox(height: 10),
            Row(children: [
              const Icon(Icons.auto_awesome_rounded, size: 16, color: _brightOrange),
              const SizedBox(width: 6),
              Text('Level $_detectedLevel Reader', style: TextStyle(fontSize: 13, color: _navyText.withValues(alpha: 0.6), fontWeight: FontWeight.bold)),
            ]),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(30), boxShadow: [BoxShadow(color: _navyText.withValues(alpha: 0.05), blurRadius: 20)]),
              child: Text(_articleBody, style: const TextStyle(fontSize: 17, color: _navyText, height: 1.8, letterSpacing: 0.3)),
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
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Words to Learn 💡', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: _navyText)),
      const SizedBox(height: 16),
      ..._hints.map((hint) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: _brightOrange.withValues(alpha: 0.1), width: 2)),
        child: Row(children: [
          Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: _brightOrange.withValues(alpha: 0.1), shape: BoxShape.circle), child: const Icon(Icons.wordpress_outlined, color: _brightOrange)),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(hint['word'] ?? '', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: _navyText)),
            Text(hint['meaning'] ?? '', style: TextStyle(fontSize: 14, color: _navyText.withValues(alpha: 0.6), fontStyle: FontStyle.italic)),
          ])),
        ]),
      )),
    ]);
  }

  Widget _buildBottomBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
      color: _bg,
      child: SizedBox(
        width: double.infinity, height: 56,
        child: ElevatedButton(
          onPressed: _loadArticle,
          style: ElevatedButton.styleFrom(
            backgroundColor: _buttonBlue,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
            elevation: 5, shadowColor: _buttonBlue.withValues(alpha: 0.4),
          ),
          child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(Icons.refresh_rounded, color: Colors.white),
            SizedBox(width: 10),
            Text('New Story', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Colors.white)),
          ]),
        ),
      ),
    );
  }

  AppBar _appBar(String title) => AppBar(
    backgroundColor: Colors.transparent, elevation: 0,
    leading: IconButton(icon: const Icon(Icons.arrow_back_ios_new_rounded, color: _navyText), onPressed: () => Navigator.pop(context)),
    title: Text(title, style: const TextStyle(fontWeight: FontWeight.w900, color: _navyText, fontSize: 20)),
  );
}