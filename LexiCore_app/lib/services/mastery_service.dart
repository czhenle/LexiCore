import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/learner_model.dart';
import 'api_service.dart';

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

  /// The onboarding-declared daily study time (student_profiles.study_time,
  /// one of "15 minutes"/"30 minutes"/"45 minutes"/"1 hour"), in minutes.
  /// Defaults to 20 if missing/unparseable.
  Future<int> studentStudyMinutes() async {
    final uid = _uid;
    if (uid == null) return 20;
    final row = await _sb
        .from('student_profiles')
        .select('study_time')
        .eq('user_id', uid)
        .maybeSingle();
    return _parseStudyMinutes(row?['study_time'] as String?);
  }

  int _parseStudyMinutes(String? label) {
    switch (label) {
      case '15 minutes':
        return 15;
      case '30 minutes':
        return 30;
      case '45 minutes':
        return 45;
      case '1 hour':
        return 60;
      default:
        return 20;
    }
  }

  /// How many questions Today's Task (Vocabulary/Grammar only — Reading and
  /// Writing route to their own real module with its own question count, so
  /// this is never used for either) should queue up, given the student's
  /// declared daily study time. Deliberately does NOT try to fill the whole
  /// budget: a 60-minute student answering ~70 back-to-back items would burn
  /// out long before finishing, and the whole point of having 4 modules is
  /// that a student moves between them, not grinds one skill for an entire
  /// session. Today's Task claims roughly 60% of the budget at a blended
  /// ~50s/item pace (reading + answering + the occasional tutor hint) —
  /// the remaining ~40% is deliberately left unclaimed, for the other
  /// modules (or the day's own scheduled skill) rather than more of this
  /// one. Clamped to [5, 15] so a 15-minute student still gets a real
  /// session and a 60-minute student isn't handed an exhausting wall of
  /// questions either way.
  int recommendedQueueCount(int studyMinutes) {
    const secondsPerItem = 50;
    const todaysTaskShare = 0.6;
    final budgetSeconds = studyMinutes * 60 * todaysTaskShare;
    final count = (budgetSeconds / secondsPerItem).round();
    return count.clamp(5, 15);
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

  /// Safety net: if `skill_mastery` is somehow still empty for this student
  /// (e.g. the one-shot seeding call right after the pre-assessment hit a
  /// transient failure), re-seed it from their persisted `assessment_results`
  /// row instead of leaving progress/Today's Task/the schedule permanently
  /// empty until they happen to complete a practice quiz on their own —
  /// masterySummary()/generateStudyPlan() both need at least one skill_
  /// mastery row to produce anything at all. A no-op once skill_mastery has
  /// any rows. Called from HomeScreen's load, right before those.
  Future<void> ensureMasterySeeded() async {
    final uid = _uid;
    if (uid == null) return;
    try {
      final existing = await _sb
          .from('skill_mastery')
          .select('sub_skill_code')
          .eq('user_id', uid);
      final existingCodes = Set<String>.from(
          (existing as List).map((r) => r['sub_skill_code'] as String));

      final standard = await studentStandard();
      final results = await _sb
          .from('assessment_results')
          .select('vocabulary_score, grammar_score, reading_score, writing_score')
          .eq('user_id', uid)
          .maybeSingle();

      final scores = <String, int>{
        'Vocabulary': (results?['vocabulary_score'] as int?) ?? 50,
        'Grammar': (results?['grammar_score'] as int?) ?? 50,
        if (results?['reading_score'] != null)
          'Reading': results!['reading_score'] as int,
        if (results?['writing_score'] != null)
          'Writing': results!['writing_score'] as int,
      };

      // Seed whichever sub-skills this student DOESN'T have a row for yet —
      // not just "the table is completely empty". That used to be the only
      // check, so a sub-skill added to the taxonomy AFTER a student's
      // account already had some mastery rows (Reading/Writing's mode-based
      // sub-skills, added mid-project) never got seeded at all: the account
      // already had rows, so this whole function short-circuited forever,
      // silently dropping that skill from the weekly schedule and the
      // Weekly Assessment for good. Catching up the gap here means any
      // account self-heals the next time Home loads.
      final subSkills = await taxonomy();
      final missing =
          subSkills.where((s) => !existingCodes.contains(s['code'])).toList();
      if (missing.isEmpty) return;

      final codeToSkill = {for (final s in subSkills) s['code'] as String: s['skill'] as String};
      final existingSkills = existingCodes.map((c) => codeToSkill[c]).toSet();
      final newSkills = missing
          .map((s) => s['skill'] as String)
          .where((skill) => !existingSkills.contains(skill))
          .toSet();

      final rows = missing.map((s) {
        final skill = s['skill'] as String;
        final score = scores[skill] ?? 50; // neutral default if missing
        final m = MasteryState(
          subSkillCode: s['code'] as String,
          standard: standard,
          ability: EloConfig.abilityFromScore(score, standard),
        );
        return m.toRow(uid);
      }).toList();

      await _sb.from('skill_mastery').upsert(rows);

      // A skill that just got its FIRST sub-skill coverage (Reading/Writing
      // catching up on an older account, above) won't show up in an
      // already-stored weekly schedule until that plan naturally expires —
      // up to 30 days. Force a fresh one now so the schedule (and the
      // Weekly Assessment, which reads from it) picks the new skill up
      // immediately instead of silently staying 2-skill-only for weeks.
      if (newSkills.isNotEmpty) {
        await generateStudyPlan();
      }
    } catch (e) {
      // Never block Home from loading over this — worst case, progress
      // just stays empty for one more visit and this retries next time.
      debugPrint('ensureMasterySeeded failed: $e');
    }
  }

  /// Appends one answered item to the event log.
  Future<void> logAttempt({
    required String subSkillCode,
    required int rung,
    required String format,
    required double itemDifficulty,
    required bool correct,
    String? response,
    String? question,
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
      'question': question,
    });
  }

  /// The last few question texts served for this sub-skill — fed into
  /// `generate` as `recent_questions` (same spirit as `recent_errors`) so it
  /// doesn't keep regenerating the same question.
  Future<List<String>> recentQuestions(String subSkillCode, {int limit = 4}) async {
    final uid = _uid;
    if (uid == null) return [];
    final rows = await _sb
        .from('item_attempts')
        .select('question')
        .eq('user_id', uid)
        .eq('sub_skill_code', subSkillCode)
        .order('created_at', ascending: false)
        .limit(limit);
    return List<Map<String, dynamic>>.from(rows)
        .map((r) => r['question'] as String?)
        .whereType<String>()
        .where((q) => q.trim().isNotEmpty)
        .toList();
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

  // ── STUDY PLAN ─────────────────────────────────────────────────────────
  // Stored in `study_schedules.plan` (one row per user), generated ONCE for
  // the student's chosen duration (student_profiles.plan_duration_days —
  // 7/14/30 days, picked at onboarding, default 7) instead of recomputed
  // every Monday. Regenerates only when no plan is stored yet, or the
  // stored plan has run its full length — and on demand right after the
  // assessment/self-evaluation, via generateStudyPlan(). Each week within
  // the plan repeats the same Mon-Fri-task/Sat-assessment/Sun-rest pattern
  // per LexiCore_Learning_System_ELO_Specification.md section 6.
  static const _weekdayNames = [
    'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'
  ];

  /// Today's date as the same 'yyyy-MM-dd' string plan days/completed_days
  /// are keyed by — exposed publicly so callers can compare against those
  /// without duplicating the format themselves.
  String todayIso() => _iso(DateTime.now());

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

  /// One week's milestone card text — what's actually scheduled that week
  /// (`subSkillNames`) and what the student should aim to get out of it,
  /// so the plan gives a sense of weekly progress/payoff instead of just a
  /// flat day list and one overall goal line.
  String _weekMilestone(int weekNumber, String skill, List<String> subSkillNames) {
    if (subSkillNames.isEmpty) {
      return 'Week $weekNumber: keep practising — your plan fills in more detail as you go.';
    }
    final list = subSkillNames.length == 1
        ? subSkillNames.first
        : '${subSkillNames.sublist(0, subSkillNames.length - 1).join(', ')} and ${subSkillNames.last}';
    return "Week $weekNumber: you'll work mostly on $skill — $list. By the end of the week, "
        'aim to feel noticeably more confident with these.';
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

  /// The student's chosen plan length (7/14/30), defaulting to 7 for any
  /// other stored value (shouldn't happen, but never dead-end the loop).
  Future<int> _planDurationDays() async {
    final uid = _uid;
    if (uid == null) return 7;
    final row = await _sb
        .from('student_profiles')
        .select('plan_duration_days')
        .eq('user_id', uid)
        .maybeSingle();
    final d = row?['plan_duration_days'] as int?;
    return (d == 7 || d == 14 || d == 30) ? d! : 7;
  }

  /// The current study plan — generates and persists a fresh one if none
  /// exists yet, or the stored one has run past its length.
  Future<Map<String, dynamic>?> getOrGenerateStudyPlan() async {
    final existing = await _storedPlan();
    if (existing != null && existing['days'] is List) {
      final start = DateTime.tryParse(existing['plan_start'] as String? ?? '');
      final length = existing['plan_length_days'] as int?;
      final days = (existing['days'] as List).cast<Map<String, dynamic>>();
      // Belt-and-braces on top of the plan_start/length expiry check below:
      // whatever the reason (a stale row from earlier testing, a bad
      // plan_start, ...), a plan that doesn't contain TODAY anywhere in its
      // day list is definitely not the plan to show — regenerate rather
      // than let the student see day cards dated months in the past.
      final containsToday = days.any((d) => d['date'] == _iso(DateTime.now()));
      if (start != null && length != null && containsToday &&
          DateTime.now().isBefore(start.add(Duration(days: length)))) {
        return existing;
      }
    }
    return generateStudyPlan();
  }

  /// Builds a brand-new plan spanning the student's chosen duration and
  /// persists it, starting from TODAY — not the Monday of whatever week
  /// generation happens to fall in (that used to mean generating on a
  /// Friday still backdated day 1 to 4 days ago). Every 7-day cycle from
  /// that start date follows the same pattern: the weakest skill gets days
  /// 1 + 3, one other skill each of days 2/4/5, day 6 = Weekly Assessment,
  /// day 7 = rest — relative to the student's own start date, so someone
  /// registering on a Saturday gets their assessment/rest on the following
  /// Thursday/Friday, not a calendar Saturday/Sunday. Sub-skill picks cycle
  /// weakest-first through each skill's sub-skills cycle over cycle
  /// (instead of repeating the exact same pick every time) so a 14/30-day
  /// plan actually varies.
  Future<Map<String, dynamic>?> generateStudyPlan() async {
    final uid = _uid;
    if (uid == null) return null;
    final summary = await masterySummary();
    if (summary == null) return null;

    final durationDays = await _planDurationDays();
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
    // Positions 0-4 of each 7-day cycle -> weakest/2nd/weakest/3rd/4th.
    const rankForDay = [0, 1, 0, 2, 3];

    // Per-skill sub-skill ranking (weakest first) — reused across cycles
    // with a round-robin cycle for variety instead of the same pick every
    // time.
    final statesBySkill = <String, List<MasteryState>>{
      for (final skill in skills.toSet())
        skill: (states.where((s) => skillOf(s.subSkillCode) == skill).toList()
          ..sort((a, b) => a.masteredRung().compareTo(b.masteredRung()))),
    };

    final now = DateTime.now();
    final planStart = DateTime(now.year, now.month, now.day); // today, time stripped
    String? weakestFocusName;
    final days = <Map<String, dynamic>>[];
    // Which sub-skill names actually get touched in each 7-day cycle — the
    // weekly milestones below are built from this, since it's what varies
    // week to week (the round-robin sub-skill pick); the skill PRIORITY
    // itself (weakest/2nd/3rd/4th) is fixed for the whole plan.
    final subSkillsByCycle = <int, Set<String>>{};

    for (var d = 0; d < durationDays; d++) {
      final date = planStart.add(Duration(days: d));
      final dayName = _weekdayNames[date.weekday - 1]; // real calendar weekday, for display
      final posInCycle = d % 7; // 0-4 task, 5 assessment, 6 rest — relative to planStart
      final cycle = d ~/ 7; // which 7-day cycle, for the sub-skill round-robin

      if (posInCycle == 5) {
        days.add({
          'date': _iso(date),
          'day_name': dayName,
          'type': 'assessment',
          'task_label': 'Weekly Assessment',
        });
        continue;
      }
      if (posInCycle == 6) {
        days.add({
          'date': _iso(date),
          'day_name': dayName,
          'type': 'rest',
          'task_label': 'Rest & Self-Revision',
        });
        continue;
      }

      final skill = skills[rankForDay[posInCycle]];
      final skillStates = statesBySkill[skill] ?? const <MasteryState>[];
      final day = <String, dynamic>{
        'date': _iso(date),
        'day_name': dayName,
        'skill': skill,
      };
      if (skillStates.isNotEmpty) {
        final picked = skillStates[cycle % skillStates.length];
        final name = codeToName[picked.subSkillCode] ?? picked.subSkillCode;
        day['sub_skill_code'] = picked.subSkillCode;
        day['task_label'] = _taskLabel(skill, name);
        (subSkillsByCycle[cycle] ??= {}).add(name);
        if (skill == skills[0] && weakestFocusName == null) {
          weakestFocusName = name;
        }
      } else {
        day['task_label'] = 'Practice $skill';
      }
      days.add(day);
    }

    final weakest = skills[0];
    var planGoal = weakestFocusName != null
        ? 'Your $durationDays-day goal: improve your $weakest — focus on $weakestFocusName.'
        : 'Your $durationDays-day goal: improve your $weakest.';

    // One card per 7-day cycle — template-built to start with, so it always
    // reads correctly and matches exactly what's actually scheduled that
    // week regardless of what happens below. The wording may then get a
    // best-effort AI rewrite (see ApiService().personalizeSchedule below);
    // the WEEK'S CONTENT (focus skill, sub-skills touched) is decided here
    // and only here, never by the AI pass.
    final weekCount = (durationDays / 7).ceil();
    final weeks = [
      for (var w = 0; w < weekCount; w++)
        {
          'week_number': w + 1,
          'focus_skill': weakest,
          'sub_skills_touched': (subSkillsByCycle[w] ?? const <String>{}).toList(),
          'milestone': _weekMilestone(
              w + 1, weakest, (subSkillsByCycle[w] ?? const <String>{}).toList()),
        },
    ];

    // Best-effort AI wording pass: LexiCore's own logic above has already
    // decided EVERYTHING that matters (which skill/sub-skill lands on which
    // day, week boundaries, assessment/rest placement) — this call only
    // rewrites the task_label/milestone/plan_goal TEXT into warmer wording
    // for the child's Standard. Every template string computed above is a
    // complete, correct plan on its own, so any failure/timeout here just
    // leaves them exactly as they are — never blocks or corrupts the plan.
    try {
      final taskDays = days.where((d) => d['type'] == null).toList();
      final personalized = await ApiService().personalizeSchedule(
        standard: standard,
        weakestSkill: weakest,
        planGoalTemplate: planGoal,
        days: [
          for (final d in taskDays)
            {
              'date': d['date'],
              'skill': d['skill'],
              'sub_skill_name': codeToName[d['sub_skill_code']] ?? d['skill'],
              'template': d['task_label'],
            },
        ],
        weeks: [
          for (final w in weeks)
            {
              'week_number': w['week_number'],
              'focus_skill': w['focus_skill'],
              'sub_skills_touched': w['sub_skills_touched'],
              'template': w['milestone'],
            },
        ],
      );
      if (personalized != null) {
        final dayLabels =
            (personalized['day_labels'] as Map?)?.cast<String, dynamic>() ?? {};
        for (final d in taskDays) {
          final label = dayLabels[d['date']];
          if (label is String && label.trim().isNotEmpty) d['task_label'] = label;
        }
        final weekMilestones =
            (personalized['week_milestones'] as Map?)?.cast<String, dynamic>() ?? {};
        for (final w in weeks) {
          final milestone = weekMilestones['${w['week_number']}'];
          if (milestone is String && milestone.trim().isNotEmpty) {
            w['milestone'] = milestone;
          }
        }
        final goal = personalized['plan_goal'];
        if (goal is String && goal.trim().isNotEmpty) planGoal = goal;
      }
    } catch (e) {
      debugPrint('Schedule wording personalization skipped: $e');
      // days/weeks/planGoal are untouched — the template plan above stands.
    }

    final plan = {
      'plan_start': _iso(planStart),
      'plan_length_days': durationDays,
      'plan_goal': planGoal,
      'weakest_skill': weakest,
      'days': days,
      'weeks': weeks,
      'completed_days': <String>[],
    };
    await _sb.from('study_schedules').upsert({
      'user_id': uid,
      'plan': plan,
      'created_at': DateTime.now().toIso8601String(),
    }, onConflict: 'user_id');
    return plan;
  }

  /// Today's entry from the (possibly freshly-generated) study plan,
  /// matched by actual calendar date rather than weekday name — a
  /// 14/30-day plan spans multiple weeks, so weekday-name matching would
  /// collide.
  Future<Map<String, dynamic>?> getTodayTask() async {
    final plan = await getOrGenerateStudyPlan();
    if (plan == null) return null;
    final days = (plan['days'] as List).cast<Map<String, dynamic>>();
    final todayIso = _iso(DateTime.now());
    final match = days.where((d) => d['date'] == todayIso);
    return match.isEmpty ? null : match.first;
  }

  /// Marks today's task done in the stored plan — call after the student
  /// finishes the session Today's Task launched.
  Future<void> markTodayTaskComplete() async {
    final uid = _uid;
    if (uid == null) return;
    final plan = await getOrGenerateStudyPlan();
    if (plan == null) return;
    final todayIso = _iso(DateTime.now());
    final completed = Set<String>.from(
        (plan['completed_days'] as List?)?.cast<String>() ?? const []);
    completed.add(todayIso);
    plan['completed_days'] = completed.toList();
    await _sb.from('study_schedules').upsert({
      'user_id': uid,
      'plan': plan,
      'created_at': DateTime.now().toIso8601String(),
    }, onConflict: 'user_id');
  }

  // ── WEEKLY ASSESSMENT ──────────────────────────────────────────────────
  // A weekly check-in covering all 4 skills, batch-generated upfront the
  // same way the pre-assessment is (the whole thing is prepared in one go,
  // not fetched item-by-item as the student answers — nothing here needs
  // live adaptivity, it's a review of a week that's already happened).
  // Grounded in what was ACTUALLY scheduled this week (see
  // _thisCycleSubSkills) rather than an abstract weakest-sub-skill guess,
  // so it reads as "did you learn what we covered", not a generic quiz.
  // See WeeklyAssessmentScreen for how this plan is turned into a session:
  // Vocabulary/Grammar/Reading batch into one quiz screen; Writing (if
  // scheduled) is a separate composition task launched right after, since
  // it needs its own submit/timer UI a quiz list doesn't have.

  /// Sub-skill codes actually scheduled in the CURRENT 7-day cycle of the
  /// stored study plan, grouped by skill — empty map if there's no stored
  /// plan yet, or today isn't in it (a fresh/expired plan), in which case
  /// callers fall back to ranking by mastered rung instead.
  Future<Map<String, List<String>>> _thisCycleSubSkills() async {
    final plan = await getOrGenerateStudyPlan();
    if (plan == null) return {};
    final days = (plan['days'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
    final todayIso = _iso(DateTime.now());
    final todayIndex = days.indexWhere((d) => d['date'] == todayIso);
    if (todayIndex == -1) return {};
    final cycleStart = (todayIndex ~/ 7) * 7;
    final cycleDays = days.skip(cycleStart).take(7);
    final tax = await taxonomy();
    final codeToSkill = {for (final t in tax) t['code'] as String: t['skill'] as String};

    final result = <String, List<String>>{};
    for (final d in cycleDays) {
      final code = d['sub_skill_code'] as String?;
      if (code == null) continue;
      final skill = codeToSkill[code] ?? (d['skill'] as String?) ?? 'Grammar';
      final list = result.putIfAbsent(skill, () => []);
      if (!list.contains(code)) list.add(code);
    }
    return result;
  }

  /// Generates the ONE passage the weekly quiz's Reading questions ground
  /// themselves in — same `generate(format:"passage")` call
  /// ReadingModuleScreen makes, factored out here so WeeklyAssessmentScreen
  /// doesn't need to duplicate it. Returns null on any failure — the caller
  /// just drops Reading from that week's quiz rather than blocking the
  /// whole thing on one passage call.
  Future<({String title, String body})?> generatePassage(int standard) async {
    try {
      final res = await _sb.functions.invoke('generate', body: {
        'skill': 'Reading',
        'sub_skill': 'reading.comprehension',
        'sub_skill_name': 'Reading Comprehension',
        'format': 'passage',
        'standard': standard,
        'rung': 1,
        'target_difficulty': 0,
        'recent_errors': <String>[],
      });
      final passage = res.data is Map ? (res.data as Map)['passage'] : null;
      if (passage is Map && passage['body'] is String && (passage['body'] as String).trim().isNotEmpty) {
        return (
          title: (passage['title'] as String?) ?? 'Reading Passage',
          body: passage['body'] as String,
        );
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Builds this week's check-in: which questions to batch-generate for the
  /// quiz, and which composition task (if any) to follow it with.
  Future<WeeklyAssessmentPlan> buildWeeklyAssessmentPlan() async {
    final standard = await studentStandard();
    final states = await loadMastery(standard);
    final tax = await taxonomy();
    final codeToSkill = {for (final t in tax) t['code'] as String: t['skill'] as String};
    String skillOf(String c) => codeToSkill[c] ?? 'Grammar';

    final scheduled = await _thisCycleSubSkills();
    List<String> picksFor(String skill, {int take = 2}) {
      final fromPlan = scheduled[skill];
      if (fromPlan != null && fromPlan.isNotEmpty) return fromPlan.take(take).toList();
      final ranked = states.where((s) => skillOf(s.subSkillCode) == skill).toList()
        ..sort((a, b) => a.masteredRung().compareTo(b.masteredRung())); // weakest first
      return ranked.take(take).map((s) => s.subSkillCode).toList();
    }

    final dbFormats = await rungFormats();
    String ladderFormat(String skill, int rungNo) {
      final fromDb = dbFormats[skill]?[rungNo];
      if (fromDb != null) return fromDb;
      final list = rungFormatFallback[skill] ?? rungFormatFallback['Grammar']!;
      return list[(rungNo - 1).clamp(0, 4)];
    }

    final vocabGrammarQueue = <PracticeQueueItem>[];
    // Vocabulary/Grammar: a mix of a choice format (rung 1's, the ladder's
    // easiest recognition format) and an open format (rung 5's, the
    // ladder's production format) per sub-skill — a review check should see
    // how a student does at BOTH recognising and producing, not just
    // whatever their current confirmed rung happens to pin as "the" format.
    for (final skill in const ['Vocabulary', 'Grammar']) {
      final picks = picksFor(skill);
      if (picks.isEmpty) continue;
      final choiceFormat = ladderFormat(skill, 1);
      final openFormat = ladderFormat(skill, 5);
      final perSubSkill = (6 / picks.length).round().clamp(2, 6);
      final openCount = (perSubSkill / 2).floor().clamp(1, perSubSkill - 1);
      for (final code in picks) {
        vocabGrammarQueue.add(PracticeQueueItem(code, perSubSkill - openCount, format: choiceFormat));
        vocabGrammarQueue.add(PracticeQueueItem(code, openCount, format: openFormat));
      }
    }

    // Reading: a quite fixed way of answering (MCQ, passage-grounded) —
    // same shape as the Reading module itself, just shorter, and (see
    // WeeklyAssessmentScreen) shown the same way too: the passage on its
    // own screen first, THEN these questions — never generated/served
    // without the student having seen it. Included whenever Reading was
    // scheduled this week, or the student has any Reading history at all
    // (a plan-less fallback).
    final readingQueue = <PracticeQueueItem>[];
    final hasReadingHistory = states.any((s) => skillOf(s.subSkillCode) == 'Reading');
    final includeReading = (scheduled['Reading']?.isNotEmpty ?? false) || hasReadingHistory;
    if (includeReading) {
      if (standard >= 5) {
        readingQueue.add(const PracticeQueueItem('reading.comprehension', 3, format: 'mcq_literal'));
        readingQueue.add(const PracticeQueueItem('reading.comprehension', 1, format: 'mcq_inference'));
      } else {
        readingQueue.add(const PracticeQueueItem('reading.comprehension', 4, format: 'mcq_literal'));
      }
    }

    // Writing: also a fixed way of answering (a real composition task, not
    // squeezed into the quiz list) — handled by WeeklyAssessmentScreen as
    // its own screen right after the quiz.
    String? writingMode;
    final scheduledWriting = scheduled['Writing'];
    if (scheduledWriting != null && scheduledWriting.isNotEmpty) {
      writingMode = scheduledWriting.first == 'writing.mode_free' ? 'free' : 'guided';
    } else {
      final writingStates = states.where((s) => skillOf(s.subSkillCode) == 'Writing').toList()
        ..sort((a, b) => a.masteredRung().compareTo(b.masteredRung()));
      if (writingStates.isNotEmpty) {
        writingMode = writingStates.first.subSkillCode == 'writing.mode_free' ? 'free' : 'guided';
      }
    }

    return WeeklyAssessmentPlan(
      vocabGrammarQueue: vocabGrammarQueue,
      readingQueue: readingQueue,
      writingMode: writingMode,
    );
  }

  // ── BATCH GENERATION (fixed-queue module sessions) ───────────────────────
  // Vocabulary/Grammar/Reading/Writing's module screens know their whole
  // session's shape (which sub-skills, how many of each, which format if
  // pinned) before the student answers anything — unlike Today's Task/the
  // Weekly Assessment, which stay genuinely adaptive one item at a time via
  // AdaptivePracticeScreen's own _decideFocus()/_fetchItem() + prefetch.
  // This generates the whole thing in one `generate` call per slice
  // (`count: slice.count`, reusing the batch path already live server-side)
  // instead of one call per question.

  /// Batch-generates every item in `queue` upfront. Each slice's rung is
  /// resolved once, right here, from the same confirmed-gate math
  /// AdaptivePracticeScreen uses (confirmed rung + 1) — a slice with a
  /// pinned format (e.g. Vocabulary's mode-cards) keeps that format
  /// regardless of rung; one without gets the rung-derived format from
  /// `rung_formats`/the fallback ladder. Returns a flat list in the same
  /// order as `queue`, ready for `AdaptivePracticeScreen(preloadedItems:
  /// ...)`. Throws on a network/generation failure — callers show their own
  /// loading/error UI around this, same as their other async loads.
  ///
  /// Trade-off: rung is decided once per slice, not re-derived as the
  /// student answers — a confirmation window can still resolve mid-session
  /// (answers still update it live), it just won't change the content of
  /// items already generated in this batch.
  Future<List<Map<String, dynamic>>> batchGenerateQueue(
    List<PracticeQueueItem> queue, {
    String? contextPassage,
  }) async {
    final standard = await studentStandard();
    final tax = await taxonomy();
    final codeToSkill = {for (final t in tax) t['code'] as String: t['skill'] as String};
    final codeToName = {for (final t in tax) t['code'] as String: t['name'] as String};
    final dbFormats = await rungFormats();
    final states = await loadMastery(standard);
    final confirmed = await confirmedRungs();

    String skillOf(String c) => codeToSkill[c] ?? 'Grammar';
    int targetRung(String code) {
      final m = states.firstWhere(
        (s) => s.subSkillCode == code,
        orElse: () => MasteryState(subSkillCode: code, standard: standard),
      );
      final base = confirmed[code] ?? m.masteredRung();
      return (base + 1).clamp(1, 5);
    }
    String formatFor(String skill, int rung) {
      final fromDb = dbFormats[skill]?[rung];
      if (fromDb != null) return fromDb;
      return (rungFormatFallback[skill] ??
          rungFormatFallback['Grammar']!)[(rung - 1).clamp(0, 4)];
    }

    // generate/index.ts clamps `count` to 5 server-side regardless of what's
    // requested — a slice bigger than that (Grammar's 10-question single
    // topic, its 15-question whole area, Reading's 8-direct slice, ...)
    // used to request its full count in one call, silently get back only 5
    // items, and then always throw "generated 5/10 items". Split into
    // sub-batches of at most this size instead — still far fewer calls than
    // one per question, just never more than the server will honour.
    const maxBatchSize = 5;

    final result = <Map<String, dynamic>>[];
    for (final slice in queue) {
      final skill = skillOf(slice.subSkillCode);
      final name = codeToName[slice.subSkillCode] ?? slice.subSkillCode;
      final rung = targetRung(slice.subSkillCode);
      final format = slice.format ?? formatFor(skill, rung);

      var remaining = slice.count;
      while (remaining > 0) {
        final batchSize = remaining > maxBatchSize ? maxBatchSize : remaining;
        remaining -= batchSize;

        // A sub-batch occasionally comes back short (an item failing the
        // server's own QA re-check a couple of times in a row) or the
        // network call itself hiccups — neither is worth surfacing to the
        // student as "couldn't prepare your questions", since a fresh call
        // usually just succeeds. Retry silently before giving up for real.
        const maxRetries = 2;
        List<dynamic>? rawItems;
        Object? lastError;
        for (var attempt = 0; attempt <= maxRetries; attempt++) {
          try {
            final res = await _sb.functions.invoke('generate', body: {
              'skill': skill,
              'sub_skill': slice.subSkillCode,
              'sub_skill_name': name,
              'rung': rung,
              'format': format,
              'standard': standard,
              'target_difficulty': EloConfig.itemDifficulty(standard, rung),
              'recent_errors': <String>[],
              'count': batchSize,
              if (contextPassage != null) 'context_passage': contextPassage,
            });
            final data = res.data;
            final items = batchSize > 1
                ? (data is Map ? data['items'] as List? : null) ?? const []
                : ((data is Map ? data['item'] : null) != null
                    ? [(data as Map)['item']]
                    : const []);
            if (items.length == batchSize) {
              rawItems = items;
              break;
            }
            final qa = data is Map ? data['qa'] : null;
            lastError = Exception(
                'generate produced ${items.length}/$batchSize items for '
                '"$format"${qa == null ? '' : ' — QA: $qa'}');
          } catch (e) {
            lastError = e;
          }
        }
        if (rawItems == null) throw lastError!;
        for (final raw in rawItems) {
          final item = Map<String, dynamic>.from(raw as Map);
          item['format'] = format;
          item['skill'] = skill;
          item['sub_skill_name'] = name;
          item['rung'] = rung;
          item['is_choice'] = item['options'] != null;
          result.add(item);
        }
      }
    }
    return result;
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