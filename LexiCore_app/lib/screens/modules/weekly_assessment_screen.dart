import 'package:flutter/material.dart';
import '../../services/mastery_service.dart';
import '../../widgets/generating_status.dart';
import '../home/home_screen.dart';
import 'adaptive_practice_screen.dart';
import 'essay_writing_screen.dart';
import '../../theme/app_colors.dart';

const Color _assessmentColor = AppColors.purple;
const Color _vocabGrammarColor = AppColors.purple;
const Color _readingColor = AppColors.blue;

/// The weekly check-in — batch-generated upfront (like the pre-assessment,
/// not fetched one item at a time), grounded in what was ACTUALLY scheduled
/// this week across all 4 skills. Orchestrates up to 4 steps in sequence,
/// each its own screen (never crammed together):
///  1. Vocabulary + Grammar quiz.
///  2. Reading's passage, shown on its OWN screen first — same as the real
///     Reading module — THEN its questions, grounded in it. Never the
///     passage hidden behind a "re-read" icon before the student has even
///     seen it once.
///  3. A composition task (EssayWritingScreen), if the student has a
///     Writing history — its own submit/timer UI, not folded into the quiz.
///  4. A single result screen summarising the whole thing.
///
/// Every step's completion is tracked via a real "did this step finish"
/// signal (AdaptivePracticeScreen.onSessionComplete / EssayWritingScreen.
/// onCompleted), NOT just "did the pushed screen eventually get popped" —
/// backing out of ANY step (the X button, the passage screen's back button)
/// stops the whole chain right there and pops back to wherever this screen
/// was opened from, instead of barrelling on into the next section. That
/// same "did it actually finish" signal is what onCompleted below reports
/// to the caller (Home's Today's Task tick).
class WeeklyAssessmentScreen extends StatefulWidget {
  /// Fired once, only when the WHOLE assessment genuinely finished (reached
  /// the final result screen) — never on an early exit from any step.
  final VoidCallback? onCompleted;

  const WeeklyAssessmentScreen({super.key, this.onCompleted});

  @override
  State<WeeklyAssessmentScreen> createState() => _WeeklyAssessmentScreenState();
}

class _WeeklyAssessmentScreenState extends State<WeeklyAssessmentScreen> {
  final _mastery = MasteryService();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _run());
  }

  Future<void> _run() async {
    try {
      final plan = await _mastery.buildWeeklyAssessmentPlan();
      if (plan.isEmpty) {
        _bail("Finish a few practice sessions first, then come back for your weekly check-in!");
        return;
      }

      int totalAnswered = 0;
      int totalCorrect = 0;

      // ── Step 1: Vocabulary + Grammar quiz ────────────────────────────
      if (plan.vocabGrammarQueue.isNotEmpty) {
        List<Map<String, dynamic>> items;
        try {
          items = await _mastery.batchGenerateQueue(plan.vocabGrammarQueue);
        } catch (e) {
          debugPrint('Weekly vocab/grammar batch failed: $e');
          _bail("Couldn't prepare your weekly check-in. Please try again in a moment.");
          return;
        }
        if (!mounted) return;
        var stepCompleted = false;
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => AdaptivePracticeScreen(
              fixedQueue: plan.vocabGrammarQueue,
              preloadedItems: items,
              resultModuleName: 'Vocabulary & Grammar',
              resultColor: _vocabGrammarColor,
              resultIcon: Icons.fact_check_rounded,
              moduleStyle: true,
              skipResultScreen: true,
              onSessionComplete: (answered, correct) {
                stepCompleted = true;
                totalAnswered += answered;
                totalCorrect += correct;
              },
            ),
          ),
        );
        if (!stepCompleted) {
          if (mounted) Navigator.pop(context);
          return;
        }
      }

      // ── Step 2: Reading — the passage first, on its own screen, THEN
      // its questions ─────────────────────────────────────────────────
      if (plan.readingQueue.isNotEmpty) {
        final standard = await _mastery.studentStandard();
        final passage = await _mastery.generatePassage(standard);
        // A failed passage just drops Reading from this week's check-in
        // (see generatePassage's doc comment) — the rest of the assessment
        // still matters more than blocking on one call.
        if (passage != null) {
          if (!mounted) return;
          final continued = await Navigator.push<bool>(
            context,
            MaterialPageRoute(
              builder: (_) => _PassageScreen(title: passage.title, body: passage.body),
            ),
          );
          if (continued != true) {
            if (mounted) Navigator.pop(context);
            return;
          }

          List<Map<String, dynamic>> items;
          try {
            items = await _mastery.batchGenerateQueue(plan.readingQueue, contextPassage: passage.body);
          } catch (e) {
            debugPrint('Weekly reading batch failed: $e');
            _bail("Couldn't prepare your weekly check-in. Please try again in a moment.");
            return;
          }
          if (!mounted) return;
          var stepCompleted = false;
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => AdaptivePracticeScreen(
                fixedQueue: plan.readingQueue,
                preloadedItems: items,
                contextPassage: passage.body,
                resultModuleName: 'Reading',
                resultColor: _readingColor,
                resultIcon: Icons.menu_book_rounded,
                moduleStyle: true,
                skipResultScreen: true,
                onSessionComplete: (answered, correct) {
                  stepCompleted = true;
                  totalAnswered += answered;
                  totalCorrect += correct;
                },
              ),
            ),
          );
          if (!stepCompleted) {
            if (mounted) Navigator.pop(context);
            return;
          }
        }
      }

      // ── Step 3: Writing ───────────────────────────────────────────────
      var writingDone = false;
      if (plan.writingMode != null) {
        if (!mounted) return;
        var stepCompleted = false;
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => EssayWritingScreen(
              mode: plan.writingMode!,
              onCompleted: () => stepCompleted = true,
            ),
          ),
        );
        if (!stepCompleted) {
          if (mounted) Navigator.pop(context);
          return;
        }
        writingDone = true;
      }

      // ── Done — save + show the ONE result screen for the whole thing ──
      if (totalAnswered > 0) {
        await _mastery.saveWeeklyCheckin(itemsAnswered: totalAnswered, itemsCorrect: totalCorrect);
      }
      widget.onCompleted?.call();
      if (!mounted) return;
      await Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => _WeeklyResultScreen(
            answered: totalAnswered,
            correct: totalCorrect,
            writingDone: writingDone,
          ),
        ),
      );
    } catch (e) {
      debugPrint('Weekly assessment failed: $e');
      _bail("Couldn't prepare your weekly check-in. Please try again in a moment.");
    }
  }

  void _bail(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: GeneratingStatus(
          color: _assessmentColor,
          label: 'Preparing your weekly check-in…',
          estimate: 'about 30-60 seconds',
        ),
      ),
    );
  }
}

