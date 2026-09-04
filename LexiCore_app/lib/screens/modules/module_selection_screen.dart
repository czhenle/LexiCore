import 'package:flutter/material.dart';
import 'vocabulary_module_screen.dart';
import 'grammar_module_screen.dart';
import 'reading_module_screen.dart';
import 'writing_module_screen.dart';
import 'weekly_assessment_screen.dart';
import '../../theme/app_colors.dart';

class ModuleSelectionScreen extends StatelessWidget {
  const ModuleSelectionScreen({super.key});

  // ✨ Sky Blue Theme Colors
  static const Color _bg       = AppColors.skyBg;
  static const Color _navyText = AppColors.navy;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        automaticallyImplyLeading: false,
        title: const Text('Modules',
            style: TextStyle(
                fontWeight: FontWeight.w900,
                color: _navyText, // Updated to Navy Blue
                fontSize: 26)),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 100),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Choose what to practise today',
                  style: TextStyle(
                      fontSize: 16, 
                      color: _navyText.withValues(alpha: 0.6), // Updated to soft Navy
                      fontWeight: FontWeight.w700)),
              const SizedBox(height: 24),

              _buildModuleCard(
                context,
                title:       'Vocabulary',
                description: 'Guess images, match meanings, and learn new words',
                icon:        Icons.abc_rounded,
                color:       AppColors.brightOrange,
                // The module's real 5 mode-cards: Guess the Image, Word
                // Meaning, Word in Context, Synonyms & Antonyms, Spelling.
                tags:        ['Guess image', 'Word meaning', 'Spelling', '+ more'],
                destination: const VocabularyModuleScreen(),
              ),
              _buildModuleCard(
                context,
                title:       'Grammar',
                description: 'Pick your grammar topics and practise targeted exercises',
                icon:        Icons.rule_rounded,
                color:       AppColors.mintGreen,
                // Real topic_group names from sub_skills (confirmed live) —
                // there are ~20 groups in total, these 3 are just a sample.
                tags:        ['Nouns', 'Articles', 'Punctuation', '+ more'],
                destination: const GrammarModuleScreen(),
              ),
              _buildModuleCard(
                context,
                title:       'Reading',
                description: 'Read an AI-generated article and answer comprehension questions',
                icon:        Icons.menu_book_rounded,
                color:       AppColors.blue,
                // Matches what the module actually does now: ONE passage,
                // then direct MCQs (+ KBAT/inference ones from Standard 5) —
                // no "save & submit" step exists.
                tags:        ['One passage', 'MCQ', 'KBAT thinking'],
                destination: const ReadingModuleScreen(),
              ),
              _buildModuleCard(
                context,
                title:       'Writing',
                description: 'A guided or free composition task — write it on paper or type it in',
                icon:        Icons.edit_rounded,
                color:       AppColors.coralRed,
                // Writing's ONLY 2 modes now (see writing_module_screen.dart)
                // — "Sentence completion"/"Error correction"/"Ordering" were
                // an older design; those formats no longer exist as a
                // standalone module entry.
                tags:        ['Guided composition', 'Free composition', 'Photo or typed'],
                destination: const WritingModuleScreen(),
              ),

              // Available any day here, not just gated to Home's Saturday
              // slot — a student (or this project's own demo/presentation)
              // shouldn't have to wait for a specific day to see it.
              _buildModuleCard(
                context,
                title:       'Weekly Assessment',
                description: 'A check-in covering all 4 skills, based on what your week actually covered',
                icon:        Icons.fact_check_rounded,
                color:       AppColors.purple,
                tags:        ['Vocabulary', 'Grammar', 'Reading', 'Writing'],
                onTap:       () => _startWeeklyAssessment(context),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _startWeeklyAssessment(BuildContext context) {
    // WeeklyAssessmentScreen builds its own plan (batch-generated, like the
    // pre-assessment) and orchestrates the quiz + any Writing task — see
    // its doc comment, including the empty-plan message.
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const WeeklyAssessmentScreen()),
    );
  }

  Widget _buildModuleCard(
    BuildContext context, {
    required String       title,
    required String       description,
    required IconData     icon,
    required Color        color,
    required List<String> tags,
    Widget?                destination,
    VoidCallback?          onTap,
  }) {
    assert(destination != null || onTap != null,
        'either destination or onTap must be given');
    return GestureDetector(
      onTap: onTap ??
          () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => destination!),
              ),
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 12,
                offset: const Offset(0, 4)),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 64, height: 64,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Icon(icon, size: 32, color: color),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          color: color)),
                  const SizedBox(height: 4),
                  Text(description,
                      style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textMid,
                          height: 1.4)),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 6, runSpacing: 6,
                    children: tags.map((tag) => Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(tag,
                          style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: color)),
                    )).toList(),
                  ),
                ],
              ),
            ),
            Icon(Icons.arrow_forward_ios_rounded,
                size: 16, color: Colors.grey[400]),
          ],
        ),
      ),
    );
  }
}