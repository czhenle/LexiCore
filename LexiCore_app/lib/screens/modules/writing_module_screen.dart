import 'package:flutter/material.dart';
import 'topic_picker_screen.dart';

const Color _writingColor = Color(0xFFE57373);

/// Writing's topic/whole-area picker — same shape as Grammar's, sourced from
/// `sub_skills` (mechanics/spelling, sentence completion/combining/tense
/// consistency, guided/free composition). Retired the old 4-exercise-type
/// card flow and its own WritingQuizScreen — Writing now routes through the
/// same generate -> grade -> skill_mastery pipeline as adaptive practice, so
/// higher-rung (composition) items pick up their complexity/word-count
/// target from the shared per-Standard syllabus config in the `generate`
/// edge function rather than the standalone `writing` edge function (which
/// is now only used by the initial diagnostic assessment).
class WritingModuleScreen extends StatelessWidget {
  const WritingModuleScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const TopicPickerScreen(
      skill: 'Writing',
      appTitle: 'Writing',
      heroTitle: 'Writing Practice',
      heroIcon: Icons.edit_rounded,
      gradientColors: [Color(0xFFB71C1C), Color(0xFFE57373), Color(0xFFEF9A9A)],
      accentColor: _writingColor,
      emptyMessage: 'No Writing topics available yet.',
    );
  }
}
