import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class ApiService {
  static const String supabaseUrl =
      'https://cldngeqtuyxwuvtsaocm.supabase.co/functions/v1';
  static const String anonKey =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImNsZG5nZXF0dXl4d3V2dHNhb2NtIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzU1NDQzNTgsImV4cCI6MjA5MTEyMDM1OH0.vYL9Cn81OptK7UVyZzbjpLxS_uyzPOiSrLyqQX9X6Nk';

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $anonKey',
      };

  // ── VOCABULARY MODULE ────────────────────────────────────────────────────
  // mode: 'image' | 'meaning' | 'context'
  Future<Map<String, dynamic>?> generateVocabularyModule(
      int level, String topic, String mode) async {
    try {
      final response = await http.post(
        Uri.parse('$supabaseUrl/vocabulary'),
        headers: _headers,
        body: jsonEncode({
          'standard': level,
          'topic':    topic,
          'mode':     mode,
        }),
      );
      if (response.statusCode == 200) return jsonDecode(response.body);
      debugPrint('Vocab error [${response.statusCode}]: ${response.body}');
      return null;
    } catch (e) {
      debugPrint('Vocab network error: $e');
      return null;
    }
  }

  // ── GRAMMAR MODULE ───────────────────────────────────────────────────────
  // Returns flat list of questions across all selected topics
  Future<List<dynamic>?> generateGrammarModule(
      int level, List<String> topics, int questionsPerTopic) async {
    try {
      // Fire one request per topic in parallel
      final futures = topics.map((topic) async {
        final res = await http.post(
          Uri.parse('$supabaseUrl/grammar'),
          headers: _headers,
          body: jsonEncode({
            'standard':            level,
            'topic':               topic,
            'questions_per_topic': questionsPerTopic,
          }),
        );
        if (res.statusCode == 200) {
          final data = jsonDecode(res.body);
          final questions =
              (data['questions'] as List<dynamic>? ?? []);
          // Tag each question with its topic
          return questions.map((q) {
            q['topic'] = topic;
            return q;
          }).toList();
        }
        return <dynamic>[];
      });

      final results = await Future.wait(futures);
      final all = results.expand((q) => q).toList();
      all.shuffle();
      return all.isNotEmpty ? all : null;
    } catch (e) {
      debugPrint('Grammar network error: $e');
      return null;
    }
  }

  // ── READING MODULE ───────────────────────────────────────────────────────
  Future<Map<String, dynamic>?> generateReadingModule(
      int level, String topic) async {
    try {
      final response = await http.post(
        Uri.parse('$supabaseUrl/reading'),
        headers: _headers,
        body: jsonEncode({
          'standard': level,
          'topic':    topic,
        }),
      );
      if (response.statusCode == 200) return jsonDecode(response.body);
      debugPrint('Reading error [${response.statusCode}]: ${response.body}');
      return null;
    } catch (e) {
      debugPrint('Reading network error: $e');
      return null;
    }
  }

  // ── WRITING MODULE ───────────────────────────────────────────────────────
  // exerciseType: 'completion' | 'ordering' | 'correction' | 'composition'
  Future<Map<String, dynamic>?> generateWritingModule(
      int level, String topic, String exerciseType) async {
    try {
      final response = await http.post(
        Uri.parse('$supabaseUrl/writing'),
        headers: _headers,
        body: jsonEncode({
          'standard':      level,
          'topic':         topic,
          'exercise_type': exerciseType,
        }),
      );
      if (response.statusCode == 200) return jsonDecode(response.body);
      debugPrint('Writing error [${response.statusCode}]: ${response.body}');
      return null;
    } catch (e) {
      debugPrint('Writing network error: $e');
      return null;
    }
  }

  // ── ARTICLE GENERATOR ───────────────────────────────────────────────────
  Future<Map<String, dynamic>?> generateArticle(int detectedLevel) async {
    try {
      final response = await http.post(
        Uri.parse('$supabaseUrl/article'),
        headers: _headers,
        body: jsonEncode({'detected_level': detectedLevel}),
      );
      if (response.statusCode == 200) return jsonDecode(response.body);
      debugPrint('Article error [${response.statusCode}]: ${response.body}');
      return null;
    } catch (e) {
      debugPrint('Article network error: $e');
      return null;
    }
  }

  // ── STUDY SCHEDULE ───────────────────────────────────────────────────────
  Future<Map<String, dynamic>?> generateSchedule(
    int standard,
    String studyTime,
    String strength,
    String weakness, {
    int detectedLevel = 3,
    int vocabScore    = 0,
    int grammarScore  = 0,
    int readingScore  = 0,
    int writingScore  = 0,
    String? modifier,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$supabaseUrl/schedule'),
        headers: _headers,
        body: jsonEncode({
          'standard':       standard,
          'detected_level': detectedLevel,
          'study_time':     studyTime,
          'strength':       strength,
          'weakness':       weakness,
          'vocab_score':    vocabScore,
          'grammar_score':  grammarScore,
          'reading_score':  readingScore,
          'writing_score':  writingScore,
          'modifier': ?modifier,
        }),
      );
      if (response.statusCode == 200) return jsonDecode(response.body);
      debugPrint('Schedule error [${response.statusCode}]: ${response.body}');
      return null;
    } catch (e) {
      debugPrint('Schedule network error: $e');
      return null;
    }
  }

  // ── AI CHATBOT ───────────────────────────────────────────────────────────
  Future<String?> chatWithLexi(
    String message,
    int standard, {
    int detectedLevel = 3,
    String weakness   = 'Grammar',
    int vocabScore    = 0,
    int grammarScore  = 0,
    int readingScore  = 0,
    int writingScore  = 0,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$supabaseUrl/chatbot'),
        headers: _headers,
        body: jsonEncode({
          'message':        message,
          'standard':       standard,
          'detected_level': detectedLevel,
          'weakness':       weakness,
          'vocab_score':    vocabScore,
          'grammar_score':  grammarScore,
          'reading_score':  readingScore,
          'writing_score':  writingScore,
        }),
      );
      if (response.statusCode == 200) {
        return jsonDecode(response.body)['reply'];
      }
      return 'Oops, something went wrong. Try again!';
    } catch (e) {
      debugPrint('Chat error: $e');
      return 'Network error. Check your connection!';
    }
  }

  // ── INITIAL ASSESSMENT ───────────────────────────────────────────────────
  Future<List<dynamic>?> generateAssessment(int standard) async {
    try {
      final responses = await Future.wait([
        generateVocabularyModule(standard, 'Daily Life',     'meaning'),
        generateVocabularyModule(standard, 'Animals',        'image'),
        generateGrammarModule(standard, ['Simple Present Tense'], 5),
        generateGrammarModule(standard, ['Nouns and Pronouns'],   5),
        generateReadingModule(standard, 'A Short Story'),
        generateWritingModule(standard, 'Everyday Tasks', 'completion'),
      ]);

      final List<dynamic> master = [];
      final types = [
        'Vocabulary', 'Vocabulary',
        'Grammar',    'Grammar',
        'Reading',    'Writing',
      ];

      for (int i = 0; i < responses.length; i++) {
        final r = responses[i];
        if (r == null) continue;

        // Vocab/Reading/Writing return Map with 'questions' key
        // Grammar returns List directly
        List<dynamic> questions = [];
        if (r is Map && r['questions'] != null) {
          questions = r['questions'] as List<dynamic>;
        } else if (r is List) {
          questions = r;
        }

        for (var q in questions) {
          q['type'] = types[i];
          master.add(q);
        }
      }

      master.shuffle();
      return master.isNotEmpty ? master : null;
    } catch (e) {
      debugPrint('Assessment error: $e');
      return null;
    }
  }
}