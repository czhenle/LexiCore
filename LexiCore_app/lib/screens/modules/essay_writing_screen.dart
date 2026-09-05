import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../services/mastery_service.dart';
import '../../widgets/generating_status.dart';
import '../../theme/app_colors.dart';

const Color _writingColor = AppColors.coralRed;
const Color _bg = AppColors.moduleBg;
const Color _textDark = AppColors.textDark;
const Color _textMid = AppColors.textMid;

/// Composition, redesigned as its own dedicated flow instead of a rung-4/5
/// item reached through the adaptive engine's normal MCQ ladder — essay
/// writing needs its own UI (word count, a timer for the paper option,
/// mistakes/recommendations) that doesn't fit the generic practice loop.
/// Two ways to answer, both ending at the same real grading call:
/// write on paper and submit a photo (transcribed + graded by a vision
/// model), or type directly in the app.
///
/// One screen, 2 modes (WritingModuleScreen's mode-cards) — each its own
/// sub-skill and a PINNED format, not derived from standard/rung the way it
/// used to be:
///  - guided:  an image + opening sentence + a few guiding hints to continue.
///  - free:    a bare topic + a couple of loose hint categories, no scaffold.
/// (A third mode, Sentence Refinement, was tried and removed.)
class EssayWritingScreen extends StatefulWidget {
  final String mode; // 'guided' | 'free'

  /// Fired once, the moment grading actually succeeds (a real verdict came
  /// back) — NOT when the screen is merely popped. A caller that needs to
  /// know "did the student actually finish this task" (Home's Today's Task
  /// completion tick, WeeklyAssessmentScreen's chaining) should use this
  /// instead of assuming a Navigator.push returning means the task is done;
  /// tapping the close (X) button before submitting pops the screen without
  /// ever calling this.
  final VoidCallback? onCompleted;

  const EssayWritingScreen({super.key, required this.mode, this.onCompleted});

  @override
  State<EssayWritingScreen> createState() => _EssayWritingScreenState();
}

class _EssayWritingScreenState extends State<EssayWritingScreen> {
  // Per-Standard minimum word count and paper-writing time limit.
  static const _minWords = {1: 20, 2: 30, 3: 50, 4: 80, 5: 100, 6: 120};
  static const _timeLimitMin = {1: 15, 2: 20, 3: 25, 4: 30, 5: 35, 6: 40};

  final _mastery = MasteryService();
  final _picker = ImagePicker();
  final _answerCtrl = TextEditingController();

  bool _loading = true;
  String? _loadError;
  int _standard = 3;
  Map<String, dynamic>? _item;

  // null = not chosen yet, true = write on paper, false = type in app.
  bool? _writeOnPaper;

  Timer? _timer;
  int _secondsLeft = 0;

  XFile? _photo;
  bool _grading = false;
  String? _gradeError;
  Map<String, dynamic>? _result;

