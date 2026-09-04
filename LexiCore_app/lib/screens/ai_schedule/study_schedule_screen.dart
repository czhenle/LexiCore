import 'package:flutter/material.dart';
import '../../services/mastery_service.dart';
import '../../theme/app_colors.dart';

/// A read-only overview of the student's whole study plan (7/14/30 days,
/// chosen at onboarding): what they're scheduled to do each day and why
/// (the plan goal). Actually STARTING a task is Home's "Today's Task"
/// card's job, not this screen's — this page only tells the student what's
/// coming, generated once for the whole plan and stored in
/// `study_schedules` (see MasteryService.getOrGenerateStudyPlan), not
/// recomputed live.
class StudyScheduleScreen extends StatefulWidget {
  const StudyScheduleScreen({super.key});

  @override
  State<StudyScheduleScreen> createState() => _StudyScheduleScreenState();
}

class _StudyScheduleScreenState extends State<StudyScheduleScreen> {
  static const _bg = AppColors.skyBg;
  static const _navy = AppColors.navy;
  static const _blue = AppColors.blue;

  static const _skillEmoji = {
    'Vocabulary': '📖',
    'Grammar': '✏️',
    'Reading': '📚',
    'Writing': '✍️',
  };
  // Aligned with every other screen's skill->color convention (Home,
  // Module Selection, the module screens themselves) — this map used to
  // have Grammar and Reading's colors swapped, plus a Vocabulary purple
  // used nowhere else in the app, so a Grammar/Reading day here showed the
  // wrong accent color relative to everywhere else the same skill appears.
  static const _skillColor = {
    'Vocabulary': AppColors.brightOrange,
    'Grammar': AppColors.mintGreen,
    'Reading': AppColors.blue,
    'Writing': AppColors.coralRed,
  };

