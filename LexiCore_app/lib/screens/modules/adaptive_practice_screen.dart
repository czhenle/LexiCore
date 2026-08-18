import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/learner_model.dart';
import '../../services/mastery_service.dart';
import '../../widgets/tutor_sheet.dart';
import 'result_screen.dart';

/// One entry in a fixed practice queue: practise this sub-skill `count` times.
class PracticeQueueItem {
  final String subSkillCode;
  final int count;
  const PracticeQueueItem(this.subSkillCode, this.count);
}

/// The adaptive practice loop (PS1). Reads the seeded mastery map, uses
/// AdaptivePolicy to choose the next sub-skill + rung, serves an item, and
/// writes the answer back through the learner model — updating ability live.
///
/// Items come from the `generate` Edge Function (validate-and-repair). If that
/// call fails, it falls back to a local stub so the loop never dead-ends.
class AdaptivePracticeScreen extends StatefulWidget {
  /// When set, practice is restricted to sub-skills of this skill
  /// (e.g. 'Writing'). When null, the policy picks across all skills.
  final String? focusSkill;

  /// When set, serves items from this fixed queue in order instead of
  /// letting AdaptivePolicy pick freely, and ends on ResultScreen once the
  /// queue is exhausted instead of looping forever. Used by topic-picker
  /// modules (e.g. Grammar) and the weekly check-in. Checkpoints can still
  /// fire mid-queue exactly as in the open-ended mode.
  final List<PracticeQueueItem>? fixedQueue;
  final String? resultModuleName;
  final Color? resultColor;
  final IconData? resultIcon;

  const AdaptivePracticeScreen({
    super.key,
    this.focusSkill,
    this.fixedQueue,
    this.resultModuleName,
    this.resultColor,
    this.resultIcon,
  });

  @override
  State<AdaptivePracticeScreen> createState() => _AdaptivePracticeScreenState();
}

class _AdaptivePracticeScreenState extends State<AdaptivePracticeScreen> {
  static const _navy = Color(0xFF003C8F);
  static const _blue = Color(0xFF1E88E5);
  static const _bg = Color(0xFFF0F8FF);

  // Rung -> format per skill. Fallback only — the live source of truth is the
  // `rung_formats` table (see MasteryService.rungFormats()), used whenever
  // it's reachable and populated. This constant just keeps the loop working
  // if that table is ever empty or unreachable.
  static const Map<String, List<String>> _fallbackFormats = {
    'Vocabulary': ['meaning_match', 'mcq_word_meaning', 'cloze_sentence_wordbank', 'cloze_paragraph_open', 'open_sentence'],
    'Grammar':    ['worked_example', 'mcq_identify_or_error', 'gap_fill', 'transform_or_reorder', 'open_sentence'],
    'Reading':    ['vocab_preview', 'mcq_literal', 'sequence_order', 'mcq_inference', 'open_response'],
    'Writing':    ['punctuation_fix', 'sentence_complete', 'sentence_combine', 'guided_composition', 'free_composition'],
  };

  final _svc = MasteryService();

  bool _loading = true;
  int _standard = 3;
  List<MasteryState> _states = [];
  Map<String, Map<int, String>> _dbFormats = {};
  final Map<String, String> _codeToSkill = {};
  final Map<String, String> _codeToName = {};

  // Current item
  FocusDecision? _focus;
  Map<String, dynamic>? _item;
  String? _selected;
  bool _answered = false;
  bool _fetching = false;
  final _answerCtrl = TextEditingController();

  // Open-item self-assessment: the answer is revealed immediately, and the
  // student marks it right/wrong themselves rather than an exact-match check.
  bool _awaitingSelfAssessment = false;
  String? _pendingResponse;

  // Fixed-queue mode (widget.fixedQueue != null): (subSkillCode, count) pairs
  // expanded into a flat, front-to-back list; session totals feed ResultScreen.
  List<String> _flatQueue = [];
  int _queuePos = 0;
  int _sessionAnswered = 0;
  int _sessionCorrect = 0;