  String get _subSkillName => widget.mode == 'guided' ? 'Guided Composition' : 'Free Composition';
  int get _minWordsForStandard => _minWords[_standard] ?? 50;
  int get _timeLimitForStandard => _timeLimitMin[_standard] ?? 25;
  int get _wordCount => _answerCtrl.text
      .trim()
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty)
      .length;
  bool get _belowMinimum => _wordCount < _minWordsForStandard;

  // A hard "you cannot submit" block over a handful of missing words was
  // too strict — a student who wrote 42/50 words shouldn't be locked out
  // entirely. Allow submitting up to 10 words short; `grade` (told the true
  // target via min_words) still judges the shortfall fairly and reflects it
  // in feedback rather than an outright block.
  static const _wordTolerance = 10;
  int get _submitWordThreshold =>
      (_minWordsForStandard - _wordTolerance).clamp(0, _minWordsForStandard);
  bool get _tooShortToSubmit => _wordCount < _submitWordThreshold;

  @override
  void initState() {
    super.initState();
    _answerCtrl.addListener(() => setState(() {}));
    _load();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _answerCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      _standard = await _mastery.studentStandard();
      // Mode picks the format directly now — not derived from standard/rung
      // the way it used to be (that's still what varies difficulty, just no
      // longer which of the 2 the student gets).
      final (subSkill, format, rung) = widget.mode == 'guided'
          ? ('writing.mode_guided', 'guided_composition', 4)
          : ('writing.mode_free', 'free_composition', 5);
      final res = await Supabase.instance.client.functions.invoke('generate', body: {
        'skill': 'Writing',
        'sub_skill': subSkill,
        'sub_skill_name': _subSkillName,
        'rung': rung,
        'format': format,
        'standard': _standard,
        'target_difficulty': 1000.0 + (_standard - 3) * 80.0,
        'recent_errors': <String>[],
      });
      final data = res.data;
      if (data is Map && data['item'] != null) {
        if (!mounted) return;
        setState(() {
          _item = Map<String, dynamic>.from(data['item'] as Map);
          _loading = false;
        });
      } else {
        throw Exception('generate returned no item');
      }
    } catch (e) {
      debugPrint('Essay prompt load failed: $e');
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = "Couldn't create your writing prompt. Please try again.";
      });
    }
  }

  void _chooseTyped() => _chooseMode(paper: false);
  void _chooseWriteOnPaper() => _chooseMode(paper: true);

  /// Picks (or switches) the submission method. Deliberately does NOT touch
  /// `_item`, `_answerCtrl`'s draft text, or `_photo` — this used to be the
  /// only way to move between typing and paper, but going through it a
  /// second time (student picked one, then wanted to switch) reset
  /// `_writeOnPaper` from a fresh initState, which re-ran `_load()` and
  /// silently handed back a BRAND NEW prompt, discarding whatever they'd
  /// already written. Switching now happens in-place instead — see
  /// `_switchMethodLink` in both flows below — so this only ever needs to
  /// change which UI is shown, never regenerate anything.
  void _chooseMode({required bool paper}) {
    setState(() => _writeOnPaper = paper);
    // Same time limit however they submit, and it should keep counting
    // down across a switch, not hand out a fresh clock every time — only
    // start it the first time a method is chosen.
    if (_timer == null) _startTimer();
  }

  void _startTimer() {
    setState(() => _secondsLeft = _timeLimitForStandard * 60);
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      if (_secondsLeft <= 0) {
        t.cancel();
        return;
      }
      setState(() => _secondsLeft--);
    });
  }

  /// Lets the student change their mind about HOW to submit without losing
  /// their prompt, timer, or (for the typed flow) whatever they've already
  /// written — just swaps which flow is shown.
  Widget _switchMethodLink() => Center(
        child: TextButton.icon(
          onPressed: () => setState(() => _writeOnPaper = !(_writeOnPaper ?? false)),
          icon: Icon(_writeOnPaper == true ? Icons.keyboard_rounded : Icons.edit_note_rounded,
              size: 18, color: _writingColor),
          label: Text(
            _writeOnPaper == true ? 'Switch to typing instead' : 'Switch to writing on paper instead',
            style: TextStyle(color: _writingColor, fontWeight: FontWeight.w700, fontSize: 13),
          ),
        ),
      );

  Future<void> _takePhoto() async {
    final photo = await _picker.pickImage(source: ImageSource.camera, imageQuality: 75);
    if (photo != null && mounted) setState(() => _photo = photo);
  }

  Future<void> _submitTyped() async {
    final typed = _answerCtrl.text.trim();
    if (typed.isEmpty || _grading) return;
    await _submit(studentResponse: typed);
  }

  Future<void> _submitPhoto() async {
    if (_photo == null || _grading) return;
    setState(() {
      _grading = true;
      _gradeError = null;
    });
    try {
      final bytes = await File(_photo!.path).readAsBytes();
      await _submit(image: base64Encode(bytes));
    } catch (e) {
      debugPrint('Photo read failed: $e');
      if (!mounted) return;
      setState(() {
        _grading = false;
        _gradeError = "Couldn't read that photo. Please try again.";
      });
    }
  }

  Future<void> _submit({String? studentResponse, String? image}) async {
    setState(() {
      _grading = true;
      _gradeError = null;
    });
    try {
      final res = await Supabase.instance.client.functions.invoke('grade', body: {
        'question': _item?['question'],
        if (studentResponse != null) 'student_response': studentResponse,
        if (image != null) 'image': image,
        'model_answer': _item?['answer'],
        'explanation': _item?['explanation'],
        'sub_skill_name': _subSkillName,
        'rung': _item?['rung'],
        'standard': _standard,
        'min_words': _minWordsForStandard,
      });
      final data = res.data;
      if (data is! Map || data['correct'] is! bool) {
        throw Exception('grade returned an invalid verdict');
      }
      if (!mounted) return;
      setState(() {
        _grading = false;
        _result = Map<String, dynamic>.from(data);
      });
      widget.onCompleted?.call();
    } catch (e) {
      debugPrint('Grading failed: $e');
      if (!mounted) return;
      setState(() {
        _grading = false;
        _gradeError = "Couldn't grade your writing. Please try again.";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: _textDark),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          _subSkillName,
          style: const TextStyle(fontWeight: FontWeight.w900, color: _writingColor, fontSize: 20),
        ),
      ),
      body: SafeArea(
        child: _loading
            ? Center(
                child: GeneratingStatus(
                  color: _writingColor,
                  label: 'Preparing your writing task…',
                  // guided_composition also runs a DALL-E image call after the
                  // text (see writing.ts postProcess) — measured 20-48s, once
                  // with an outright timeout, vs 5-9s for free_composition
                  // (no image). One static number could not honestly cover
                  // both.
                  estimate: widget.mode == 'guided'
                      ? 'about 20-45 seconds'
                      : 'about 5-15 seconds',
                ),
              )
            : _loadError != null
                ? _errorView()
                : _result != null
                    ? _resultView()
                    : SingleChildScrollView(
                        padding: const EdgeInsets.all(24),
                        child: _promptView(),
                      ),
      ),
    );
  }

  Widget _errorView() => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('😕', style: TextStyle(fontSize: 48)),
              const SizedBox(height: 16),
              Text(_loadError!, textAlign: TextAlign.center),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _load,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _writingColor,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: const Text('Try again', style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
        ),
      );

  Widget _promptCard() {
    final imageB64 = _item?['image_b64'] as String?;
    final hints = (_item?['hints'] as List?)?.cast<dynamic>() ?? const [];
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Guided mode only — the picture grounding the opening sentence.
          if (imageB64 != null) ...[
            Center(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Image.memory(
                  base64Decode(imageB64),
                  width: 180,
                  height: 180,
                  fit: BoxFit.contain,
                  errorBuilder: (_, _, _) =>
                      const Icon(Icons.image_not_supported_outlined, size: 40),
                ),
              ),
            ),
            const SizedBox(height: 14),
          ],
          Text(
            _item?['question'] as String? ?? '',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: _textDark, height: 1.4),
          ),
          // Guided/free modes — a few things they could mention, not a script.
          if (hints.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: hints.map((h) => Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: _writingColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(h.toString(),
                        style: TextStyle(
                            fontSize: 11, color: _writingColor, fontWeight: FontWeight.w700)),
                  )).toList(),
            ),
          ],
          const SizedBox(height: 14),
          Row(
            children: [
              _statChip(Icons.short_text_rounded, 'At least $_minWordsForStandard words'),
              const SizedBox(width: 8),
              _statChip(Icons.timer_outlined, 'Time given: $_timeLimitForStandard min'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _statChip(IconData icon, String label) => Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: _writingColor.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Icon(icon, size: 14, color: _writingColor),
              const SizedBox(width: 6),
              Expanded(
                child: Text(label, style: TextStyle(fontSize: 11, color: _writingColor, fontWeight: FontWeight.w700)),
              ),
            ],
          ),
        ),
      );

  Widget _promptView() {
    if (_writeOnPaper == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _promptCard(),
          const SizedBox(height: 24),
          const Text('How do you want to write it?',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: _textDark)),
          const SizedBox(height: 12),
          _choiceCard(
            icon: Icons.edit_note_rounded,
            title: 'Write on Paper',
            subtitle: 'Write by hand, then take a photo to submit',
            onTap: _chooseWriteOnPaper,
          ),
          const SizedBox(height: 12),
          _choiceCard(
            icon: Icons.keyboard_rounded,
            title: 'Type in App',
            subtitle: 'Type your essay directly here',
            onTap: _chooseTyped,
          ),
        ],
      );
    }
    return _writeOnPaper! ? _paperFlow() : _typedFlow();
  }

  Widget _choiceCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 8, offset: const Offset(0, 3)),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: _writingColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: _writingColor, size: 24),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: _textDark)),
                  const SizedBox(height: 2),
                  Text(subtitle, style: const TextStyle(fontSize: 12, color: _textMid)),
                ],
              ),
            ),
            Icon(Icons.arrow_forward_ios_rounded, size: 14, color: Colors.grey[400]),
          ],
        ),
      ),
    );
  }

  Widget _typedFlow() {
    final minutes = _secondsLeft ~/ 60;
    final seconds = _secondsLeft % 60;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _promptCard(),
        const SizedBox(height: 12),
        // Same time given as the paper option — it starts the moment
        // either is chosen, so this counts down here too, not just there.
        Center(
          child: Text(
            '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}',
            style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w900,
                color: _secondsLeft > 0 ? _writingColor : Colors.grey.shade500),
          ),
        ),
        const SizedBox(height: 4),
        _switchMethodLink(),
        const SizedBox(height: 8),
        TextField(
          controller: _answerCtrl,
          maxLines: 10,
          enabled: !_grading,
          decoration: InputDecoration(
            hintText: 'Write your essay here…',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
            filled: true,
            fillColor: Colors.white,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '$_wordCount / $_minWordsForStandard words',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: _belowMinimum ? Colors.red.shade400 : Colors.green.shade600,
          ),
        ),
        if (_belowMinimum && !_tooShortToSubmit) ...[
          const SizedBox(height: 4),
          Text(
            "A little short, but you can still submit — it'll be graded fairly for what's there.",
            style: TextStyle(fontSize: 11, color: Colors.orange.shade700, fontStyle: FontStyle.italic),
          ),
        ],
        const SizedBox(height: 16),
        if (_gradeError != null) ...[
          _errorBanner(_gradeError!),
          const SizedBox(height: 12),
        ],
        SizedBox(
          height: 54,
          child: ElevatedButton(
            onPressed: (_grading || _tooShortToSubmit) ? null : _submitTyped,
            style: ElevatedButton.styleFrom(
              backgroundColor: _writingColor,
              disabledBackgroundColor: Colors.grey[300],
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            child: _grading
                ? const SizedBox(
                    width: 22, height: 22,
                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3),
                  )
                : const Text('Submit', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ),
      ],
    );
  }

  Widget _paperFlow() {
    final minutes = _secondsLeft ~/ 60;
    final seconds = _secondsLeft % 60;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _promptCard(),
        const SizedBox(height: 12),
        _switchMethodLink(),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            children: [
              Text(
                '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}',
                style: const TextStyle(fontSize: 40, fontWeight: FontWeight.w900, color: _writingColor),
              ),
              const SizedBox(height: 4),
              Text(
                _secondsLeft > 0
                    ? 'Write on paper — take your time'
                    : "Time's up — take a photo whenever you're ready",
                style: const TextStyle(fontSize: 12, color: _textMid),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        if (_photo == null)
          SizedBox(
            height: 54,
            child: OutlinedButton.icon(
              onPressed: _takePhoto,
              icon: const Icon(Icons.camera_alt_rounded),
              label: const Text('Take a Photo'),
              style: OutlinedButton.styleFrom(foregroundColor: _writingColor),
            ),
          )
        else ...[
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Image.file(File(_photo!.path), height: 200, fit: BoxFit.cover),
          ),
          const SizedBox(height: 10),
          TextButton.icon(
            onPressed: _grading ? null : _takePhoto,
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: const Text('Retake photo'),
          ),
          const SizedBox(height: 8),
          if (_gradeError != null) ...[
            _errorBanner(_gradeError!),
            const SizedBox(height: 12),
          ],
          SizedBox(
            height: 54,
            child: ElevatedButton(
              onPressed: _grading ? null : _submitPhoto,
              style: ElevatedButton.styleFrom(
                backgroundColor: _writingColor,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              child: _grading
                  ? const SizedBox(
                      width: 22, height: 22,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3),
                    )
                  : const Text('Submit', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ],
    );
  }

  Widget _errorBanner(String message) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.red.shade50,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(children: [
          Icon(Icons.error_outline, color: Colors.red.shade700, size: 18),
          const SizedBox(width: 8),
          Expanded(child: Text(message, style: TextStyle(color: Colors.red.shade800, fontSize: 13))),
        ]),
      );

  Widget _resultView() {
    final r = _result!;
    final correct = r['correct'] == true;
    final wordCount = r['word_count'] as int?;
    final modelEssay = r['model_essay'] as String?;
    final feedback = r['feedback'] as String? ?? '';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Icon(
              correct ? Icons.emoji_events_rounded : Icons.rate_review_rounded,
              size: 64,
              color: correct ? Colors.green.shade600 : _writingColor,
            ),
          ),
          const SizedBox(height: 12),
          Center(
            child: Text(
              correct ? 'Great writing!' : 'Good effort — let\'s improve it',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: _textDark),
            ),
          ),
          if (wordCount != null) ...[
            const SizedBox(height: 8),
            Center(
              child: Text(
                '$wordCount / $_minWordsForStandard words',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: wordCount >= _minWordsForStandard ? Colors.green.shade600 : Colors.red.shade400,
                ),
              ),
            ),
          ],
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.blue.shade100),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.tips_and_updates_rounded, color: Colors.blue.shade700, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(feedback, style: TextStyle(fontSize: 13, color: Colors.blue.shade800)),
                ),
              ],
            ),
          ),
          if (modelEssay != null && modelEssay.trim().isNotEmpty) ...[
            const SizedBox(height: 16),
            Row(children: [
              Icon(Icons.auto_stories_rounded, color: Colors.green.shade700, size: 18),
              const SizedBox(width: 8),
              const Text('A corrected version of your essay',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: _textDark)),
            ]),
            const SizedBox(height: 4),
            const Text(
              'Same ideas, written the way a strong Standard-level essay would say them — read it alongside what you wrote.',
              style: TextStyle(fontSize: 12, color: _textMid),
            ),
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.green.shade100),
              ),
              child: Text(modelEssay,
                  style: TextStyle(fontSize: 14, color: Colors.green.shade900, height: 1.6)),
            ),
          ],
          const SizedBox(height: 24),
          SizedBox(
            height: 54,
            child: ElevatedButton(
              onPressed: () => Navigator.pop(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: _writingColor,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              child: const Text('Done', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }
}