/// Reading's passage, shown on its own screen exactly like the real Reading
/// module does — full text, up front, before any question exists — rather
/// than generating questions straight away and hiding the passage behind a
/// re-read icon in a quiz app bar. Pops `true` ("I've finished reading") or
/// `false`/nothing (backed out — the caller treats that as bailing the
/// whole assessment, same as the X button anywhere else in this flow).
class _PassageScreen extends StatelessWidget {
  final String title;
  final String body;
  const _PassageScreen({required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: AppColors.textDark),
          onPressed: () => Navigator.pop(context, false),
        ),
        title: const Text('Reading',
            style: TextStyle(fontWeight: FontWeight.w900, color: _readingColor, fontSize: 20)),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                            color: AppColors.textDark,
                            height: 1.3)),
                    const SizedBox(height: 16),
                    Container(height: 2, color: _readingColor.withValues(alpha: 0.15)),
                    const SizedBox(height: 16),
                    Text(body,
                        style: const TextStyle(
                            fontSize: 16, color: AppColors.textDark, height: 1.9, letterSpacing: 0.1)),
                  ],
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 28),
              color: Colors.white,
              child: SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context, true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _readingColor,
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  child: const Text("I've finished reading",
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Colors.white)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The ONE result screen for the whole weekly check-in — pre-assessment
/// style, covering everything that was actually attempted this run instead
/// of leaving the student with no summary at all once it's over.
class _WeeklyResultScreen extends StatelessWidget {
  final int answered;
  final int correct;
  final bool writingDone;
  const _WeeklyResultScreen({
    required this.answered,
    required this.correct,
    required this.writingDone,
  });

  int get _score => answered == 0 ? 0 : ((correct / answered) * 100).round();

  String get _feedback {
    if (answered == 0) return "Nice work finishing this week's writing task!";
    if (_score >= 80) return "Excellent! You've got a strong handle on this week's material.";
    if (_score >= 60) return 'Good job — a little more practice and you\'ll have it fully down.';
    if (_score >= 40) return "Not bad! Revisit this week's topics before the next check-in.";
    return "Keep going — this week's topics are worth another look.";
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 12),
              Center(
                child: Container(
                  width: 90,
                  height: 90,
                  decoration: BoxDecoration(
                    color: _assessmentColor.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.fact_check_rounded, size: 48, color: _assessmentColor),
                ),
              ),
              const SizedBox(height: 16),
              const Text('Weekly Check-In Complete',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: AppColors.textDark)),
              const SizedBox(height: 28),
              if (answered > 0)
                Center(
                  child: Container(
                    width: 140,
                    height: 140,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _assessmentColor.withValues(alpha: 0.1),
                      border: Border.all(color: _assessmentColor.withValues(alpha: 0.4), width: 4),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text('$_score%',
                            style: const TextStyle(
                                fontSize: 36, fontWeight: FontWeight.w900, color: _assessmentColor)),
                        Text('$correct / $answered correct',
                            style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: _assessmentColor.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(_feedback,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.bold, color: _assessmentColor)),
              ),
              if (writingDone) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: AppColors.coralRed.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Row(children: [
                    Icon(Icons.edit_rounded, color: AppColors.coralRed, size: 18),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text('Your composition task is done too — nice work!',
                          style: TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.coralRed)),
                    ),
                  ]),
                ),
              ],
              const Spacer(),
              ElevatedButton(
                onPressed: () => Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (_) => const HomeScreen()),
                  (route) => false,
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _assessmentColor,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: const Text('Back to home',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
