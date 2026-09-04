import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/learner_model.dart';
import '../../services/mastery_service.dart';
import '../../widgets/generating_status.dart';
import '../../theme/app_colors.dart';
import 'adaptive_practice_screen.dart';

const Color _readingColor = AppColors.blue;
const Color _textDark = AppColors.textDark;
const Color _textMid = AppColors.textMid;

// ─────────────────────────────────────────────────────────────────────────────
// Reading module, Pipeline 1: one passage generated per session (`generate`
// with format:"passage"), shown once here, then reused across the whole
// question queue via AdaptivePracticeScreen's contextPassage — replacing the
// old curriculum.dart topic ladder + bespoke question screen. Per-standard
// question count/type is fixed directly (not rung-derived — every slice
// below pins its own format, same mechanism as Vocabulary's mode-cards):
// Standard 1-2 -> 5 direct, 3-4 -> 7 direct, 5-6 -> 8 direct + 2 KBAT.
// ─────────────────────────────────────────────────────────────────────────────
class ReadingModuleScreen extends StatefulWidget {
  /// Fired once the question set is genuinely finished (the queue was
  /// answered all the way through) — NOT when the screen is merely popped.
  /// See EssayWritingScreen.onCompleted's doc comment for why this
  /// distinction matters to callers like Home's Today's Task.
  final VoidCallback? onCompleted;

  const ReadingModuleScreen({super.key, this.onCompleted});

  @override
  State<ReadingModuleScreen> createState() => _ReadingModuleScreenState();
}

class _ReadingModuleScreenState extends State<ReadingModuleScreen> {
  bool _isLoading = true;
  String _errorMessage = '';

  String _articleTitle = '';
  String _articleBody = '';
  int _standard = 3;

  // Whether the whole question set is batch-generating (see
  // MasteryService.batchGenerateQueue) — separate from _isLoading (the
  // passage itself), so a failure here doesn't discard the passage the
  // student already read; they just stay on this screen and can retry.
  bool _startingQuestions = false;

  @override
  void initState() {
    super.initState();
    _loadPassage();
  }

  Future<void> _loadPassage() async {
    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });
    try {
      _standard = await MasteryService().studentStandard();
      final res = await Supabase.instance.client.functions.invoke('generate', body: {
        'skill': 'Reading',
        'sub_skill': 'reading.comprehension',
        'sub_skill_name': 'Reading Comprehension',
        'format': 'passage',
        'standard': _standard,
        'rung': 1,
        'target_difficulty': 0,
        'recent_errors': <String>[],
      });
      final data = res.data;
      final passage = data is Map ? data['passage'] : null;
      if (passage is Map &&
          passage['title'] is String &&
          passage['body'] is String &&
          (passage['body'] as String).trim().isNotEmpty) {
        setState(() {
          _articleTitle = passage['title'] as String;
          _articleBody = passage['body'] as String;
          _isLoading = false;
        });
      } else {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Failed to load article. Please try again.';
        });
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Something went wrong. Please try again.';
      });
      debugPrint('Reading passage load error: $e');
    }
  }

  // Standard 1-2 -> 5 direct, 3-4 -> 7 direct, 5-6 -> 8 direct + 2 KBAT.
  List<PracticeQueueItem> _buildQueue() {
    const code = 'reading.comprehension';
    if (_standard <= 2) {
      return const [PracticeQueueItem(code, 5, format: 'mcq_literal')];
    } else if (_standard <= 4) {
      return const [PracticeQueueItem(code, 7, format: 'mcq_literal')];
    } else {
      return const [
        PracticeQueueItem(code, 8, format: 'mcq_literal'),
        PracticeQueueItem(code, 2, format: 'mcq_inference'),
      ];
    }
  }

  Future<void> _startQuestions() async {
    final queue = _buildQueue();
    setState(() => _startingQuestions = true);

    // The whole question set is generated together, grounded in the SAME
    // passage — one `generate` call per format slice instead of one call
    // per question (previously: one at a time, even though every question
    // was about the exact same passage anyway).
    List<Map<String, dynamic>> items;
    try {
      items = await MasteryService()
          .batchGenerateQueue(queue, contextPassage: _articleBody);
    } catch (e) {
      debugPrint('Reading question batch failed: $e');
      if (!mounted) return;
      setState(() => _startingQuestions = false);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text("Couldn't prepare your questions. Please try again.")));
      return;
    }
    if (!mounted) return;

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => AdaptivePracticeScreen(
          fixedQueue: queue,
          preloadedItems: items,
          resultModuleName: 'Reading',
          resultColor: _readingColor,
          resultIcon: Icons.menu_book_rounded,
          moduleStyle: true,
          contextPassage: _articleBody,
          onSessionComplete: (answered, correct) => widget.onCompleted?.call(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return _loadingScreen();
    if (_errorMessage.isNotEmpty) return _errorScreen();

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: _textDark),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Reading',
            style: TextStyle(
                fontWeight: FontWeight.w900, color: _readingColor, fontSize: 18)),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Level badge
                    Row(children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: _readingColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text('Standard $_standard',
                            style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: _readingColor)),
                      ),
                      const SizedBox(width: 8),
                      Text('${_articleBody.split(' ').length} words',
                          style: TextStyle(fontSize: 12, color: _textMid)),
                    ]),
                    const SizedBox(height: 14),

                    // Title
                    Text(_articleTitle,
                        style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                            color: _textDark,
                            height: 1.3)),
                    const SizedBox(height: 16),

                    Container(height: 2, color: _readingColor.withValues(alpha: 0.15)),
                    const SizedBox(height: 16),

                    // Article body
                    Text(_articleBody,
                        style: const TextStyle(
                            fontSize: 16,
                            color: _textDark,
                            height: 1.9,
                            letterSpacing: 0.1)),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),

            // Go to questions button
            Container(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 28),
              color: Colors.white,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_startingQuestions)
                    const Padding(
                      padding: EdgeInsets.only(bottom: 8),
                      child: Text('Preparing your questions — usually ready in about 20-40s',
                          style: TextStyle(fontSize: 12, color: _textMid)),
                    ),
                  SizedBox(
                    width: double.infinity,
                    height: 54,
                    child: ElevatedButton(
                      onPressed: _startingQuestions ? null : _startQuestions,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _readingColor,
                        disabledBackgroundColor: _readingColor.withValues(alpha: 0.6),
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      child: _startingQuestions
                          ? const SizedBox(
                              width: 22, height: 22,
                              child: CircularProgressIndicator(
                                  color: Colors.white, strokeWidth: 3),
                            )
                          : const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text("I've finished reading",
                                    style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w800,
                                        color: Colors.white)),
                                SizedBox(width: 8),
                                Icon(Icons.arrow_forward_rounded,
                                    color: Colors.white, size: 18),
                              ],
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _loadingScreen() => const Scaffold(
        backgroundColor: Colors.white,
        body: Center(
          child: GeneratingStatus(
            color: _readingColor,
            label: 'Generating your reading article…',
            estimate: 'about 10-15 seconds',
          ),
        ),
      );

  Widget _errorScreen() => Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.wifi_off_rounded, size: 64, color: _readingColor),
                const SizedBox(height: 16),
                Text(_errorMessage, textAlign: TextAlign.center),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: _loadPassage,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _readingColor,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: const Text('Try again', style: TextStyle(color: Colors.white)),
                ),
              ],
            ),
          ),
        ),
      );
}
