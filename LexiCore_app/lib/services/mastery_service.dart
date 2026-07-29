import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/learner_model.dart';

/// Persistence for the adaptive practice loop: loads the learner-model state,
/// saves ability updates, logs attempts, and exposes the taxonomy. Kept
/// separate from SupabaseService so the adaptive engine is self-contained.
class MasteryService {
  final SupabaseClient _sb = Supabase.instance.client;
  String? get _uid => _sb.auth.currentUser?.id;

  List<Map<String, dynamic>>? _taxonomy;

  /// Sub-skill taxonomy: [{code, skill, name}]. Cached after first load.
  Future<List<Map<String, dynamic>>> taxonomy() async {
    _taxonomy ??= List<Map<String, dynamic>>.from(
        await _sb.from('sub_skills').select('code, skill, name'));
    return _taxonomy!;
  }

  /// The student's declared standard (defaults to 3 if missing).
  Future<int> studentStandard() async {
    final uid = _uid;
    if (uid == null) return 3;
    final row = await _sb
        .from('student_profiles')
        .select('standard')
        .eq('user_id', uid)
        .maybeSingle();
    return (row?['standard'] as int?) ?? 3;
  }

  /// Loads one MasteryState per seeded sub-skill for this student.
  Future<List<MasteryState>> loadMastery(int standard) async {
    final uid = _uid;
    if (uid == null) return [];
    final rows = await _sb.from('skill_mastery').select().eq('user_id', uid);
    return List<Map<String, dynamic>>.from(rows)
        .map((r) => MasteryState(
              subSkillCode: r['sub_skill_code'] as String,
              standard: standard,
              ability: (r['ability'] as num).toDouble(),
              attempts: (r['attempts'] as int?) ?? 0,
            ))
        .toList();
  }

  /// Persists a single updated MasteryState (upsert on the composite PK).
  Future<void> saveMastery(MasteryState m) async {
    final uid = _uid;
    if (uid == null) return;
    await _sb.from('skill_mastery').upsert(m.toRow(uid));
  }

  /// Appends one answered item to the event log.
  Future<void> logAttempt({
    required String subSkillCode,
    required int rung,
    required String format,
    required double itemDifficulty,
    required bool correct,
    String? response,
  }) async {
    final uid = _uid;
    if (uid == null) return;
    await _sb.from('item_attempts').insert({
      'user_id': uid,
      'sub_skill_code': subSkillCode,
      'rung_no': rung,
      'format': format,
      'item_difficulty': itemDifficulty,
      'is_correct': correct,
      'student_response': response,
    });
  }

  /// Records one checkpoint (re-assessment) result. This table is also the
  /// student's progress-over-time history.
  Future<void> saveCheckpoint({
    required String subSkillCode,
    required int rung,
    required double preAbility,
    required double postAbility,
    required bool passed,
  }) async {
    final uid = _uid;
    if (uid == null) return;
    await _sb.from('checkpoints').insert({
      'user_id': uid,
      'sub_skill_code': subSkillCode,
      'rung_no': rung,
      'pre_ability': preAbility,
      'post_ability': postAbility,
      'passed': passed,
    });
  }

  /// Highest rung each sub-skill has PASSED a checkpoint for. Persists the
  /// gate across sessions so a confirmed rung stays confirmed.
  Future<Map<String, int>> confirmedRungs() async {
    final uid = _uid;
    if (uid == null) return {};
    final rows = await _sb
        .from('checkpoints')
        .select('sub_skill_code, rung_no')
        .eq('user_id', uid)
        .eq('passed', true);
    final map = <String, int>{};
    for (final r in List<Map<String, dynamic>>.from(rows)) {
      final code = r['sub_skill_code'] as String;
      final rung = (r['rung_no'] as int?) ?? 0;
      if (rung > (map[code] ?? 0)) map[code] = rung;
    }
    return map;
  }
}