import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import 'essay_writing_screen.dart';

const Color _writingColor = AppColors.coralRed;
const Color _bg = AppColors.moduleBg;
const Color _textDark = AppColors.textDark;
const Color _textMid = AppColors.textMid;

class _WritingMode {
  final IconData icon;
  final String title;
  final String description;
  final String tag;
  final Color tagColor;
  final String mode; // EssayWritingScreen's mode param

  const _WritingMode({
    required this.icon,
    required this.title,
    required this.description,
    required this.tag,
    required this.tagColor,
    required this.mode,
  });
}

const List<_WritingMode> _modes = [
  _WritingMode(
    icon: Icons.image_outlined,
    title: 'Guided Composition',
    description: 'A picture and an opening sentence — continue the story with a few hints',
    tag: 'Guided',
    tagColor: AppColors.mintGreen,
    mode: 'guided',
  ),
  _WritingMode(
    icon: Icons.edit_rounded,
    title: 'Free Composition',
    description: "Just a topic — write your own essay, on paper or typed",
    tag: 'Free',
    tagColor: _writingColor,
    mode: 'free',
  ),
];

/// Writing's entry screen — 2 mode-cards, mirroring Vocabulary's. Previously
/// a `TopicPickerScreen` over Writing's sub_skills (punctuation/
/// capitalisation, sentence skills, composition), then a single "Start
/// Writing" button into one auto-picked composition format (a third mode,
/// Sentence Refinement, was tried and removed). Those older sub_skills
/// (writing.mechanics/spelling/sentence_completion/sentence_combining/
/// tense_consistency/mode_refine, plus a duplicate old writing.
/// guided_composition/free_composition pair) are NOT wired to anything
/// live anymore — nothing generates for them, and Today's Task/the weekly
/// assessment only ever pick between the 2 modes below. They're still
/// present as orphaned rows in `sub_skills` though (never migrated away),
/// which is a real latent bug: anything that ranks/picks a Writing
/// sub-skill from `skill_mastery` without explicitly filtering to
/// mode_guided/mode_free can pick one of these dead ones instead — see
/// MasteryService.generateStudyPlan()'s Writing-day assignment and
/// buildWeeklyAssessmentPlan()'s writingMode fallback, neither of which
/// filters yet.
class WritingModuleScreen extends StatelessWidget {
  const WritingModuleScreen({super.key});

  void _start(BuildContext context, _WritingMode mode) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => EssayWritingScreen(mode: mode.mode)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: _textDark),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Writing',
          style: TextStyle(
            fontWeight: FontWeight.w900,
            color: _writingColor,
            fontSize: 22,
          ),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [
                      Color(0xFFB71C1C),
                      _writingColor,
                      Color(0xFFEF9A9A),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: _writingColor.withValues(alpha: 0.3),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.edit_rounded, color: Colors.white, size: 40),
                    SizedBox(height: 12),
                    Text(
                      'Writing Practice',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    SizedBox(height: 6),
                    Text(
                      'Choose how you want to practise writing today',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 28),

              const Text(
                'Select a practice mode',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: _textDark,
                ),
              ),
              const SizedBox(height: 14),

              for (final mode in _modes) _modeCard(context, mode),

              const SizedBox(height: 8),
              const Center(
                child: Text(
                  "These 2 are Writing's whole module — Today's Task and "
                  'the Weekly Assessment draw from the same 2 composition '
                  'tasks too.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: _textMid),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _modeCard(BuildContext context, _WritingMode mode) {
    return GestureDetector(
      onTap: () => _start(context, mode),
      child: Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: mode.tagColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(mode.icon, color: mode.tagColor, size: 28),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        mode.title,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: _textDark,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: mode.tagColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          mode.tag,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: mode.tagColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    mode.description,
                    style: const TextStyle(
                      fontSize: 12,
                      color: _textMid,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.arrow_forward_ios_rounded,
              size: 14,
              color: Colors.grey[400],
            ),
          ],
        ),
      ),
    );
  }
}
