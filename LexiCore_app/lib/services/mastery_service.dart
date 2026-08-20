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
  /// sort_order, topic_group}]. Cached after first load.
  Future<List<Map<String, dynamic>>> taxonomy() async {
    _taxonomy ??= List<Map<String, dynamic>>.from(await _sb.from('sub_skills').select(
        'code, skill, name, standard_min, standard_max, sort_order, topic_group'));
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

  // ── WEEKLY SCHEDULE ────────────────────────────────────────────────────
  // Stored in `study_schedules.plan` (one row per user) so it's generated
  // ONCE per week and just read for the rest of it, instead of being
  // recomputed live on every visit. Regenerates when the stored plan is for
  // an earlier week, or on demand (e.g. right after the Saturday
  // assessment, once that exists) via regenerateWeeklySchedule().
  static const _weekdayNames = [
    'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'
  ];

  String _iso(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  DateTime _mondayOf(DateTime d) =>
      DateTime(d.year, d.month, d.day).subtract(Duration(days: d.weekday - 1));

  String _taskLabel(String skill, String subSkillName) {
    switch (skill) {
      case 'Writing':
        return 'Write: $subSkillName';
      case 'Reading':
        return 'Read & Answer: $subSkillName';
      case 'Vocabulary':
        return 'Learn: $subSkillName';
      default:
        return 'Practice: $subSkillName';
    }
  }

  Future<Map<String, dynamic>?> _storedPlan() async {
    final uid = _uid;
    if (uid == null) return null;
    final row = await _sb
        .from('study_schedules')
        .select()
        .eq('user_id', uid)
        .maybeSingle();
    return row?['plan'] as Map<String, dynamic>?;
  }

  /// This week's plan — generates and persists a fresh one if none exists
  /// yet or the stored one is for an earlier week.
  Future<Map<String, dynamic>?> getOrGenerateWeeklySchedule() async {
    final monday = _mondayOf(DateTime.now());
    final existing = await _storedPlan();
    if (existing != null &&
        existing['week_start'] == _iso(monday) &&
        existing['days'] is List) {
      return existing;
    }
    return regenerateWeeklySchedule();
  }

  /// Builds a brand-new plan for the CURRENT week and persists it. The
  /// weakest skill gets Monday + Wednesday (2 of 5 weekdays); each other
  /// skill gets one day — same weighting the schedule used before, just
  /// computed once and stored instead of recomputed on every visit. Saturday
  /// is reserved for the weekly assessment, Sunday for rest, per
  /// LexiCore_Learning_System_ELO_Specification.md section 6.
  Future<Map<String, dynamic>?> regenerateWeeklySchedule() async {
    final uid = _uid;
    if (uid == null) return null;
    final summary = await masterySummary();
    if (summary == null) return null;

    final standard = await studentStandard();
    final states = await loadMastery(standard);
    final tax = await taxonomy();
    final codeToSkill = {for (final t in tax) t['code'] as String: t['skill'] as String};
    final codeToName = {for (final t in tax) t['code'] as String: t['name'] as String};
    String skillOf(String c) => codeToSkill[c] ?? 'Grammar';

    final ordered = summary.avgRungBySkill.entries.toList()
      ..sort((a, b) => a.value.compareTo(b.value)); // weakest first
    final skills = ordered.map((e) => e.key).toList();
    while (skills.length < 4) {
      skills.add(skills.isEmpty ? 'Vocabulary' : skills.last);
    }
    const rankForDay = [0, 1, 0, 2, 3]; // Mon..Fri -> weakest/2nd/weakest/3rd/4th

    String? weakestFocusName;
    final days = <Map<String, dynamic>>[];
    for (var i = 0; i < 5; i++) {
      final skill = skills[rankForDay[i]];
      final skillStates =
          states.where((s) => skillOf(s.subSkillCode) == skill).toList();
      final day = <String, dynamic>{'day': _weekdayNames[i], 'skill': skill};
      if (skillStates.isNotEmpty) {
        final picked = AdaptivePolicy().selectNext(skillStates, skillOf);
        final name = codeToName[picked.subSkillCode] ?? picked.subSkillCode;
        day['sub_skill_code'] = picked.subSkillCode;
        day['task_label'] = _taskLabel(skill, name);
        if (skill == skills[0] && weakestFocusName == null) {
          weakestFocusName = name;
        }
      } else {
        day['task_label'] = 'Practice $skill';
      }
      days.add(day);
    }
    days.add({
      'day': 'Saturday',
      'type': 'assessment',
      'task_label': 'Weekly Assessment',
    });
    days.add({'day': 'Sunday', 'type': 'rest', 'task_label': 'Rest & Self-Revision'});

    final weakest = skills[0];
    final weekGoal = weakestFocusName != null
        ? 'This week\'s goal: improve your $weakest — focus on $weakestFocusName.'
        : 'This week\'s goal: improve your $weakest.';

    final plan = {
      'week_start': _iso(_mondayOf(DateTime.now())),
      'week_goal': weekGoal,
      'weakest_skill': weakest,
      'days': days,
      'completed_days': <String>[],
    };
    await _sb.from('study_schedules').upsert({
      'user_id': uid,
      'plan': plan,
      'created_at': DateTime.now().toIso8601String(),
    }, onConflict: 'user_id');
    return plan;
  }

  /// Today's entry from the (possibly freshly-generated) weekly plan.
  Future<Map<String, dynamic>?> getTodayTask() async {
    final plan = await getOrGenerateWeeklySchedule();
    if (plan == null) return null;
    final days = (plan['days'] as List).cast<Map<String, dynamic>>();
    final todayName = _weekdayNames[DateTime.now().weekday - 1];
    final match = days.where((d) => d['day'] == todayName);
    return match.isEmpty ? null : match.first;
  }

  /// Marks today's task done in the stored plan — call after the student
  /// finishes the session Today's Task launched.
  Future<void> markTodayTaskComplete() async {
    final uid = _uid;
    if (uid == null) return;
    final plan = await getOrGenerateWeeklySchedule();
    if (plan == null) return;
    final todayName = _weekdayNames[DateTime.now().weekday - 1];
    final completed = Set<String>.from(
        (plan['completed_days'] as List?)?.cast<String>() ?? const []);
    completed.add(todayName);
    plan['completed_days'] = completed.toList();
    await _sb.from('study_schedules').upsert({
      'user_id': uid,
      'plan': plan,
      'created_at': DateTime.now().toIso8601String(),
    }, onConflict: 'user_id');
  }

  // ── WEEKLY ASSESSMENT ──────────────────────────────────────────────────
  // Saturday's 40-question check (10/skill), per
  // LexiCore_Learning_System_ELO_Specification.md section 6/38 — stronger
  // evidence than ordinary practice, but routed through the exact same
  // generate -> grade -> skill_mastery pipeline via AdaptivePracticeScreen's
  // fixed-queue mode.

  /// Builds the 40-item queue: for each of the 4 skills, the 2 weakest
  /// sub-skills share 10 questions (via distributeQuestions — 5/5, or
  /// e.g. 6/4 if their current mastery differs enough to weight practice
  /// toward the weaker of the two... no, evenly split, simplicity over
  /// micro-weighting here). Skipped skills the student has no seeded
  /// sub-skills for yet are simply left out of the 40.
  Future<List<PracticeQueueItem>> buildWeeklyAssessmentQueue() async {
    final standard = await studentStandard();
    final states = await loadMastery(standard);
    final tax = await taxonomy();
    final codeToSkill = {for (final t in tax) t['code'] as String: t['skill'] as String};
    String skillOf(String c) => codeToSkill[c] ?? 'Grammar';

    final queue = <PracticeQueueItem>[];
    for (final skill in const ['Vocabulary', 'Grammar', 'Reading', 'Writing']) {
      final skillStates = states.where((s) => skillOf(s.subSkillCode) == skill).toList()
        ..sort((a, b) => a.masteredRung().compareTo(b.masteredRung())); // weakest first
      if (skillStates.isEmpty) continue;
      final picks = skillStates.take(2).map((s) => s.subSkillCode).toList();
      queue.addAll(distributeQuestions(picks, 10));
    }
    return queue;
  }

  /// Records one Saturday assessment's result — stronger evidence than
  /// ordinary practice (spec section 38), stored as a snapshot for
  /// progress-over-time, separate from the ongoing skill_mastery updates
  /// each answered item already made via the normal recordAttempt path.
  Future<void> saveWeeklyCheckin({
    required int itemsAnswered,
    required int itemsCorrect,
  }) async {
    final uid = _uid;
    if (uid == null) return;
    final summary = await masterySummary();
    await _sb.from('weekly_checkins').upsert({
      'user_id': uid,
      'week_start': _iso(_mondayOf(DateTime.now())),
      'overall': summary?.overall ?? 0,
      'avg_rung_by_skill': summary?.avgRungBySkill ?? <String, double>{},
      'items_answered': itemsAnswered,
      'items_correct': itemsCorrect,
      'taken_at': DateTime.now().toIso8601String(),
    }, onConflict: 'user_id,week_start');
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