// ============================================================================
// LexiCore — Learner Model (Elo-based Knowledge Tracing)
// ----------------------------------------------------------------------------
// This is LexiCore's OWN adaptive engine. The LLM only writes question text;
// this file decides WHAT to ask, at WHICH difficulty, and WHETHER a student has
// mastered a skill. It is the examinable ML contribution of the project.
//
// Method: online Elo rating (Computer Adaptive Practice), after
// Klinkenberg, Straatemeier & van der Maas (2011), "Computer adaptive practice
// of maths ability using a new item response model...", Computers & Education.
//
// Design decisions (defend these in the viva):
//   * Each (student, sub-skill) has ONE continuous ability rating `theta`.
//   * Item difficulty `beta` is NOT rated per item (items are generated fresh
//     and never reused, so per-item ratings can't converge). Instead each
//     item's difficulty is FIXED a-priori by the curriculum ladder:
//     beta = standardBase[standard] + rungOffset[rung].
//     => Only student ability updates online. This is the standard adaptation
//        of Elo when items are ephemeral.
//   * A "rung" (1..5) is a mastery STAGE on the pedagogical ladder. The rung a
//     student currently sits on is READ OFF their ability, not stored directly:
//     a rung is mastered when P(correct at that rung) >= masteryThreshold.
// ============================================================================

import 'dart:math' as math;

/// Universal 5-rung mastery ladder (same shape for every skill).
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

/// Tunable hyper-parameters. All ratings live on the standard Elo scale.
class EloConfig {
  /// Difficulty baseline per school standard (1..6). One step per standard.
  static const Map<int, double> standardBase = {
    1: 1000, 2: 1080, 3: 1160, 4: 1240, 5: 1320, 6: 1400,
  };

  /// Difficulty offset per rung. Rungs are evenly spaced 80 Elo points apart
  /// and centred so that rung 4 == the grade baseline. Effect: a student whose
  /// ability equals their grade baseline has mastered rungs 1-2 and is working
  /// on rung 3 — i.e. "typical for their grade", not "mastered nothing".
  /// Calibrated empirically (see verification runs); tune per pilot data.
  static const Map<int, double> rungOffset = {
    1: -240, 2: -160, 3: -80, 4: 0, 5: 80,
  };

  /// Probability of a correct answer at which a rung counts as "mastered".
  static const double masteryThreshold = 0.70;

  /// Adaptive K-factor: large early (fast convergence), small later (stable).
  static const double kMax = 48;
  static const double kMin = 16;
  static const double kTau = 20; // attempts at which K is roughly halfway down

  /// Elo logistic scale.
  static const double scale = 400;

  static double itemDifficulty(int standard, int rungNumber) {
    final base = standardBase[standard.clamp(1, 6)]!;
    return base + (rungOffset[rungNumber.clamp(1, 5)] ?? 0);
  }

  /// K shrinks as the student answers more items in this sub-skill.
  static double kFor(int attempts) =>
      kMin + (kMax - kMin) / (1 + attempts / kTau);

  /// Seed an initial ability from a coarse assessment score (0..100).
  /// 50% maps to the grade baseline; each point shifts ability by 4 Elo pts,
  /// so 0% -> baseline-200 and 100% -> baseline+200.
  static double abilityFromScore(int scorePercent, int standard) =>
      standardBase[standard.clamp(1, 6)]! + (scorePercent - 50) * 4.0;
}

/// Per-(student, sub-skill) state. Persisted in `skill_mastery`.
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