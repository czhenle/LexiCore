import 'package:supabase_flutter/supabase_flutter.dart';
import '../main.dart';
import '../models/learner_model.dart';

class SupabaseService {
  // ── AUTH ──────────────────────────────────────────────────────────────────

  Future<AuthResponse> signUp(
    String email,
    String password, {
    String? username,
  }) async {
    return await supabase.auth.signUp(
      email: email,
      password: password,
      data: username == null ? null : {'username': username},
    );
  }

  Future<AuthResponse> signIn(String email, String password) async {
    return await supabase.auth.signInWithPassword(
      email: email,
      password: password,
    );
  }

  Future<void> signOut() async {
    await supabase.auth.signOut();
  }

  User? get currentUser => supabase.auth.currentUser;

  bool get isLoggedIn => supabase.auth.currentUser != null;

  // ── STUDENT PROFILE ───────────────────────────────────────────────────────

  Future<void> saveStudentProfile({
    required String username,
    required int age,
    required int standard,
    required String studyTime,
    required String grade,
    required String rate,
  }) async {
    final userId = currentUser!.id;
    await supabase.from('student_profiles').upsert({
      'user_id': userId,
      'username': username,
      'age': age,
      'standard': standard,
      'study_time': studyTime,
      'grade': grade,
      'rate': rate,
    }, onConflict: 'user_id');
  }

  Future<Map<String, dynamic>?> getStudentProfile() async {
    final userId = currentUser?.id;
    if (userId == null) return null;

    return await supabase
        .from('student_profiles')
        .select()
        .eq('user_id', userId)
        .maybeSingle();
  }

  // ── ASSESSMENT RESULTS ────────────────────────────────────────────────────

  Future<void> saveAssessmentResults({
    required int vocabularyScore,
    required int grammarScore,
    required int readingScore,
    required int writingScore,
  }) async {
    final userId = currentUser!.id;

    final profile = await getStudentProfile();
    final declaredStandard = (profile?['standard'] as int?) ?? 3;
    final avgScore = (vocabularyScore + grammarScore + readingScore + writingScore) ~/ 4;

    int detectedLevel;
    if (avgScore < 40) {
      detectedLevel = (declaredStandard - 1).clamp(1, 6);
    } else if (avgScore > 70) {
      detectedLevel = (declaredStandard + 1).clamp(1, 6);
    } else {
      detectedLevel = declaredStandard;
    }

    await supabase.from('assessment_results').upsert({
      'user_id': userId,
      'vocabulary_score': vocabularyScore,
      'grammar_score': grammarScore,
      'reading_score': readingScore,
      'writing_score': writingScore,
      'detected_level': detectedLevel,
      'taken_at': DateTime.now().toIso8601String(),
    }, onConflict: 'user_id');
  }

  /// Seeds the per-sub-skill mastery map from the coarse assessment scores.
  /// Each sub-skill of a skill starts at that skill's estimated ability; the
  /// online Elo loop then refines each one independently as the student
  /// practises. Called once, right after the assessment is scored.
  Future<void> seedMasteryFromAssessment({
    required Map<String, int> skillScores, // e.g. {'Grammar': 62, ...}
    required int standard,
  }) async {
    final userId = currentUser?.id;
    if (userId == null) return;

    // Taxonomy is public-read; one seeded row per sub-skill.
    final subSkills = await supabase.from('sub_skills').select('code, skill');

    final rows = <Map<String, dynamic>>[];
    for (final s in (subSkills as List)) {
      final skill = s['skill'] as String;
      final score = skillScores[skill] ?? 50; // neutral default if missing
      final m = MasteryState(
        subSkillCode: s['code'] as String,
        standard: standard,
        ability: EloConfig.abilityFromScore(score, standard),
      );
      rows.add(m.toRow(userId));
    }

    if (rows.isNotEmpty) {
      await supabase.from('skill_mastery').upsert(rows);
    }
  }

