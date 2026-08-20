import 'package:flutter/material.dart';
import 'topic_picker_screen.dart';

const Color _grammarColor = Color(0xFF4DB6AC);

/// Grammar's topic/whole-area picker — see TopicPickerScreen for the shared
/// implementation (topics grouped by area from `sub_skills`, single
/// topic = 10 questions, whole area = 15 mixed, routed through
/// AdaptivePracticeScreen's fixed-queue mode).
class GrammarModuleScreen extends StatelessWidget {
  const GrammarModuleScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const TopicPickerScreen(
      skill: 'Grammar',
      appTitle: 'Grammar',
      heroTitle: 'Grammar Practice',
      heroIcon: Icons.rule_rounded,
      gradientColors: [Color(0xFF00796B), Color(0xFF4DB6AC), Color(0xFF80CBC4)],
      accentColor: _grammarColor,
      emptyMessage: 'No Grammar topics available yet.',
    );
  }
}
