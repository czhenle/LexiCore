import 'dart:math' as math;

bool needsChallengeAlert(int studentStandard, int subSkillStandardMin) =>
    studentStandard < subSkillStandardMin;

enum Rung {
  understand(1, 'Understand'),   // receptive exposure
  recognize(2, 'Recognize'),     // receptive discrimination
  controlled(3, 'Controlled'),   // guided production
  transfer(4, 'Transfer'),       // extend / transform
  produce(5, 'Produce');         // free production

  const Rung(this.number, this.label);
  final int number;
  final String label;

  static Rung fromNumber(int n) =>
      Rung.values.firstWhere((r) => r.number == n, orElse: () => Rung.understand);
}

class EloConfig {
  static const Map<int, double> standardBase = {
    1: 1000, 2: 1080, 3: 1160, 4: 1240, 5: 1320, 6: 1400,
  };

  static const Map<int, double> rungOffset = {
    1: -240, 2: -160, 3: -80, 4: 0, 5: 80,
  };

  static const double masteryThreshold = 0.70;

  static const double kMax = 48;
  static const double kMin = 16;
  static const double kTau = 20;

  static const double scale = 400;

  static double itemDifficulty(int standard, int rungNumber) {
    final base = standardBase[standard.clamp(1, 6)]!;
    return base + (rungOffset[rungNumber.clamp(1, 5)] ?? 0);
  }

  static double kFor(int attempts) =>
      kMin + (kMax - kMin) / (1 + attempts / kTau);

  static double abilityFromScore(int scorePercent, int standard) =>
      standardBase[standard.clamp(1, 6)]! + (scorePercent - 50) * 4.0;
}

/// Rung -> format per skill. Fallback only — the live source of truth is the
/// `rung_formats` table (MasteryService.rungFormats()); this just keeps
/// rung-derived (non-pinned-format) queues working if that table is ever
/// empty/unreachable. Shared between AdaptivePracticeScreen (one item at a
/// time) and MasteryService.batchGenerateQueue (a whole session upfront) so
/// there's one place to update, not two that can drift apart.
const Map<String, List<String>> rungFormatFallback = {
  'Vocabulary': ['meaning_match', 'mcq_word_meaning', 'cloze_sentence_wordbank', 'cloze_paragraph_open', 'open_sentence'],
  'Grammar':    ['worked_example', 'mcq_identify_or_error', 'gap_fill', 'transform_or_reorder', 'open_sentence'],
  // Reading dropped its 5-format ladder — the module screen pins
  // mcq_literal (direct) / mcq_inference (KBAT) per-slice by standard
  // instead, not by rung. This fallback only matters if 'reading.
  // comprehension' is ever served without a pinned format — kept
  // consistent with the module either way: direct until the top rung,
  // KBAT at rung 5.
  'Reading':    ['mcq_literal', 'mcq_literal', 'mcq_literal', 'mcq_literal', 'mcq_inference'],
  'Writing':    ['error_correction_rewrite', 'sentence_complete', 'sentence_combine', 'guided_composition', 'free_composition'],
};

class MasteryState {
  final String subSkillCode;
  final int standard;
  double ability;   // theta on the Elo scale
  int attempts;

  MasteryState({
    required this.subSkillCode,
    required this.standard,
    double? ability,
    this.attempts = 0,
  }) : ability = ability ?? EloConfig.standardBase[standard.clamp(1, 6)]!;

  /// Probability the student answers a given-difficulty item correctly.
  double pCorrect(double itemDifficulty) =>
      1.0 / (1.0 + math.pow(10, (itemDifficulty - ability) / EloConfig.scale));

  /// Probability of success at a whole rung, for this student's standard.
  double pCorrectAtRung(int rungNumber) =>
      pCorrect(EloConfig.itemDifficulty(standard, rungNumber));

  /// Highest rung the student has mastered (0 = none yet). Difficulty rises
  /// monotonically with rung, so this is the top rung meeting the threshold.
  int masteredRung() {
    int top = 0;
    for (var r = 1; r <= 5; r++) {
      if (pCorrectAtRung(r) >= EloConfig.masteryThreshold) top = r;
    }
    return top;
  }

  /// The rung the student should practise next (the first not-yet-mastered
  /// one). Capped at 5 for maintenance once everything is mastered.
  int nextTargetRung() => math.min(masteredRung() + 1, 5);

  /// Core Elo update. Call once per answered item.
  /// Returns the ability change (delta) for logging/inspection.
  double recordAttempt({required int rungNumber, required bool correct}) {
    final beta = EloConfig.itemDifficulty(standard, rungNumber);
    final expected = pCorrect(beta);
    final actual = correct ? 1.0 : 0.0;
    final k = EloConfig.kFor(attempts);
    final delta = k * (actual - expected);
    ability += delta;
    attempts += 1;
    return delta;
  }

  Map<String, dynamic> toRow(String userId) => {
        'user_id': userId,
        'sub_skill_code': subSkillCode,
        'ability': ability,
        'attempts': attempts,
        'mastered_rung': masteredRung(),
        'updated_at': DateTime.now().toIso8601String(),
      };
}

/// A single answered item, appended to `item_attempts` for analytics + the
/// self-trained difficulty/error classifiers later.
class ItemAttempt {
  final String subSkillCode;
  final int rungNumber;
  final String format;
  final double itemDifficulty;
  final bool correct;
  final String? errorType;
  ItemAttempt(this.subSkillCode, this.rungNumber, this.format,
      this.itemDifficulty, this.correct, this.errorType);
}

