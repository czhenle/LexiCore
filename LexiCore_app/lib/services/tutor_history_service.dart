import 'package:supabase_flutter/supabase_flutter.dart';

/// Cross-session persistence for the tutor (hint-helper)'s per-question
/// conversation — kept in its own table (`tutor_messages`), deliberately
/// separate from ChatHistoryService's `chatbot_messages`. See the
/// tutor_messages migration for why: the tutor's history is scoped to ONE
/// question at a time, not one long running thread.
class TutorHistoryService {
  final SupabaseClient _sb = Supabase.instance.client;
  String? get _uid => _sb.auth.currentUser?.id;

  /// A stable-enough key for "this served item" — items are generated ad hoc
  /// and have no other id, but this is stable for as long as the student is
  /// looking at the same one (sub_skill + a hash of its question text).
  String itemKey(Map<String, dynamic> item) {
    final subSkill = item['sub_skill']?.toString() ?? 'x';
    final question = item['question']?.toString() ?? '';
    return '$subSkill::${question.hashCode}';
  }

  /// This item's hint conversation so far, oldest first. Empty for a
  /// question the student hasn't asked the tutor about yet, or if not
  /// signed in.
  Future<List<Map<String, dynamic>>> loadForItem(String itemKey) async {
    final uid = _uid;
    if (uid == null) return [];
    try {
      final rows = await _sb
          .from('tutor_messages')
          .select('role, text, created_at')
          .eq('user_id', uid)
          .eq('item_key', itemKey)
          .order('created_at', ascending: true)
          .limit(30);
      return List<Map<String, dynamic>>.from(rows);
    } catch (e) {
      return []; // never block the tutor sheet from opening over a read failure
    }
  }

  /// Appends one turn — fire-and-forget, same reasoning as
  /// ChatHistoryService.append: a failed write shouldn't interrupt the hint
  /// the student is getting right now.
  Future<void> append({
    required String itemKey,
    required String role, // 'user' | 'assistant'
    required String text,
  }) async {
    final uid = _uid;
    if (uid == null) return;
    try {
      await _sb.from('tutor_messages').insert({
        'user_id': uid,
        'item_key': itemKey,
        'role': role,
        'text': text,
      });
    } catch (e) {
      // Swallowed deliberately — see append()'s doc comment above.
    }
  }
}
