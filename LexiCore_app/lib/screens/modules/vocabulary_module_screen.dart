import 'package:flutter/material.dart';
import '../../models/learner_model.dart';
import '../../services/mastery_service.dart';
import '../../widgets/generating_status.dart';
import '../../theme/app_colors.dart';
import 'adaptive_practice_screen.dart';

// ── Palette ───────────────────────────────────────────────────────────────────
const Color _vocabColor = AppColors.brightOrange;
const Color _bg = AppColors.moduleBg;
const Color _textDark = AppColors.textDark;
const Color _textMid = AppColors.textMid;

/// One entry in the mode-card list, and how it maps onto `generate` calls.
/// Unlike Grammar/Reading/Writing (rung-derived format from `rung_formats`),
/// every mode here pins its own format(s) — see PracticeQueueItem.format and
/// _shared/generators/vocabulary.ts's header comment for why Vocabulary is
/// the one skill where the mode picked matters as much as the rung.
class _VocabMode {
  final IconData icon;
  final String title;
  final String description;
  final String tag;
  final Color tagColor;
  final String subSkillCode;
  // {format, count} slices making up this mode's 10-question queue — a
  // single slice for mcq-only/open-only modes, two for the modes that mix
  // both (Guess the Image, Word Meaning).
  final List<({String format, int count})> slices;

  const _VocabMode({
    required this.icon,
    required this.title,
    required this.description,
    required this.tag,
    required this.tagColor,
    required this.subSkillCode,
    required this.slices,
  });
}

const List<_VocabMode> _modes = [
  _VocabMode(
    icon: Icons.image_search_rounded,
    title: 'Guess the Image',
    description: 'Look at a picture and choose the correct word',
    tag: 'Visual',
    tagColor: _vocabColor,
    subSkillCode: 'vocab.mode_image',
    slices: [(format: 'vocab_image_mcq', count: 5), (format: 'vocab_image_open', count: 5)],
  ),
  _VocabMode(
    icon: Icons.menu_book_rounded,
    title: 'Word Meaning',
    description: 'Read a definition and choose the matching word',
    tag: 'Reading',
    tagColor: AppColors.lightBlue,
    subSkillCode: 'vocab.mode_meaning',
    slices: [(format: 'vocab_meaning_mcq', count: 5), (format: 'vocab_meaning_open', count: 5)],
  ),
  _VocabMode(
    icon: Icons.edit_note_rounded,
    title: 'Word in Context',
    description: 'Fill in the blank — choose the word that best fits the sentence',
    tag: 'Writing',
    tagColor: AppColors.mintGreen,
    subSkillCode: 'vocab.mode_context',
    slices: [(format: 'vocab_context_mcq', count: 10)],
  ),
  _VocabMode(
    icon: Icons.compare_arrows_rounded,
    title: 'Synonyms & Antonyms',
    description: 'Choose a word that means the same, or the opposite',
    tag: 'Vocabulary',
    tagColor: Color(0xFFEC407A),
    subSkillCode: 'vocab.mode_synonyms',
    slices: [(format: 'vocab_synonyms_mcq', count: 10)],
  ),
  _VocabMode(
    icon: Icons.spellcheck_rounded,
    title: 'Spelling',
    description: 'Look at a picture and type the word correctly',
    tag: 'Spelling',
    tagColor: Color(0xFF7E57C2),
    subSkillCode: 'vocab.mode_spelling',
    slices: [(format: 'vocab_spelling_open', count: 10)],
  ),
];

// ─────────────────────────────────────────────────────────────────────────────
// ENTRY SCREEN — choose practice mode. Each mode is a fixed-format queue on
// its own sub-skill, routed through AdaptivePracticeScreen (Pipeline 1 —
// `generate`/`grade`, real per-item mastery) instead of the retired
// vocabulary edge function + curriculum.dart topic ladder.
// ─────────────────────────────────────────────────────────────────────────────
class VocabularyModuleScreen extends StatelessWidget {
  const VocabularyModuleScreen({super.key});

  // Image-bearing formats generate a picture per item (a real ~20s DALL-E
  // call), sequentially, inside `generate`'s postProcess step — batching a
  // whole 5/10-image slice upfront would mean 100+ seconds before the
  // FIRST question shows, which is worse than one-at-a-time-with-prefetch,
  // not better. Only Guess the Image and Spelling use these; the rest are
  // pure text and batch cleanly.
  static const _imageFormats = {'vocab_image_mcq', 'vocab_image_open', 'vocab_spelling_open'};

  Future<void> _start(BuildContext context, _VocabMode mode) async {
    final queue = [
      for (final slice in mode.slices)
        PracticeQueueItem(mode.subSkillCode, slice.count, format: slice.format),
    ];
    final hasImages = mode.slices.any((s) => _imageFormats.contains(s.format));

    if (hasImages) {
      // Falls back to AdaptivePracticeScreen's own one-at-a-time fetch +
      // prefetch — already tuned for this cost (first item ~20s, later
      // ones often ready while the student answers the one before).
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => AdaptivePracticeScreen(
            fixedQueue: queue,
            resultModuleName: mode.title,
            resultColor: mode.tagColor,
            resultIcon: mode.icon,
            moduleStyle: true,
          ),
        ),
      );
      return;
    }

    // The whole mode's session is generated upfront in 1-2 calls (one per
    // slice) instead of one call per question — see
    // MasteryService.batchGenerateQueue.
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(
        child: GeneratingStatus(
          color: Colors.white,
          label: 'Preparing your questions…',
          estimate: 'about 15-30 seconds',
        ),
      ),
    );

    List<Map<String, dynamic>> items;
    try {
      items = await MasteryService().batchGenerateQueue(queue);
    } catch (e) {
      debugPrint('Batch generate failed: $e');
      if (!context.mounted) return;
      Navigator.pop(context); // close the loading dialog
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text("Couldn't prepare your questions. Please try again.")));
      return;
    }
    if (!context.mounted) return;
    Navigator.pop(context); // close the loading dialog

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AdaptivePracticeScreen(
          fixedQueue: queue,
          preloadedItems: items,
          resultModuleName: mode.title,
          resultColor: mode.tagColor,
          resultIcon: mode.icon,
          moduleStyle: true,
        ),
      ),
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
          'Vocabulary',
          style: TextStyle(
            fontWeight: FontWeight.w900,
            color: _vocabColor,
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
              // Hero
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [
                      Color(0xFFE65100),
                      _vocabColor,
                      Color(0xFFFFB74D),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: _vocabColor.withValues(alpha: 0.3),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.abc_rounded, color: Colors.white, size: 40),
                    SizedBox(height: 12),
                    Text(
                      'Vocabulary Practice',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    SizedBox(height: 6),
                    Text(
                      'Choose how you want to practise words today',
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
            ],
          ),
        ),
      ),
    );
  }

  Widget _modeCard(BuildContext context, _VocabMode mode) {
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