  /// Seeds ability from the student's self-reported exam grade when they SKIP
  /// the assessment. Even 80-point steps around 1000 — simple and explainable:
  /// A=1200, B=1120, C=1040, D=960, E=880, F=800.
  Future<void> seedMasteryFromGrade({
    required String grade,
    required int standard,
  }) async {
    final userId = currentUser?.id;
    if (userId == null) return;

    const gradeAbility = <String, double>{
      'A': 1200,
      'B': 1120,
      'C': 1040,
      'D': 960,
      'E': 880,
      'F': 800,
    };
    final ability =
        gradeAbility[grade.toUpperCase()] ?? 1000; // crash-guard only

    final subSkills = await supabase.from('sub_skills').select('code, skill');

    final rows = <Map<String, dynamic>>[];
    for (final s in (subSkills as List)) {
      final m = MasteryState(
        subSkillCode: s['code'] as String,
        standard: standard,
        ability: ability,
      );
      rows.add(m.toRow(userId));
    }

    if (rows.isNotEmpty) {
      await supabase.from('skill_mastery').upsert(rows);
    }
  }

  /// Skip-path seeding that blends the exam grade with the student's per-skill
  /// self-rating. Each skill = grade base ± 40 per rating step from neutral (3).
  /// e.g. grade C base 1040; Reading rated 5 → 1120; Writing rated 2 → 1000.
  Future<void> seedMasteryFromGradeAndRatings({
    required String grade,
    required Map<String, int> ratings, // {'Vocabulary':4,...}, values 1..5
    required int standard,
  }) async {
    final userId = currentUser?.id;
    if (userId == null) return;

    const gradeAbility = <String, double>{
      'A': 1200,
      'B': 1120,
      'C': 1040,
      'D': 960,
      'E': 880,
      'F': 800,
    };
    final base = gradeAbility[grade.toUpperCase()] ?? 1000; // crash-guard only

    final subSkills = await supabase.from('sub_skills').select('code, skill');

    final rows = <Map<String, dynamic>>[];
    for (final s in (subSkills as List)) {
      final skill = s['skill'] as String;
      final rating = ratings[skill] ?? 3; // 3 = neutral
      final ability = base + (rating - 3) * 40.0;
      final m = MasteryState(
        subSkillCode: s['code'] as String,
        standard: standard,
        ability: ability,
      );
      rows.add(m.toRow(userId));
    }

    if (rows.isNotEmpty) {
      await supabase.from('skill_mastery').upsert(rows);
    }
  }

  Future<Map<String, dynamic>?> getAssessmentResults() async {
    final userId = currentUser?.id;
    if (userId == null) return null;

    return await supabase
        .from('assessment_results')
        .select()
        .eq('user_id', userId)
        .maybeSingle();
  }

  // ── QUIZ PROGRESS ─────────────────────────────────────────────────────────

  Future<void> saveQuizProgress({
    required String moduleType,
    required int unitNumber,
    required String topic,
    required int score,
  }) async {
    final userId = currentUser!.id;
    await supabase.from('quiz_progress').insert({
      'user_id': userId,
      'module_type': moduleType,
      'unit_number': unitNumber,
      'topic': topic,
      'score': score,
      'completed': true,
      'completed_at': DateTime.now().toIso8601String(),
    });
  }

  Future<List<Map<String, dynamic>>> getQuizHistory({
    String? moduleType,
  }) async {
    final userId = currentUser?.id;
    if (userId == null) return [];

    var query = supabase.from('quiz_progress').select().eq('user_id', userId);

    if (moduleType != null) {
      query = query.eq('module_type', moduleType);
    }

    final response = await query.order('completed_at', ascending: false);
    return List<Map<String, dynamic>>.from(response);
  }

  // Returns the highest completed unit per module
  Future<Map<String, int>> getModuleProgress() async {
    final history = await getQuizHistory();
    final Map<String, int> progress = {
      'Vocabulary': 0,
      'Grammar': 0,
      'Reading': 0,
      'Writing': 0,
    };

    for (final row in history) {
      final type = row['module_type'] as String?;
      final unit = (row['unit_number'] as int?) ?? 0;
      if (type == null || !progress.containsKey(type)) continue;
      if (unit > (progress[type] ?? 0)) {
        progress[type] = unit;
      }
    }

    return progress;
  }

}
