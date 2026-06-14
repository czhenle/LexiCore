import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../main.dart';

class SupabaseService {
  // ── AUTH ──────────────────────────────────────────────────────────────────

  Future<AuthResponse> signUp(String email, String password) async {
    return await supabase.auth.signUp(email: email, password: password);
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
  }) async {
    final userId = currentUser!.id;
    await supabase.from('student_profiles').upsert({
      'user_id':    userId,
      'username':   username,
      'age':        age,
      'standard':   standard,
      'study_time': studyTime,
    });
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

    final profile          = await getStudentProfile();
    final declaredStandard = (profile?['standard'] as int?) ?? 3;
    final avgScore =
        (vocabularyScore + grammarScore + readingScore + writingScore) ~/ 4;

    int detectedLevel;
    if (avgScore < 40) {
      detectedLevel = (declaredStandard - 1).clamp(1, 6);
    } else if (avgScore > 70) {
      detectedLevel = (declaredStandard + 1).clamp(1, 6);
    } else {
      detectedLevel = declaredStandard;
    }

    await supabase.from('assessment_results').upsert({
      'user_id':          userId,
      'vocabulary_score': vocabularyScore,
      'grammar_score':    grammarScore,
      'reading_score':    readingScore,
      'writing_score':    writingScore,
      'detected_level':   detectedLevel,
      'taken_at':         DateTime.now().toIso8601String(),
    });
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
    required int    unitNumber,
    required String topic,
    required int    score,
  }) async {
    final userId = currentUser!.id;
    await supabase.from('quiz_progress').insert({
      'user_id':      userId,
      'module_type':  moduleType,
      'unit_number':  unitNumber,
      'topic':        topic,
      'score':        score,
      'completed':    true,
      'completed_at': DateTime.now().toIso8601String(),
    });
  }

  Future<List<Map<String, dynamic>>> getQuizHistory({
    String? moduleType,
  }) async {
    final userId = currentUser?.id;
    if (userId == null) return [];

    var query =
        supabase.from('quiz_progress').select().eq('user_id', userId);

    if (moduleType != null) {
      query = query.eq('module_type', moduleType);
    }

    final response =
        await query.order('completed_at', ascending: false);
    return List<Map<String, dynamic>>.from(response);
  }

  // Returns the highest completed unit per module
  Future<Map<String, int>> getModuleProgress() async {
    final history = await getQuizHistory();
    final Map<String, int> progress = {
      'Vocabulary': 0,
      'Grammar':    0,
      'Reading':    0,
      'Writing':    0,
    };

    for (final row in history) {
      final type = row['module_type'] as String;
      final unit = row['unit_number'] as int;
      if (unit > (progress[type] ?? 0)) {
        progress[type] = unit;
      }
    }

    return progress;
  }

  // ── STUDY SCHEDULE ────────────────────────────────────────────────────────

  Future<void> saveStudySchedule(Map<String, dynamic> plan) async {
    final userId = currentUser?.id;
    if (userId == null) return;

    await supabase.from('study_schedules').upsert({
      'user_id':    userId,
      'plan':       plan,
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  /// Returns the saved plan with '_created_at' injected so the schedule
  /// screen can compute which week number the student is currently on.
  Future<Map<String, dynamic>?> getSavedSchedule() async {
    final userId = currentUser?.id;
    if (userId == null) return null;

    final response = await supabase
        .from('study_schedules')
        .select()
        .eq('user_id', userId)
        .maybeSingle();

    if (response == null) return null;

    final plan = response['plan'] as Map<String, dynamic>?;
    if (plan == null) return null;

    // Inject created_at so the screen knows when the plan started
    plan['_created_at'] = response['created_at'];
    return plan;
  }

  /// Returns today's task from the saved schedule, matched to the
  /// correct week based on how many days ago the plan was created.
  Future<Map<String, dynamic>?> getTodayTask() async {
    try {
      final userId = currentUser?.id;
      if (userId == null) return null;

      final response = await supabase
          .from('study_schedules')
          .select()
          .eq('user_id', userId)
          .maybeSingle();

      if (response == null) return null;

      final createdAtStr = response['created_at'] as String?;
      final createdAt = createdAtStr != null
          ? DateTime.tryParse(createdAtStr) ?? DateTime.now()
          : DateTime.now();

      final weeks = response['plan']?['weeks'] as List<dynamic>?;
      if (weeks == null || weeks.isEmpty) return null;

      // Compute which week we're currently in
      final daysSinceStart =
          DateTime.now().difference(createdAt).inDays;
      final currentWeek = (daysSinceStart ~/ 7 + 1).clamp(1, 4);

      // Find the matching week
      final weekData = weeks.firstWhere(
        (w) => (w['week'] as int?) == currentWeek,
        orElse: () => weeks.first,
      );

      final tasks = weekData['daily_tasks'] as List<dynamic>?;
      if (tasks == null) return null;

      // Match today's day name
      const days = [
        'Monday', 'Tuesday', 'Wednesday',
        'Thursday', 'Friday', 'Saturday', 'Sunday',
      ];
      final todayName = days[DateTime.now().weekday - 1];

      for (final task in tasks) {
        if ((task['day'] as String?)?.toLowerCase() ==
            todayName.toLowerCase()) {
          return Map<String, dynamic>.from(task as Map);
        }
      }
      return null;
    } catch (e) {
      debugPrint('getTodayTask error: $e');
      return null;
    }
  }
}