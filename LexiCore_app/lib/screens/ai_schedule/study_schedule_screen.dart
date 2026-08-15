import 'package:flutter/material.dart';
import '../../services/mastery_service.dart';
import '../modules/adaptive_practice_screen.dart';

/// A weekly plan derived directly from the student's mastery map: the weakest
/// skills get the most days, and every day links into focused adaptive
/// practice. Deterministic (no LLM), so it always reflects the CURRENT mastery
/// and updates itself as the student improves.
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
  static const _days = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday'];

  final _mastery = MasteryService();
  bool _loading = true;
  MasterySummary? _summary;
  List<_PlanDay> _plan = [];
  final Set<int> _done = {}; // check-offs for this session

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final summary = await _mastery.masterySummary();
    if (!mounted) return;
    setState(() {
      _summary = summary;
      _plan = summary == null ? [] : _buildPlan(summary);
      _loading = false;
    });
  }

  /// Weakest skill appears twice (days 1 & 3); the rest once — a simple,
  /// explainable weighting toward what the student needs most.
  List<_PlanDay> _buildPlan(MasterySummary s) {
    final ordered = s.avgRungBySkill.entries.toList()
      ..sort((a, b) => a.value.compareTo(b.value)); // weakest first
    final skills = ordered.map((e) => e.key).toList();
    while (skills.length < 4) {
      skills.add(skills.isEmpty ? 'Vocabulary' : skills.last);
    }
    final forDay = [skills[0], skills[1], skills[0], skills[2], skills[3]];
    return List.generate(
        5, (i) => _PlanDay(day: _days[i], skill: forDay[i], minutes: 15));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator(color: _blue))
            : _summary == null
                ? _emptyState()
                : _planView(),
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

  Widget _planView() {
    final done = _done.length;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('My Week 📅',
              style: TextStyle(
                  fontSize: 28, fontWeight: FontWeight.w900, color: _navy)),
          const SizedBox(height: 4),
          Text('More practice on the skills you need most — '
              'extra time on ${_summary!.weakest}!',
              style: TextStyle(
                  fontSize: 14,
                  color: _navy.withValues(alpha: 0.7),
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 16),
          _weekProgress(done),
          const SizedBox(height: 20),
          ...List.generate(_plan.length, (i) => _dayCard(i, _plan[i])),
        ],
      ),
    );
  }

  Widget _weekProgress(int done) {
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
            Text('$done of ${_plan.length} days done this week',
                style: const TextStyle(
                    color: _navy, fontSize: 15, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: _plan.isEmpty ? 0 : done / _plan.length,
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

  Widget _dayCard(int index, _PlanDay d) {
    final color = _skillColor[d.skill] ?? _blue;
    final emoji = _skillEmoji[d.skill] ?? '⭐';
    final isDone = _done.contains(index);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.25), width: 1.5),
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
            Text(d.day.substring(0, 3),
                style: TextStyle(
                    color: color, fontSize: 11, fontWeight: FontWeight.w800)),
          ]),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(d.skill,
                style: const TextStyle(
                    color: _navy, fontSize: 16, fontWeight: FontWeight.w900)),
            const SizedBox(height: 2),
            Text('~${d.minutes} min practice',
                style: TextStyle(
                    color: _navy.withValues(alpha: 0.6),
                    fontSize: 12,
                    fontWeight: FontWeight.w600)),
          ]),
        ),
        // start / done
        if (isDone)
          IconButton(
            onPressed: () => setState(() => _done.remove(index)),
            icon: const Icon(Icons.check_circle,
                color: Color(0xFF4DB6AC), size: 32),
          )
        else
          ElevatedButton(
            onPressed: () async {
              await Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) =>
                          AdaptivePracticeScreen(focusSkill: d.skill)));
              if (mounted) setState(() => _done.add(index));
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: color,
              foregroundColor: Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
            ),
            child: const Text('Start',
                style: TextStyle(fontWeight: FontWeight.w800)),
          ),
      ]),
    );
  }
}

class _PlanDay {
  final String day;
  final String skill;
  final int minutes;
  _PlanDay({required this.day, required this.skill, required this.minutes});
}