  final _mastery = MasteryService();
  bool _loading = true;
  Map<String, dynamic>? _plan;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final plan = await _mastery.getOrGenerateStudyPlan();
    if (!mounted) return;
    setState(() {
      _plan = plan;
      _loading = false;
    });
  }

  static const _monthNames = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ];
  String _formatDate(DateTime d) => '${_monthNames[d.month - 1]} ${d.day}';

  String _todayIso() {
    final now = DateTime.now();
    return '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator(color: _blue))
            : _plan == null
                ? _emptyState()
                : _planView(_plan!),
      ),
    );
  }

  Widget _emptyState() => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: const [
            Text('🗓️', style: TextStyle(fontSize: 48)),
            SizedBox(height: 12),
            Text('Finish your quiz to get your study plan!',
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: _navy, fontSize: 16, fontWeight: FontWeight.w700)),
          ]),
        ),
      );

  Widget _planView(Map<String, dynamic> plan) {
    final days = (plan['days'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
    final completed =
        Set<String>.from((plan['completed_days'] as List?)?.cast<String>() ?? const []);
    final planGoal = plan['plan_goal'] as String?;
    // One entry per 7-day cycle — {week_number, focus_skill,
    // sub_skills_touched, milestone} — what that specific week is actually
    // for, distinct from `weeks` below (which is just the day cards
    // grouped by 7 for section headers).
    final planWeeks = (plan['weeks'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
    final planLength = plan['plan_length_days'] as int? ?? days.length;
    final doneCount = days.where((d) => completed.contains(d['date'])).length;
    final trackedDays = days.where((d) => d['type'] != 'rest').length;
    final todayIso = _todayIso();

    // Group into week-of-7 chunks for section headers.
    final weeks = <List<Map<String, dynamic>>>[];
    for (var i = 0; i < days.length; i += 7) {
      weeks.add(days.sublist(i, i + 7 > days.length ? days.length : i + 7));
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('My Study Plan 📅',
              style: TextStyle(
                  fontSize: 28, fontWeight: FontWeight.w900, color: _navy)),
          const SizedBox(height: 4),
          Text(
              '$planLength days — start each day\'s task from Home.',
              style: TextStyle(
                  fontSize: 14,
                  color: _navy.withValues(alpha: 0.7),
                  fontWeight: FontWeight.w600)),
          if (planGoal != null) ...[
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.brightOrange.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: AppColors.brightOrange.withValues(alpha: 0.3)),
              ),
              child: Row(children: [
                const Text('🎯', style: TextStyle(fontSize: 22)),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(planGoal,
                      style: TextStyle(
                          color: Colors.orange.shade900,
                          fontSize: 14,
                          fontWeight: FontWeight.w800)),
                ),
              ]),
            ),
          ],
          const SizedBox(height: 16),
          _planProgress(doneCount, trackedDays),
          const SizedBox(height: 20),
          for (var w = 0; w < weeks.length; w++) ...[
            if (weeks.length > 1) ...[
              Text('Week ${w + 1}',
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w900, color: _navy)),
              const SizedBox(height: 10),
            ],
            if (w < planWeeks.length) ...[
              _weekMilestoneCard(planWeeks[w]),
              const SizedBox(height: 10),
            ],
            ...weeks[w].map((d) => _dayCard(
                  d,
                  completed.contains(d['date']),
                  d['date'] == todayIso,
                )),
            const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }

  /// Was one flowing sentence crammed together ("you'll work mostly on X —
  /// A, B and C. By the end of the week..."). Now a clear headline + a real
  /// bullet list of what's actually scheduled, so it reads at a glance
  /// instead of needing to be parsed as a paragraph.
  Widget _weekMilestoneCard(Map<String, dynamic> week) {
    const color = AppColors.mintGreen;
    final weekNumber = week['week_number'] as int? ?? 1;
    final focusSkill = week['focus_skill'] as String? ?? '';
    final subSkills = (week['sub_skills_touched'] as List?)?.cast<String>() ?? const [];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Text('📈', style: TextStyle(fontSize: 18)),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                subSkills.isEmpty
                    ? 'Week $weekNumber: keep practising'
                    : 'Week $weekNumber focus: $focusSkill',
                style: const TextStyle(
                    color: Color(0xFF00695C),
                    fontSize: 14,
                    fontWeight: FontWeight.w900),
              ),
            ),
          ]),
          if (subSkills.isEmpty) ...[
            const SizedBox(height: 4),
            const Padding(
              padding: EdgeInsets.only(left: 28),
              child: Text('Your plan fills in more detail as you go.',
                  style: TextStyle(
                      color: Color(0xFF00695C), fontSize: 12, height: 1.4)),
            ),
          ] else ...[
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.only(left: 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: subSkills
                    .map((s) => Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('•  ',
                                  style: TextStyle(
                                      color: Color(0xFF00695C),
                                      fontWeight: FontWeight.w900)),
                              Expanded(
                                child: Text(s,
                                    style: const TextStyle(
                                        color: Color(0xFF00695C),
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600)),
                              ),
                            ],
                          ),
                        ))
                    .toList(),
              ),
            ),
            const SizedBox(height: 6),
            const Padding(
              padding: EdgeInsets.only(left: 28),
              child: Text('Aim to feel noticeably more confident with these by the weekend.',
                  style: TextStyle(
                      color: Color(0xFF00695C),
                      fontSize: 12,
                      fontStyle: FontStyle.italic,
                      height: 1.4)),
            ),
          ],
        ],
      ),
    );
  }

  Widget _planProgress(int done, int total) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
              color: _blue.withValues(alpha: 0.08),
              blurRadius: 12,
              offset: const Offset(0, 4)),
        ],
      ),
      child: Row(children: [
        const Text('⭐', style: TextStyle(fontSize: 22)),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('$done of $total tasks done so far',
                style: const TextStyle(
                    color: _navy, fontSize: 15, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: total == 0 ? 0 : done / total,
                minHeight: 10,
                backgroundColor: _bg,
                valueColor: const AlwaysStoppedAnimation(AppColors.mintGreen),
              ),
            ),
          ]),
        ),
      ]),
    );
  }

  Widget _dayCard(Map<String, dynamic> d, bool isDone, bool isToday) {
    final dayName = d['day_name'] as String? ?? '';
    final date = DateTime.tryParse(d['date'] as String? ?? '');
    final type = d['type'] as String?;
    final skill = d['skill'] as String?;
    final label = d['task_label'] as String? ?? skill ?? 'Practice';
    final isRest = type == 'rest';
    final color = isRest
        ? Colors.grey
        : (type == 'assessment' ? AppColors.purple : (_skillColor[skill] ?? _blue));
    final emoji = isRest ? '🌤️' : (type == 'assessment' ? '📝' : (_skillEmoji[skill] ?? '⭐'));

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
            color: isToday ? color : color.withValues(alpha: 0.25),
            width: isToday ? 2.5 : 1.5),
      ),
      child: Row(children: [
        // day chip
        Container(
          width: 54,
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(children: [
            Text(emoji, style: const TextStyle(fontSize: 20)),
            const SizedBox(height: 2),
            Text(dayName.length >= 3 ? dayName.substring(0, 3) : dayName,
                style: TextStyle(
                    color: color, fontSize: 11, fontWeight: FontWeight.w800)),
          ]),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              if (isToday) ...[
                Text('TODAY',
                    style: TextStyle(
                        color: color, fontSize: 10, fontWeight: FontWeight.w900)),
                const SizedBox(width: 6),
              ],
              if (date != null)
                Text(_formatDate(date),
                    style: TextStyle(
                        color: _navy.withValues(alpha: 0.5),
                        fontSize: 11,
                        fontWeight: FontWeight.w700)),
            ]),
            Text(label,
                style: const TextStyle(
                    color: _navy, fontSize: 15, fontWeight: FontWeight.w900)),
          ]),
        ),
        if (!isRest)
          Icon(
            isDone ? Icons.check_circle : Icons.radio_button_unchecked,
            color: isDone ? AppColors.mintGreen : Colors.grey.shade300,
            size: 28,
          ),
      ]),
    );
  }
}
