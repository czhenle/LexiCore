import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/learner_model.dart';

/// Persistence for the adaptive practice loop: loads the learner-model state,
/// saves ability updates, logs attempts, and exposes the taxonomy. Kept
/// separate from SupabaseService so the adaptive engine is self-contained.
class MasteryService {
  final SupabaseClient _sb = Supabase.instance.client;
  String? get _uid => _sb.auth.currentUser?.id;

  List<Map<String, dynamic>>? _taxonomy;
  Map<String, Map<int, String>>? _rungFormats;

  /// Sub-skill taxonomy: [{code, skill, name, standard_min, standard_max,
  /// sort_order}]. Cached after first load.
  Future<List<Map<String, dynamic>>> taxonomy() async {
    _taxonomy ??= List<Map<String, dynamic>>.from(await _sb
        .from('sub_skills')
        .select('code, skill, name, standard_min, standard_max, sort_order'));
    return _taxonomy!;
  }

  /// Rung -> format per skill, sourced from the `rung_formats` table (the
  /// single source of truth this mirrors — see AdaptivePracticeScreen's
  /// fallback constant for what to use if this table is empty/unreachable).
  /// Cached after first load; returns an empty map on any failure so callers
  /// can fall back without the practice loop dead-ending.
  Future<Map<String, Map<int, String>>> rungFormats() async {
    if (_rungFormats != null) return _rungFormats!;
    try {
      final rows = List<Map<String, dynamic>>.from(
          await _sb.from('rung_formats').select('skill, rung_no, format'));
      final map = <String, Map<int, String>>{};
      for (final r in rows) {
        final skill = r['skill'] as String;
        final rung = r['rung_no'] as int;
        final format = r['format'] as String;
        (map[skill] ??= {})[rung] = format;
      }
      _rungFormats = map;
      return map;
    } catch (_) {
      return {};
    }
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

  /// Interim Ability Count wiring for the legacy Vocabulary/Reading/Writing
  /// modules, which still pick topics from curriculum.dart rather than
  /// `sub_skills` directly (unlike Grammar). Maps the quiz's free-text topic
  /// onto the single best-matching sub-skill by word overlap (falling back to
  /// a deterministic hash so repeat attempts at the same unit keep landing on
  /// the same sub-skill, letting Elo actually converge), then replays every
  /// answered question's correctness through the same learner-model update
  /// used by adaptive practice. Superseded per-skill once that skill gets its
  /// own syllabus and moves onto `sub_skills` the way Grammar just did.
  Future<void> recordLegacyQuizCompletion({
    required String skill,
    required String topic,
    required List<bool> correctness,
    required int standard,
  }) async {
    if (correctness.isEmpty) return;
    final tax = (await taxonomy()).where((t) => t['skill'] == skill).toList();
    if (tax.isEmpty) return;
    final code = _pickSubSkillForTopic(topic, tax);
    final states = await loadMastery(standard);
    final m = states.firstWhere((s) => s.subSkillCode == code,
        orElse: () => MasteryState(subSkillCode: code, standard: standard));
    for (final correct in correctness) {
      final rung = m.nextTargetRung();
      m.recordAttempt(rungNumber: rung, correct: correct);
      await logAttempt(
        subSkillCode: code,
        rung: rung,
        format: 'legacy_mcq',
        itemDifficulty: EloConfig.itemDifficulty(standard, rung),
        correct: correct,
      );
    }
    await saveMastery(m);
  }

  /// Best sub-skill match for a free-text legacy topic string, by lowercase
  /// word overlap with each candidate's name; deterministic hash fallback
  /// (not random) if nothing overlaps at all.
  String _pickSubSkillForTopic(String topic, List<Map<String, dynamic>> tax) {
    final topicWords = topic.toLowerCase().split(RegExp(r'\W+')).toSet();
    Map<String, dynamic>? best;
    int bestScore = -1;
    for (final t in tax) {
      final nameWords =
          (t['name'] as String).toLowerCase().split(RegExp(r'\W+')).toSet();
      final score = topicWords.intersection(nameWords).length;
      if (score > bestScore) {
        bestScore = score;
        best = t;
      }
    }
    if (best != null && bestScore > 0) return best['code'] as String;
    final idx = topic.hashCode.abs() % tax.length;
    return tax[idx]['code'] as String;
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

  /// Aggregates the mastery map into per-skill averages, a strongest/weakest
  /// skill, and an overall progress fraction — for the Home dashboard.
  Future<MasterySummary?> masterySummary() async {
    final uid = _uid;
    if (uid == null) return null;
    final tax = await taxonomy();
    final codeToSkill = {
      for (final t in tax) t['code'] as String: t['skill'] as String
    };
    final rows = await _sb
        .from('skill_mastery')
        .select('sub_skill_code, mastered_rung')
        .eq('user_id', uid);
    final list = List<Map<String, dynamic>>.from(rows);
    if (list.isEmpty) return null;

    final sums = <String, double>{};
    final counts = <String, int>{};
    double totalRung = 0;
    int totalN = 0;
    for (final r in list) {
      final skill = codeToSkill[r['sub_skill_code']] ?? 'Other';
      final rung = ((r['mastered_rung'] as num?) ?? 0).toDouble();
      sums[skill] = (sums[skill] ?? 0) + rung;
      counts[skill] = (counts[skill] ?? 0) + 1;
      totalRung += rung;
      totalN += 1;
    }
    final avg = <String, double>{
      for (final s in sums.keys) s: sums[s]! / counts[s]!
    };
    final ordered = avg.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return MasterySummary(
      avgRungBySkill: avg,
      strongest: ordered.first.key,
      weakest: ordered.last.key,
      overall: totalN > 0 ? (totalRung / totalN) / 5.0 : 0.0,
    );
  }
}

/// A snapshot of a student's mastery for the Home dashboard.
class MasterySummary {
  final Map<String, double> avgRungBySkill; // skill -> mean mastered rung (0..5)
  final String strongest;
  final String weakest;
  final double overall; // 0..1

  MasterySummary({
    required this.avgRungBySkill,
    required this.strongest,
    required this.weakest,
    required this.overall,
  });
}