/// What the scheduler/generator needs: which sub-skill + rung to serve next.
class FocusDecision {
  final String subSkillCode;
  final int rungNumber;
  final double targetDifficulty;
  final double priority;
  FocusDecision(this.subSkillCode, this.rungNumber, this.targetDifficulty,
      this.priority);

  @override
  String toString() =>
      '$subSkillCode @ rung $rungNumber (β=${targetDifficulty.toStringAsFixed(0)}, '
      'priority=${priority.toStringAsFixed(2)})';
}

/// Item-selection policy — LexiCore's own logic, not the LLM's.
/// Picks the highest-priority sub-skill to practise next. Priority favours
/// (a) skills the diagnostic flagged as weak, and (b) low current mastery.
class AdaptivePolicy {
  /// weaknessWeight: 1.0 = normal; >1 for skills flagged weak in the
  /// diagnostic (e.g. Grammar 1.5). Keyed by the sub-skill's parent skill.
  final Map<String, double> weaknessWeight;
  AdaptivePolicy({this.weaknessWeight = const {}});

  double _priority(MasteryState m, String parentSkill) {
    // Lower mastered rung => higher need. Normalise rung 0..5 to 1..0.
    final need = (5 - m.masteredRung()) / 5.0;
    final w = weaknessWeight[parentSkill] ?? 1.0;
    return w * need;
  }

  /// Choose the next focus across all tracked sub-skills.
  /// `parentSkillOf` maps a sub-skill code to its skill (Grammar/Vocab/...).
  FocusDecision selectNext(
    List<MasteryState> states,
    String Function(String subSkillCode) parentSkillOf,
  ) {
    MasteryState? best;
    double bestP = -1;
    for (final m in states) {
      final p = _priority(m, parentSkillOf(m.subSkillCode));
      if (p > bestP) {
        bestP = p;
        best = m;
      }
    }
    best ??= states.first;
    final rung = best.nextTargetRung();
    return FocusDecision(
      best.subSkillCode,
      rung,
      EloConfig.itemDifficulty(best.standard, rung),
      bestP,
    );
  }
}

/// Checkpoint / re-assessment gate. A rung is CONFIRMED mastered only after the
/// student demonstrates it under re-test, not on a single lucky answer.
class Checkpoint {
  static const int minAttempts = 3;
  static const double minAccuracy = 0.8;

  /// Given recent attempts AT a specific rung, is it confirmed?
  static bool isRungConfirmed(List<ItemAttempt> recentAtRung, MasteryState m,
      int rungNumber) {
    if (recentAtRung.length < minAttempts) return false;
    final acc = recentAtRung.where((a) => a.correct).length /
        recentAtRung.length;
    return acc >= minAccuracy &&
        m.pCorrectAtRung(rungNumber) >= EloConfig.masteryThreshold;
  }
}

/// One entry in a fixed practice queue: practise this sub-skill `count`
/// times. Used by AdaptivePracticeScreen's bounded-session mode (Grammar's
/// topic/whole-area picker, the weekly assessment, Today's Task) — lives here
/// rather than in the screen file so MasteryService can build queues too,
/// without a circular import.
class PracticeQueueItem {
  final String subSkillCode;
  final int count;

  /// Overrides the rung-derived format for every item in this slice. Every
  /// other skill picks its format from `rung_formats`/the rung ladder, but
  /// Vocabulary's mode-cards (Guess the Image, Word Meaning, ...) fix the
  /// format to whichever mode the student tapped — rung still scales
  /// difficulty within that mode, it just never changes the format.
  final String? format;
  const PracticeQueueItem(this.subSkillCode, this.count, {this.format});
}

/// What MasteryService.buildWeeklyAssessmentPlan() decided this week's
/// check-in should contain — see WeeklyAssessmentScreen for how it's run.
/// Kept as 3 separate parts (not one combined queue) because each needs its
/// own screen/step: Reading's questions need the passage shown first, on
/// its own screen, the same way the real Reading module shows it — not
/// folded into a generic quiz with the passage hidden behind a re-read
/// button; Writing needs its own submit/timer UI entirely.
class WeeklyAssessmentPlan {
  /// Vocabulary/Grammar questions, batch-generated together into one quiz
  /// screen.
  final List<PracticeQueueItem> vocabGrammarQueue;

  /// Reading's questions — generated (and shown) only AFTER the student has
  /// read the passage on its own screen, same flow as the real Reading
  /// module.
  final List<PracticeQueueItem> readingQueue;

  /// 'guided' | 'free' | null — null means no composition task this week
  /// (no Writing history yet to target). When set, the caller launches
  /// EssayWritingScreen(mode: writingMode) as its own screen right after
  /// the quiz — a full composition needs its own submit/timer UI, not a
  /// slot in the quiz list.
  final String? writingMode;

  const WeeklyAssessmentPlan({
    required this.vocabGrammarQueue,
    required this.readingQueue,
    required this.writingMode,
  });

  bool get isEmpty =>
      vocabGrammarQueue.isEmpty && readingQueue.isEmpty && writingMode == null;
}

/// Splits `total` questions as evenly as possible across `codes`, in a fixed
/// (not random) order — e.g. 15 across 4 codes -> [4,4,4,3]. Shared by
/// Grammar's "whole area" mode and the weekly assessment's per-skill split.
List<PracticeQueueItem> distributeQuestions(List<String> codes, int total) {
  final n = codes.length;
  if (n == 0) return const [];
  final base = total ~/ n;
  final remainder = total % n;
  return [
    for (var i = 0; i < n; i++)
      PracticeQueueItem(codes[i], base + (i < remainder ? 1 : 0)),
  ];
}