  // Feedback snapshot (so the panel can show the movement)
  bool _lastCorrect = false;

  // Session error memory: sub_skill_code -> recent wrong-answer notes.
  final Map<String, List<String>> _errorLog = {};

  // Checkpoint (re-assessment) state.
  static const int _cpItems = 3;    // items in a checkpoint
  static const int _cpPassMark = 2; // correct needed to pass (2 of 3)
  final Map<String, int> _confirmed = {}; // sub_skill -> confirmed rung
  bool _inCheckpoint = false;
  bool _cpFinished = false;
  bool _cpPassed = false;
  int _cpRung = 0;
  int _cpDone = 0;
  int _cpCorrect = 0;
  double _cpPreAbility = 0;
  String? _cpSubSkill;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    _standard = await _svc.studentStandard();
    _dbFormats = await _svc.rungFormats();
    final tax = await _svc.taxonomy();
    for (final t in tax) {
      _codeToSkill[t['code'] as String] = t['skill'] as String;
      _codeToName[t['code'] as String] = t['name'] as String;
    }
    _states = await _svc.loadMastery(_standard);
    if (widget.fixedQueue != null) {
      _flatQueue = [
        for (final q in widget.fixedQueue!)
          for (var i = 0; i < q.count; i++) q.subSkillCode,
      ];
      // Sub-skills should already be seeded (assessment/skip-path seed every
      // sub-skill), but guard against a gap so the queue never dead-ends.
      for (final code in _flatQueue.toSet()) {
        if (!_states.any((s) => s.subSkillCode == code)) {
          _states.add(MasteryState(subSkillCode: code, standard: _standard));
        }
      }
    }
    // Seed the advancement gate: confirmed = max(assessment level, DB history).
    final dbConfirmed = await _svc.confirmedRungs();
    for (final s in _states) {
      final seed = s.masteredRung();
      final db = dbConfirmed[s.subSkillCode] ?? 0;
      _confirmed[s.subSkillCode] = db > seed ? db : seed;
    }
    if (mounted) {
      setState(() => _loading = false);
      if (_states.isNotEmpty) _next();
    }
  }

  /// The rung to serve for a sub-skill: one above its confirmed level.
  int _targetRung(MasteryState m) =>
      ((_confirmed[m.subSkillCode] ?? m.masteredRung()) + 1).clamp(1, 5);

  String _skillOf(String code) => _codeToSkill[code] ?? 'Grammar';

  /// States the policy may choose from. If a focus skill is set, restrict to
  /// its sub-skills (falling back to all if none are seeded for it yet).
  List<MasteryState> _activeStates() {
    final focus = widget.focusSkill;
    if (focus == null) return _states;
    final filtered =
        _states.where((s) => _skillOf(s.subSkillCode) == focus).toList();
    return filtered.isEmpty ? _states : filtered;
  }
  String _formatFor(String skill, int rung) {
    final fromDb = _dbFormats[skill]?[rung];
    if (fromDb != null) return fromDb;
    return (_fallbackFormats[skill] ?? _fallbackFormats['Grammar']!)[(rung - 1).clamp(0, 4)];
  }

  Future<void> _next() async {
    final FocusDecision focus;
    if (_inCheckpoint && !_cpFinished) {
      // Serve a checkpoint item: same sub-skill, fixed checkpoint rung.
      final m = _states.firstWhere((s) => s.subSkillCode == _cpSubSkill);
      focus = FocusDecision(m.subSkillCode, _cpRung,
          EloConfig.itemDifficulty(m.standard, _cpRung), 0);
    } else if (widget.fixedQueue != null) {
      if (_queuePos >= _flatQueue.length) {
        _finishQueueSession();
        return;
      }
      final code = _flatQueue[_queuePos];
      _queuePos++;
      final m = _states.firstWhere((s) => s.subSkillCode == code);
      final rung = m.nextTargetRung();
      focus = FocusDecision(code, rung, EloConfig.itemDifficulty(_standard, rung), 0);
    } else {
      final picked = AdaptivePolicy().selectNext(_activeStates(), _skillOf);
      final m =
          _states.firstWhere((s) => s.subSkillCode == picked.subSkillCode);
      final rung = _targetRung(m); // gated by confirmed level
      focus = FocusDecision(m.subSkillCode, rung,
          EloConfig.itemDifficulty(m.standard, rung), picked.priority);
    }
    final skill = _skillOf(focus.subSkillCode);
    final format = _formatFor(skill, focus.rungNumber);
    final name = _codeToName[focus.subSkillCode] ?? focus.subSkillCode;
    final recentErrors = (_errorLog[focus.subSkillCode] ?? const <String>[])
        .reversed
        .take(3)
        .toList();
    setState(() {
      _focus = focus;
      _item = null;
      _fetching = true;
      _selected = null;
      _answered = false;
      _awaitingSelfAssessment = false;
      _pendingResponse = null;
      _answerCtrl.clear();
    });

    Map<String, dynamic> item;
    try {
      item = await _fetchItem(focus, skill, name, format, recentErrors);
    } catch (_) {
      item = _stubItem(skill, name, focus.rungNumber, format);
    }
    if (!mounted) return;
    setState(() {
      _item = item;
      _fetching = false;
    });
  }

  /// Calls the `generate` Edge Function and normalises the returned item.
  Future<Map<String, dynamic>> _fetchItem(FocusDecision focus, String skill,
      String name, String format, List<String> recentErrors) async {
    final res =
        await Supabase.instance.client.functions.invoke('generate', body: {
      'skill': skill,
      'sub_skill': focus.subSkillCode,
      'sub_skill_name': name,
      'rung': focus.rungNumber,
      'format': format,
      'standard': _standard,
      'target_difficulty': focus.targetDifficulty,
      'recent_errors': recentErrors,
    });
    final data = res.data;
    if (data is! Map || data['item'] == null) {
      throw Exception('generate returned no item');
    }
    final item = Map<String, dynamic>.from(data['item'] as Map);
    item['format'] = format;
    item['skill'] = skill;
    item['sub_skill_name'] = name;
    item['rung'] = focus.rungNumber;
    item['is_choice'] = item['options'] != null; // choice vs open item
    return item;
  }

  // ── STUB ITEM SOURCE — replace with the `generate` Edge Function ──────────
  Map<String, dynamic> _stubItem(
      String skill, String subSkillName, int rung, String format) {
    final opts = [
      'The correct answer',
      'A wrong option',
      'Another wrong one',
      'Not this either',
    ]..shuffle();
    final keys = ['A', 'B', 'C', 'D'];
    final correctKey = keys[opts.indexOf('The correct answer')];
    return {
      'stub': true,
      'is_choice': true,
      'skill': skill,
      'sub_skill_name': subSkillName,
      'rung': rung,
      'format': format,
      'question':
          'Placeholder item — tap “The correct answer” to answer correctly, '
          'or a wrong one to watch the ability drop.',
      'options': {for (var i = 0; i < 4; i++) keys[i]: opts[i]},
      'correct_answer': correctKey,
    };
  }

  Future<void> _submit() async {
    if (_focus == null || _item == null) return;
    final isChoice = _item!['is_choice'] == true;
    if (isChoice) {
      if (_selected == null) return;
      final correct = _selected == _item!['correct_answer'];
      final response = (_item!['options'] as Map)[_selected]?.toString() ?? '';
      await _gradeAndPersist(correct, response, isChoice: true);
      return;
    }
    // Open item: no exact-match grading (a poor fit for free-text answers —
    // validation/AI-grading is out of scope this phase). Reveal the model's
    // answer/explanation immediately and let the student self-assess instead.
    final typed = _answerCtrl.text.trim();
    if (typed.isEmpty) return;
    setState(() {
      _pendingResponse = typed;
      _awaitingSelfAssessment = true;
      _answered = true;
    });
  }

  /// Called from the "I got it right" / "I need more practice" buttons that
  /// follow an open item's revealed answer.
  Future<void> _selfAssess(bool correct) async {
    final response = _pendingResponse ?? '';
    setState(() => _awaitingSelfAssessment = false);
    await _gradeAndPersist(correct, response, isChoice: false);
  }

  /// Shared grading + persistence tail for both choice items (graded
  /// immediately) and open items (graded via student self-assessment).
  Future<void> _gradeAndPersist(bool correct, String response,
      {required bool isChoice}) async {
    if (_focus == null || _item == null) return;
    final m = _states.firstWhere((s) => s.subSkillCode == _focus!.subSkillCode);

    if (!correct) _recordError(isChoice, response);

    m.recordAttempt(rungNumber: _focus!.rungNumber, correct: correct);
    _lastCorrect = correct;
    _sessionAnswered++;
    if (correct) _sessionCorrect++;

    // ── Checkpoint state machine ─────────────────────────────────────────
    bool cpJustFinished = false;
    if (_inCheckpoint) {
      _cpDone += 1;
      if (correct) _cpCorrect += 1;
      if (_cpDone >= _cpItems) {
        _cpPassed = _cpCorrect >= _cpPassMark;
        if (_cpPassed) _confirmed[_cpSubSkill!] = _cpRung; // advance the gate
        _cpFinished = true;
        cpJustFinished = true;
      }
    } else {
      // Trigger a checkpoint once ability first reaches the target rung.
      final servedRung = _focus!.rungNumber;
      if (m.masteredRung() >= servedRung &&
          (_confirmed[m.subSkillCode] ?? 0) < servedRung) {
        _inCheckpoint = true;
        _cpFinished = false;
        _cpRung = servedRung;
        _cpSubSkill = m.subSkillCode;
        _cpPreAbility = m.ability;
        _cpDone = 0;
        _cpCorrect = 0;
      }
    }

    setState(() => _answered = true);

    // Persist (awaited for correctness).
    await _svc.saveMastery(m);
    await _svc.logAttempt(
      subSkillCode: _focus!.subSkillCode,
      rung: _focus!.rungNumber,
      format: _item!['format'] as String,
      itemDifficulty: _focus!.targetDifficulty,
      correct: correct,
      response: response,
    );
    if (cpJustFinished) {
      await _svc.saveCheckpoint(
        subSkillCode: _cpSubSkill!,
        rung: _cpRung,
        preAbility: _cpPreAbility,
        postAbility: m.ability,
        passed: _cpPassed,
      );
    }
  }

  /// Advances after an answer: exits a finished checkpoint, then serves next.
  void _advance() {
    if (_cpFinished) {
      _inCheckpoint = false;
      _cpFinished = false;
    }
    _next();
  }

  /// Fixed-queue mode only: the queue is exhausted — show ResultScreen with
  /// this session's own totals rather than fetching another item.
  void _finishQueueSession() {
    final score = _sessionAnswered == 0
        ? 0
        : ((_sessionCorrect / _sessionAnswered) * 100).round();
    final topics = widget.fixedQueue!
        .map((q) => _codeToName[q.subSkillCode] ?? q.subSkillCode)
        .toSet()
        .join(', ');
    Navigator.of(context).pushReplacement(MaterialPageRoute(
      builder: (_) => ResultScreen(
        moduleName: widget.resultModuleName ?? 'Practice',
        moduleColor: widget.resultColor ?? _blue,
        moduleIcon: widget.resultIcon ?? Icons.bolt_rounded,
        unitNumber: 1,
        topic: topics,
        score: score,
        totalQuestions: _sessionAnswered,
        correctAnswers: _sessionCorrect,
      ),
    ));
  }

  /// Opens the Socratic hint chat for the current item (PS3).
  void _openTutor() {
    if (_item == null) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => TutorSheet(item: _item!, standard: _standard),
    );
  }

  /// Stores a concise note about a wrong answer so the next question on this
  /// sub-skill can target the same weakness (performance-aware generation).
  void _recordError(bool isChoice, String response) {
    final q = (_item!['question'] ?? '').toString();
    final note = isChoice
        ? 'Q: "$q" — chose "${(_item!['options'] as Map)[_selected]}", '
            'correct "${(_item!['options'] as Map)[_item!['correct_answer']]}"'
        : 'Q: "$q" — wrote "$response", expected "${_item!['answer']}"';
    final list = _errorLog.putIfAbsent(_focus!.subSkillCode, () => []);
    list.add(note);
    if (list.length > 5) list.removeAt(0); // keep only the recent few
  }

  @override
  void dispose() {
    _answerCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _blue,
        foregroundColor: Colors.white,
        title: Text(widget.focusSkill != null
            ? '${widget.focusSkill} Practice'
            : 'Adaptive Practice'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _states.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'No mastery data yet.\nComplete the assessment first so the '
                      'mastery map can be seeded.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : _buildLoop(),
    );
  }

  Widget _buildLoop() {
    if (_fetching || _item == null) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_focus != null) _topicHeader(),
            const SizedBox(height: 40),
            const Center(child: CircularProgressIndicator()),
            const SizedBox(height: 12),
            const Center(child: Text('Generating your question…')),
          ],
        ),
      );
    }

    final item = _item!;
    final isChoice = item['is_choice'] == true;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _topicHeader(),
          const SizedBox(height: 16),
          if (_inCheckpoint) _checkpointBanner(),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item['question'] as String,
                      style: const TextStyle(fontSize: 16)),
                  const SizedBox(height: 16),
                  if (isChoice)
                    ...(item['options'] as Map)
                        .cast<String, dynamic>()
                        .entries
                        .map((e) => _optionTile(e.key, e.value as String))
                  else
                    _openAnswerField(),
                ],
              ),
            ),
          ),
          if (!_answered)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _openTutor,
                icon: const Icon(Icons.lightbulb_outline,
                    color: Color(0xFFF9A825)),
                label: const Text("I'm stuck — ask Lexi for a hint"),
              ),
            ),
          const SizedBox(height: 16),
          if (!_answered)
            ElevatedButton(
              onPressed: _canSubmit(isChoice) ? _submit : null,
              style: ElevatedButton.styleFrom(
                  backgroundColor: _blue, foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14)),
              child: const Text('Submit'),
            )
          else if (_awaitingSelfAssessment) ...[
            _revealAnswer(),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _selfAssess(false),
                  style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14)),
                  child: const Text('I need more practice'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: () => _selfAssess(true),
                  style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green, foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14)),
                  child: const Text('I got it right'),
                ),
              ),
            ]),
          ] else ...[
            _feedback(),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: _advance,
              style: ElevatedButton.styleFrom(
                  backgroundColor: _navy, foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14)),
              child: Text(_cpFinished
                  ? 'Continue'
                  : _inCheckpoint
                      ? 'Next checkpoint item ($_cpDone/$_cpItems)'
                      : 'Next question'),
            ),
          ],
        ],
      ),
    );
  }

  bool _canSubmit(bool isChoice) =>
      isChoice ? _selected != null : _answerCtrl.text.trim().isNotEmpty;

  Widget _openAnswerField() {
    return TextField(
      controller: _answerCtrl,
      enabled: !_answered,
      onChanged: (_) => setState(() {}), // refresh Submit button state
      decoration: InputDecoration(
        hintText: 'Type your answer…',
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  Widget _optionTile(String key, String label) {
    final isSel = _selected == key;
    Color border = Colors.grey.shade300;
    if (_answered) {
      if (key == _item!['correct_answer']) {
        border = Colors.green;
      } else if (isSel) {
        border = Colors.red;
      }
    } else if (isSel) {
      border = _blue;
    }
    return GestureDetector(
      onTap: _answered ? null : () => setState(() => _selected = key),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          border: Border.all(color: border, width: 2),
          borderRadius: BorderRadius.circular(10),
          color: isSel ? border.withValues(alpha: 0.06) : Colors.white,
        ),
        child: Text('$key.  $label'),
      ),
    );
  }

  // Minimal, kid-friendly header — just what skill/topic you're on.
  Widget _topicHeader() {
    final focus = _focus!;
    final name = _codeToName[focus.subSkillCode] ?? focus.subSkillCode;
    final skill = _skillOf(focus.subSkillCode);
    const emoji = {
      'Vocabulary': '\u{1F4D6}',
      'Grammar': '\u{270F}\u{FE0F}',
      'Reading': '\u{1F4DA}',
      'Writing': '\u{270D}\u{FE0F}',
    };
    return Row(children: [
      Text(emoji[skill] ?? '\u{2B50}', style: const TextStyle(fontSize: 22)),
      const SizedBox(width: 8),
      Expanded(
        child: Text('$skill \u00B7 $name',
            style: const TextStyle(
                fontWeight: FontWeight.w800, color: _navy, fontSize: 15)),
      ),
    ]);
  }

  Widget _checkpointBanner() {
    final color = _cpFinished
        ? (_cpPassed ? Colors.green : Colors.red)
        : const Color(0xFF6A1B9A);
    final text = _cpFinished
        ? (_cpPassed
            ? 'Checkpoint passed — level $_cpRung confirmed! ($_cpCorrect/$_cpItems)'
            : 'Checkpoint not passed — keep practising level $_cpRung '
                '($_cpCorrect/$_cpItems)')
        : 'Checkpoint: prove level $_cpRung   ·   $_cpDone/$_cpItems answered';
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Row(children: [
        Icon(
            _cpFinished
                ? (_cpPassed ? Icons.verified : Icons.refresh)
                : Icons.flag,
            size: 18,
            color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Text(text,
              style: TextStyle(
                  fontWeight: FontWeight.w700, color: color, fontSize: 13)),
        ),
      ]),
    );
  }

  /// Shown for open items after Submit, before the student self-assesses —
  /// no correct/incorrect verdict yet, just the model's own answer.
  Widget _revealAnswer() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.blueGrey.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(children: [
            Icon(Icons.visibility_outlined, color: Colors.blueGrey),
            SizedBox(width: 8),
            Text('Here\'s a model answer — how did you do?',
                style: TextStyle(fontWeight: FontWeight.w700)),
          ]),
          if (_item?['answer'] != null) ...[
            const SizedBox(height: 6),
            Text('${_item!['answer']}',
                style: TextStyle(color: Colors.grey.shade800, fontSize: 14, fontWeight: FontWeight.w600)),
          ],
          if (_item?['explanation'] != null) ...[
            const SizedBox(height: 6),
            Text(_item!['explanation'].toString(),
                style: TextStyle(color: Colors.grey.shade700, fontSize: 13)),
          ],
        ],
      ),
    );
  }

  Widget _feedback() {
    final isChoice = _item?['is_choice'] == true;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: (_lastCorrect ? Colors.green : Colors.red).withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(_lastCorrect ? Icons.check_circle : Icons.cancel,
                color: _lastCorrect ? Colors.green : Colors.red),
            const SizedBox(width: 8),
            Text(_lastCorrect ? 'Correct!' : 'Not quite.',
                style: const TextStyle(fontWeight: FontWeight.w700)),
          ]),
          if (!isChoice && _item?['answer'] != null) ...[
            const SizedBox(height: 6),
            Text('Expected: ${_item!['answer']}',
                style: TextStyle(color: Colors.grey.shade700, fontSize: 13)),
          ],
          if (_item?['explanation'] != null) ...[
            const SizedBox(height: 6),
            Text(_item!['explanation'].toString(),
                style: TextStyle(color: Colors.grey.shade700, fontSize: 13)),
          ],
        ],
      ),
    );
  }
}