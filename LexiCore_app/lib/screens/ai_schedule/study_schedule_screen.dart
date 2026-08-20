import 'package:flutter/material.dart';
import '../../services/mastery_service.dart';

/// A read-only weekly overview: what the student is scheduled to do each day
/// and why (this week's goal). Actually STARTING a task is Home's "Today's
/// Task" card's job, not this screen's — this page only tells the student
/// what's coming, generated once per week and stored in `study_schedules`
/// (see MasteryService.getOrGenerateWeeklySchedule), not recomputed live.
class StudyScheduleScreen extends StatefulWidget {
  const StudyScheduleScreen({super.key});

  @override
  State<StudyScheduleScreen> createState() => _StudyScheduleScreenState();
}

class _StudyScheduleScreenState extends State<StudyScheduleScreen> {
  static const _bg = Color(0xFFF0F8FF);
  static const _navy = Color(0xFF003C8F);
  static const _blue = Color(0xFF1E88E5);

  static const _skillEmoji = {
    'Vocabulary': '📖',
    'Grammar': '✏️',
    'Reading': '📚',
    'Writing': '✍️',
  };
  static const _skillColor = {
    'Vocabulary': Color(0xFF7E57C2),
    'Grammar': Color(0xFFFF9800),
    'Reading': Color(0xFF4DB6AC),
    'Writing': Color(0xFFE57373),
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
    final plan = await _mastery.getOrGenerateWeeklySchedule();
    if (!mounted) return;
    setState(() {
      _plan = plan;
      _loading = false;
    });
  }

  String get _todayName {
    const names = [
      'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'
    ];
    return names[DateTime.now().weekday - 1];
  }

  DateTime _mondayOf(DateTime d) =>
      DateTime(d.year, d.month, d.day).subtract(Duration(days: d.weekday - 1));

  static const _monthNames = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ];
  String _formatDate(DateTime d) => '${_monthNames[d.month - 1]} ${d.day}';

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
            Text('Finish your quiz to get your weekly plan!',
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
    final weekGoal = plan['week_goal'] as String?;
    final doneCount = days.where((d) => completed.contains(d['day'])).length;
    final trackedDays = days.where((d) => d['type'] != 'rest').length;
    final weekStart =
        DateTime.tryParse(plan['week_start'] as String? ?? '') ?? _mondayOf(DateTime.now());

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('My Week 📅',
              style: TextStyle(
                  fontSize: 28, fontWeight: FontWeight.w900, color: _navy)),
          const SizedBox(height: 4),
          Text('Here\'s your plan for the week — start each day\'s task from Home.',
              style: TextStyle(
                  fontSize: 14,
                  color: _navy.withValues(alpha: 0.7),
                  fontWeight: FontWeight.w600)),
          if (weekGoal != null) ...[
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFFF9800).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: const Color(0xFFFF9800).withValues(alpha: 0.3)),
              ),
              child: Row(children: [
                const Text('🎯', style: TextStyle(fontSize: 22)),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(weekGoal,
                      style: TextStyle(
                          color: Colors.orange.shade900,
                          fontSize: 14,
                          fontWeight: FontWeight.w800)),
                ),
              ]),
            ),
          ],
          const SizedBox(height: 16),
          _weekProgress(doneCount, trackedDays),
          const SizedBox(height: 20),
          ...List.generate(
            days.length,
            (i) => _dayCard(
              days[i],
              completed.contains(days[i]['day']),
              weekStart.add(Duration(days: i)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _weekProgress(int done, int total) {
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
            Text('$done of $total tasks done this week',
                style: const TextStyle(
                    color: _navy, fontSize: 15, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: total == 0 ? 0 : done / total,
                minHeight: 10,
                backgroundColor: _bg,
                valueColor: const AlwaysStoppedAnimation(Color(0xFF4DB6AC)),
              ),
            ),
          ]),
        ),
      ]),
    );
  }

  Widget _dayCard(Map<String, dynamic> d, bool isDone, DateTime date) {
    final day = d['day'] as String? ?? '';
    final type = d['type'] as String?;
    final skill = d['skill'] as String?;
    final label = d['task_label'] as String? ?? skill ?? 'Practice';
    final isToday = day == _todayName;
    final isRest = type == 'rest';
    final color = isRest
        ? Colors.grey
        : (type == 'assessment' ? const Color(0xFF6A1B9A) : (_skillColor[skill] ?? _blue));
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
            Text(day.substring(0, 3),
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
            color: isDone ? const Color(0xFF4DB6AC) : Colors.grey.shade300,
            size: 28,
          ),
      ]),
    );
  }
}
