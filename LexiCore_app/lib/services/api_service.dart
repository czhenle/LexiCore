import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

// NOTE ON THE `Response` NAME: both package:http and package:supabase_flutter
// (via its own dependencies) define a class named `Response`. Both imports
// above are aliased (`as http`, `as sb`) specifically to avoid that name
// clashing — but as extra insurance, every http.Response below is given an
// EXPLICIT type (`final http.Response x = ...`) instead of `final x = ...`.
// Explicit typing removes any possibility of the analyzer picking the wrong
// `Response` class, regardless of import order or analyzer caching.

class ApiService {
  static const String supabaseUrl =
      'https://cldngeqtuyxwuvtsaocm.supabase.co/functions/v1';
  static const String publishableKey =
      'sb_publishable_NJvrBZXKXKoeGp4e-GzI3A_yIkohgjh';

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $publishableKey',
      };

  // ── READING MODULE ───────────────────────────────────────────────────────
  Future<Map<String, dynamic>?> generateReadingModule(
      int level, String topic) async {
    try {
      final http.Response response = await http.post(
        Uri.parse('$supabaseUrl/reading'),
        headers: _headers,
        body: jsonEncode({
          'standard': level,
          'topic': topic,
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

  // ── ARTICLE GENERATOR ───────────────────────────────────────────────────
  Future<Map<String, dynamic>?> generateArticle(
    int standard,
    String grade,
    String rate,
    int? vocabularyScore,
    int? grammarScore,
    int? readingScore,
    int? writingScore, {
    bool force = false,
  }) async {
    try {
      // This function authenticates the student via their session (it calls
      // supabase.auth.getUser() server-side), so it must be invoked through
      // the Supabase client — not the anon-key http.post used elsewhere —
      // so the student's login token is attached automatically.
      final sb.FunctionResponse res =
          await sb.Supabase.instance.client.functions.invoke(
        'article',
        body: {
          'standard': standard,
          'grade': grade,
          'rate': rate,
          if (vocabularyScore != null) 'vocabulary_score': vocabularyScore,
          if (grammarScore != null) 'grammar_score': grammarScore,
          if (readingScore != null) 'reading_score': readingScore,
          if (writingScore != null) 'writing_score': writingScore,
          if (force) 'force': true,
        },
      );
      final data = res.data;
      if (data is Map) return Map<String, dynamic>.from(data);
      debugPrint('Article error: unexpected response shape: $data');
      return null;
    } on sb.FunctionException catch (e) {
      // Non-2xx responses (e.g. 429 when the daily regeneration cap is hit)
      // surface as an exception, not a normal result — unwrap it so the UI
      // still gets the {success:false, error, message, article} body the
      // function actually sent, instead of losing it.
      final details = e.details;
      Map<String, dynamic>? body;
      if (details is Map) {
        body = Map<String, dynamic>.from(details);
      } else if (details is String) {
        try {
          final decoded = jsonDecode(details);
          if (decoded is Map) body = Map<String, dynamic>.from(decoded);
        } catch (_) {
          // not JSON — fall through to the generic body below
        }
      }
      return body ??
          {
            'success': false,
            'error': 'ARTICLE_ERROR',
            'message': 'Could not load the story right now.',
          };
    } catch (e) {
      debugPrint('Article network error: $e');
      return null;
    }
  }

  // ── AI CHATBOT ───────────────────────────────────────────────────────────
  Future<Map<String, dynamic>> chatWithLexi(
    String message,
    int standard, {
    String weakness = 'Grammar',
    int vocabScore = 0,
    int grammarScore = 0,
    int readingScore = 0,
    int writingScore = 0,
    String? imageBase64,
    List<Map<String, String>> history = const [],
    String mode = 'auto',
  }) async {
    try {
      final http.Response response = await http.post(
        Uri.parse('$supabaseUrl/chatbot'),
        headers: _headers,
        body: jsonEncode({
          'message': message,
          'standard': standard,
          'weakness': weakness,
          'vocab_score': vocabScore,
          'grammar_score': grammarScore,
          'reading_score': readingScore,
          'writing_score': writingScore,
          'history': history,
          'mode': mode,
          if (imageBase64 != null) 'image': imageBase64,
        }),
      );
      // 400 also carries a proper `reply` (e.g. "that message is a little too
      // long") — unwrap it too, instead of replacing the server's specific,
      // child-friendly guidance with a generic error.
      if (response.statusCode == 200 || response.statusCode == 400) {
        final reply = jsonDecode(response.body)['reply'];
        if (reply is Map) return Map<String, dynamic>.from(reply);
        if (reply != null) {
          // Older/string replies -> wrap so the UI can always render a type.
          return {'type': 'simple_answer', 'text': reply.toString()};
        }
      }
      debugPrint('Chat error [${response.statusCode}]: ${response.body}');
      return {
        'type': 'simple_answer',
        'text': 'Oops, something went wrong. Try again!'
      };
    } catch (e) {
      debugPrint('Chat error: $e');
      return {
        'type': 'simple_answer',
        'text': 'Network error. Check your connection!'
      };
    }
  }
}