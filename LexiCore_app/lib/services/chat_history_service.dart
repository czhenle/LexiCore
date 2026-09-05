import 'package:supabase_flutter/supabase_flutter.dart';

/// Cross-session persistence for the chatbot (`chatbot_messages` table).
/// Kept separate from SupabaseService the same way MasteryService is — this
/// is a self-contained concern with its own table.
class ChatHistoryService {
  final SupabaseClient _sb = Supabase.instance.client;
  String? get _uid => _sb.auth.currentUser?.id;

  /// The most recent messages, oldest first (ready to drop straight into
  /// the UI's message list). Empty for a brand-new student, or if not
  /// signed in — the screen falls back to its welcome message either way.
  Future<List<Map<String, dynamic>>> loadRecent({int limit = 50}) async {
    final uid = _uid;
    if (uid == null) return [];
    try {
      final rows = await _sb
          .from('chatbot_messages')
          .select('role, text, data, created_at')
          .eq('user_id', uid)
          .order('created_at', ascending: false)
          .limit(limit);
      return List<Map<String, dynamic>>.from(rows).reversed.toList();
    } catch (e) {
      return []; // never block the chat screen from opening over a history read failure
    }
  }

  /// Appends one message — fire-and-forget from the caller's side (a failed
  /// write shouldn't interrupt the conversation the student is having right
  /// now, it just means this one turn won't be there next time they open
  /// the chat).
  ///
  /// For a user message with a photo, `data` carries `{'image_base64': ...}`
  /// — reusing this same flexible field Lexi's structured replies already
  /// use, rather than a dedicated image column, so the photo is restored
  /// alongside the message on the next `loadRecent()` instead of only ever
  /// living in this session's in-memory list.
  Future<void> append({
    required String role, // 'user' | 'lexi'
    String? text,
    Map<String, dynamic>? data,
  }) async {
    final uid = _uid;
    if (uid == null) return;
    try {
      await _sb.from('chatbot_messages').insert({
        'user_id': uid,
        'role': role,
        'text': text,
        'data': data,
      });
    } catch (e) {
      // Swallowed deliberately — see append()'s doc comment.
    }
  }
}
