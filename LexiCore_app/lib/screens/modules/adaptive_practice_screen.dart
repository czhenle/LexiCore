import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/learner_model.dart';
import '../../services/mastery_service.dart';
import '../../widgets/tutor_sheet.dart';
import '../../widgets/generating_status.dart';
import '../../theme/app_colors.dart';
import 'result_screen.dart';

/// What _decideFocus() picks for the next item — everything _fetchItem()
/// needs, resolved once so a prefetch and the real fetch never disagree.
typedef _FocusPick = ({
  FocusDecision focus,
  String skill,
  String format,
  String name,
  List<String> recentErrors,
  List<String> recentQuestions,
});

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

  /// Fired once, right when a fixed-queue session finishes (before
  /// navigating to ResultScreen) — lets a caller (e.g. the weekly
  /// assessment) record the session's totals without this screen needing to
  /// know anything about where they get saved.
  final void Function(int itemsAnswered, int itemsCorrect)? onSessionComplete;

  /// When true, renders the older bespoke quiz look (progress-bar header,
  /// filled colored option tiles) used by Grammar/Writing's topic-picker
  /// modules instead of the generic adaptive-practice UI. Purely visual —
  /// the underlying generate/grade/persist engine is identical either way.
  final bool moduleStyle;

  /// Reading's one-passage-per-session mechanism: fetched once by the caller
  /// (ReadingModuleScreen) before this screen opens, then threaded into
  /// every `generate` call for the whole session as `context_passage` so
  /// every question is grounded in the same passage. Null for every other
  /// skill. When set, a "Read passage" button appears so the student can
  /// reread it mid-session.
  final String? contextPassage;

  /// When set, the WHOLE session was already batch-generated upfront (see
  /// MasteryService.batchGenerateQueue) — items are served from this list in
  /// order instead of one `generate` call per question. Always paired with
  /// `fixedQueue` describing the same session (same length, same order);
  /// `fixedQueue` still drives the declarative "Question X of Y" progress
  /// count, this is what's actually shown. Answering/grading/persisting is
  /// completely unaffected — only the fetch side changes. The trade-off:
  /// every item's rung was decided once, from the confirmed-gate snapshot
  /// at generation time, not re-derived as the student answers — a
  /// confirmation window can still resolve mid-session, it just won't
  /// change the content of items already generated in this batch.
  final List<Map<String, dynamic>>? preloadedItems;

  /// When true, a finished fixed-queue session just calls onSessionComplete
  /// and pops itself, instead of navigating to the standalone ResultScreen.
  /// For a caller chaining several of these together as ONE bigger flow
  /// (WeeklyAssessmentScreen: quiz -> passage -> quiz -> composition) —
  /// ResultScreen's own "Back to home"/"Try again" buttons clear the ENTIRE
  /// navigation stack via pushAndRemoveUntil, which would blow away that
  /// chain mid-flow the moment one segment finished. The caller shows its
  /// own single result screen at the very end instead.
  final bool skipResultScreen;

  const AdaptivePracticeScreen({
    super.key,
    this.focusSkill,
    this.fixedQueue,
    this.resultModuleName,
    this.resultColor,
    this.resultIcon,
    this.onSessionComplete,
    this.moduleStyle = false,
    this.contextPassage,
    this.preloadedItems,
    this.skipResultScreen = false,
  });

  @override
  State<AdaptivePracticeScreen> createState() => _AdaptivePracticeScreenState();
}

class _AdaptivePracticeScreenState extends State<AdaptivePracticeScreen> {
  static const _navy = AppColors.navy;
  static const _blue = AppColors.blue;
  static const _bg = AppColors.skyBg;
  static const _moduleTextDark = AppColors.textDark;
  static const _moduleTextMid = AppColors.textMid;

  Color get _accent => widget.resultColor ?? _blue;


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
  /// Non-null when the last generate call failed — drives the retry view.
  String? _loadError;
  final _answerCtrl = TextEditingController();

  // Open-item grading: the `grade` Edge Function judges the student's typed
  // response (LLM-as-judge) instead of asking the student to self-report.
  bool _grading = false;
  String? _gradeFeedback;
  // Fallback ONLY — if the grade call itself fails, degrade to the old
  // reveal-answer + self-report buttons rather than dead-ending the loop.
  bool _gradeUnavailable = false;
  String? _pendingResponse;

  // Fixed-queue mode (widget.fixedQueue != null): (subSkillCode, count) pairs
  // expanded into a flat, front-to-back list; session totals feed ResultScreen.
  List<String> _flatQueue = [];
  // Parallel to _flatQueue — non-null when that slot's PracticeQueueItem
  // pinned a format (Vocabulary's mode-cards), overriding the rung-derived one.
  List<String?> _flatFormatOverride = [];
  int _queuePos = 0;
  int _sessionAnswered = 0;
  int _sessionCorrect = 0;

  // Feedback snapshot (so the panel can show the movement)
  bool _lastCorrect = false;

  // Session error memory: sub_skill_code -> recent wrong-answer notes.
  final Map<String, List<String>> _errorLog = {};

  // Checkpoint / re-assessment gate. A rung only counts as CONFIRMED once
  // the student proves it over a short window, not on a single lucky
  // answer — but unlike the old design, that window is never a separate,
  // visibly-inserted detour. _targetRung/nextTargetRung already hold the
  // served rung at confirmed+1 until it's confirmed, so the window's
  // attempts are just whichever of the student's own next questions happen
  // to land at that rung — same queue, same count, no banner.
  final Map<String, int> _confirmed = {}; // sub_skill -> confirmed rung
  static const int _cpItems = 3;    // attempts in a confirmation window
  static const int _cpPassMark = 2; // correct needed to pass (2 of 3)
  final Map<String, int> _cpWindowRung = {};    // sub_skill -> rung being confirmed
  final Map<String, int> _cpWindowDone = {};
  final Map<String, int> _cpWindowCorrect = {};
  final Map<String, double> _cpWindowPreAbility = {};

  // Prefetch: kicked off as soon as an answer is graded (see
  // _gradeAndPersist), while the feedback panel is showing, so _next() can
  // usually just reveal an item that's already fetched instead of a
  // "Generating…" spinner. Non-null only when a prefetch was started for
  // exactly the transition _next() is about to make; _next() always clears
  // it and falls back to fetching fresh if it's absent or was for something
  // else (e.g. right after a failed-fetch retry).
  ({_FocusPick pick, Future<Map<String, dynamic>> future})? _prefetch;

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
      _flatFormatOverride = [
        for (final q in widget.fixedQueue!)
          for (var i = 0; i < q.count; i++) q.format,
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
    return (rungFormatFallback[skill] ?? rungFormatFallback['Grammar']!)[(rung - 1).clamp(0, 4)];
  }

  /// Picks the next sub-skill/rung/format — the deciding half of what used
  /// to be all of _next(). Mutates _queuePos (fixed-queue mode) exactly
  /// once per call, so this must only ever be called once per transition —
  /// either eagerly by _prefetchNext() or lazily by _next() itself, never
  /// both for the same item. Returns null when a fixed queue is exhausted.
  Future<_FocusPick?> _decideFocus() async {
    final FocusDecision focus;
    // Set only by the fixed-queue branch below, when that slot's
    // PracticeQueueItem pinned a format (Vocabulary's mode-cards) — null
    // everywhere else, falling through to the normal rung-derived format.
    String? queuedFormat;
    if (widget.fixedQueue != null) {
      if (_queuePos >= _flatQueue.length) return null;
      final code = _flatQueue[_queuePos];
      queuedFormat = _flatFormatOverride[_queuePos];
      _queuePos++;
      final m = _states.firstWhere((s) => s.subSkillCode == code);
      // Confirmed-gated, exactly like the adaptive branch below — holds the
      // rung steady at confirmed+1 across as many queue items as it takes to
      // pass its confirmation window, instead of jumping ahead the moment
      // ability crosses the threshold (see _gradeAndPersist).
      final rung = _targetRung(m);
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
    final format = queuedFormat ?? _formatFor(skill, focus.rungNumber);
    final name = _codeToName[focus.subSkillCode] ?? focus.subSkillCode;
    final recentErrors = (_errorLog[focus.subSkillCode] ?? const <String>[])
        .reversed
        .take(3)
        .toList();
    final recentQuestions = await _svc.recentQuestions(focus.subSkillCode);
    return (
      focus: focus,
      skill: skill,
      format: format,
      name: name,
      recentErrors: recentErrors,
      recentQuestions: recentQuestions,
    );
  }

  /// Fire-and-forget, called right when an answer is graded (see
  /// _gradeAndPersist) — decides + starts fetching the NEXT item while the
  /// feedback panel is still showing, so by the time the student taps "Next
  /// question" it's often already in hand. Safe to call unconditionally:
  /// _next() only adopts this if it's still there when needed, and falls
  /// back to a fresh fetch otherwise (queue exhausted, prefetch failed and
  /// was already consumed, or this simply hasn't resolved into anything).
  /// A no-op for a preloaded session — nothing to fetch, and _decideFocus()
  /// would wrongly double-advance _queuePos alongside _next()'s own
  /// preloaded-item branch.
  Future<void> _prefetchNext() async {
    if (widget.preloadedItems != null) return;
    final pick = await _decideFocus();
    if (!mounted || pick == null) return;
    final future = _fetchItem(pick.focus, pick.skill, pick.name, pick.format,
        pick.recentErrors, pick.recentQuestions);
    future.ignore(); // avoid an unhandled-error warning if never consumed below
    _prefetch = (pick: pick, future: future);
  }

  Future<void> _next() async {
    // Batch-preloaded session — no fetch, no prefetch, just serve the next
    // already-generated item. See the `preloadedItems` field comment.
    if (widget.preloadedItems != null) {
      if (_queuePos >= widget.preloadedItems!.length) {
        _finishQueueSession();
        return;
      }
      final item = widget.preloadedItems![_queuePos];
      _queuePos++;
      final code = item['sub_skill'] as String;
      final rung = item['rung'] as int;
      final focus =
          FocusDecision(code, rung, EloConfig.itemDifficulty(_standard, rung), 0);
      setState(() {
        _focus = focus;
        _item = item;
        _fetching = false;
        _loadError = null;
        _selected = null;
        _answered = false;
        _grading = false;
        _gradeFeedback = null;
        _gradeUnavailable = false;
        _pendingResponse = null;
        _answerCtrl.clear();
      });
      return;
    }

    final prefetched = _prefetch;
    _prefetch = null;
    final pick = prefetched?.pick ?? await _decideFocus();
    if (pick == null) {
      _finishQueueSession();
      return;
    }
    setState(() {
      _focus = pick.focus;
      _item = null;
      _fetching = true;
      _loadError = null;
      _selected = null;
      _answered = false;
      _grading = false;
      _gradeFeedback = null;
      _gradeUnavailable = false;
      _pendingResponse = null;
      _answerCtrl.clear();
    });

    // No fake-content fallback: if generation fails the student sees a real
    // error and can retry. Substituting a placeholder item (as this used to)
    // silently recorded bogus attempts into skill_mastery/item_attempts and
    // corrupted the student's ability score.
    Map<String, dynamic> item;
    try {
      item = prefetched != null
          ? await prefetched.future
          : await _fetchItem(pick.focus, pick.skill, pick.name, pick.format,
              pick.recentErrors, pick.recentQuestions);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _fetching = false;
        _item = null;
        // Roll the queue back so retrying re-serves THIS item rather than
        // skipping it — otherwise one failure silently shortens the session.
        if (widget.fixedQueue != null && _queuePos > 0) _queuePos--;
        _loadError = _describeError(e);
      });
      return;
    }
    if (!mounted) return;
    setState(() {
      _item = item;
      _loadError = null;
      _fetching = false;
    });
  }

  /// Turns a fetch failure into something a child can act on, keeping the
  /// technical cause for the debug line underneath.
  String _describeError(Object e) {
    if (e is FunctionException) {
      final detail = e.details ?? e.reasonPhrase ?? '';
      return 'generate failed (HTTP ${e.status})'
          '${detail.toString().isEmpty ? '' : ': $detail'}';
    }
    return e.toString();
  }

  /// Calls the `generate` Edge Function and normalises the returned item.
  Future<Map<String, dynamic>> _fetchItem(FocusDecision focus, String skill,
      String name, String format, List<String> recentErrors,
      List<String> recentQuestions) async {
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
      'recent_questions': recentQuestions,
      if (widget.contextPassage != null) 'context_passage': widget.contextPassage,
    });
    final data = res.data;
    // A 200 with item:null is the validate-and-repair loop giving up after
    // MAX_ATTEMPTS — surface the QA issues rather than a generic message.
    if (data is! Map || data['item'] == null) {
      final qa = data is Map ? data['qa'] : null;
      throw Exception(
          'generate produced no valid item for format "$format"'
          '${qa == null ? '' : ' — QA: $qa'}');
    }
    final item = Map<String, dynamic>.from(data['item'] as Map);
    item['format'] = format;
    item['skill'] = skill;
    item['sub_skill_name'] = name;
    item['rung'] = focus.rungNumber;
    item['is_choice'] = item['options'] != null; // choice vs open item
    return item;
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
    // Open item: judged by the `grade` Edge Function (LLM-as-judge) rather
    // than asking the student to self-report their own correctness.
    final typed = _answerCtrl.text.trim();
    if (typed.isEmpty) return;
    setState(() {
      _pendingResponse = typed;
      _answered = true;
      _grading = true;
      _gradeFeedback = null;
      _gradeUnavailable = false;
    });
    await _gradeOpenResponse(typed);
  }

  /// Calls the `grade` Edge Function to judge a typed open-item response.
  /// Falls back to the old self-report UI (never dead-ends the loop) if the
  /// grading call itself fails — see `_gradeUnavailable`.
  Future<void> _gradeOpenResponse(String response) async {
    try {
      final res =
          await Supabase.instance.client.functions.invoke('grade', body: {
        'question': _item?['question'],
        'student_response': response,
        'model_answer': _item?['answer'],
        'explanation': _item?['explanation'],
        'sub_skill_name': _item?['sub_skill_name'],
        'target_word': _item?['target_word'],
        'rung': _item?['rung'],
        'standard': _standard,
      });
      final data = res.data;
      if (data is! Map || data['correct'] is! bool || data['feedback'] == null) {
        throw Exception('grade returned an invalid verdict');
      }
      final correct = data['correct'] as bool;
      if (!mounted) return;
      setState(() {
        _grading = false;
        _gradeFeedback = data['feedback'].toString();
      });
      await _gradeAndPersist(correct, response, isChoice: false);
    } catch (e) {
      debugPrint('grade call failed: $e');
      if (!mounted) return;
      setState(() {
        _grading = false;
        _gradeUnavailable = true;
      });
    }
  }

  /// Called from the fallback "I got it right" / "I need more practice"
  /// buttons — only shown when `_gradeUnavailable` (the `grade` call failed).
  Future<void> _selfAssess(bool correct) async {
    final response = _pendingResponse ?? '';
    setState(() => _gradeUnavailable = false);
    await _gradeAndPersist(correct, response, isChoice: false);
  }

  /// Shared grading + persistence tail for both choice items (graded
  /// immediately) and open items (graded via student self-assessment).
  Future<void> _gradeAndPersist(bool correct, String response,
      {required bool isChoice}) async {
    if (_focus == null || _item == null) return;
    final m = _states.firstWhere((s) => s.subSkillCode == _focus!.subSkillCode);
    final code = _focus!.subSkillCode;
    final servedRung = _focus!.rungNumber;

    if (!correct) _recordError(isChoice, response);

    m.recordAttempt(rungNumber: servedRung, correct: correct);
    _lastCorrect = correct;
    _sessionAnswered++;
    if (correct) _sessionCorrect++;

    // ── Confirmation window ────────────────────────────────────────────
    // servedRung is always confirmed+1 (both _targetRung and the fixed-queue
    // branch derive it that way) until this advances the gate, so this is
    // just "the next _cpItems answers once mastery first shows" — no extra
    // item is inserted and no separate state is shown; whichever of the
    // student's own next questions land at this rung silently count.
    Map<String, Object>? finishedCheckpoint;
    if (m.masteredRung() >= servedRung && (_confirmed[code] ?? 0) < servedRung) {
      if (_cpWindowRung[code] != servedRung) {
        _cpWindowRung[code] = servedRung;
        _cpWindowDone[code] = 0;
        _cpWindowCorrect[code] = 0;
        _cpWindowPreAbility[code] = m.ability;
      }
      _cpWindowDone[code] = (_cpWindowDone[code] ?? 0) + 1;
      if (correct) _cpWindowCorrect[code] = (_cpWindowCorrect[code] ?? 0) + 1;
      if (_cpWindowDone[code]! >= _cpItems) {
        final passed = _cpWindowCorrect[code]! >= _cpPassMark;
        if (passed) _confirmed[code] = servedRung; // advance the gate
        finishedCheckpoint = {
          'rung': servedRung,
          'preAbility': _cpWindowPreAbility[code] ?? m.ability,
          'passed': passed,
        };
        // Closed either way — a fresh window opens next time mastery is
        // (re)detected, whatever rung is being served then.
        _cpWindowRung.remove(code);
        _cpWindowDone.remove(code);
        _cpWindowCorrect.remove(code);
        _cpWindowPreAbility.remove(code);
      }
    }

    setState(() => _answered = true);

    // Start fetching the next item now, while the feedback panel is up —
    // ability/confirmed are already updated above, so the decision it makes
    // matches what _next() would decide once the student taps Next anyway.
    _prefetchNext();

    // Persist (awaited for correctness).
    await _svc.saveMastery(m);
    await _svc.logAttempt(
      subSkillCode: code,
      rung: servedRung,
      format: _item!['format'] as String,
      itemDifficulty: _focus!.targetDifficulty,
      correct: correct,
      response: response,
      question: _item!['question'] as String?,
    );
    if (finishedCheckpoint != null) {
      await _svc.saveCheckpoint(
        subSkillCode: code,
        rung: finishedCheckpoint['rung'] as int,
        preAbility: finishedCheckpoint['preAbility'] as double,
        postAbility: m.ability,
        passed: finishedCheckpoint['passed'] as bool,
      );
    }
  }

  /// Advances after an answer. Kept as its own method (rather than calling
  /// _next directly from every button) purely so callers read the same way
  /// regardless of what — if anything — happens between an answer and the
  /// next question.
  void _advance() => _next();

  /// Fixed-queue mode only: the queue is exhausted — show ResultScreen with
  /// this session's own totals rather than fetching another item.
  void _finishQueueSession() {
    widget.onSessionComplete?.call(_sessionAnswered, _sessionCorrect);
    if (widget.skipResultScreen) {
      Navigator.of(context).pop();
      return;
    }
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
      backgroundColor: widget.moduleStyle ? Colors.white : _bg,
      appBar: widget.moduleStyle
          ? _moduleAppBar()
          : AppBar(
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

  /// Shown when generation genuinely failed. Deliberately does NOT record an
  /// attempt — nothing reaches skill_mastery/item_attempts from here.
  Widget _errorView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('😕', style: TextStyle(fontSize: 48)),
            const SizedBox(height: 16),
            const Text(
              "We couldn't make your question right now.",
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: _navy, fontSize: 17, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            const Text(
              "This is a problem on our side, not yours — your score hasn't changed.",
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.black54, fontSize: 13),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _next,
              style: ElevatedButton.styleFrom(
                backgroundColor: _blue,
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
              icon: const Icon(Icons.refresh_rounded, size: 20),
              label: const Text('Try again',
                  style: TextStyle(fontWeight: FontWeight.w800)),
            ),
            const SizedBox(height: 28),
            // Technical detail — collapsed so it never confronts a child,
            // but available when debugging a deploy/contract problem.
            ExpansionTile(
              title: const Text('Technical details',
                  style: TextStyle(fontSize: 12, color: Colors.black45)),
              tilePadding: EdgeInsets.zero,
              children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: SelectableText(
                    _loadError ?? '',
                    style: const TextStyle(
                        fontSize: 11, color: Colors.black54, height: 1.4),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoop() {
    if (_loadError != null) return _errorView();

    if (_fetching || _item == null) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_focus != null) _topicHeader(),
            const SizedBox(height: 40),
            GeneratingStatus(
              color: _accent,
              label: 'Generating your question…',
              estimate: 'about 5-10 seconds',
            ),
          ],
        ),
      );
    }

    if (widget.moduleStyle) return _buildModuleLoop();

    final item = _item!;
    final isChoice = item['is_choice'] == true;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _topicHeader(),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item['question'] as String,
                      style: const TextStyle(fontSize: 16)),
                  const SizedBox(height: 16),
                  if (isChoice) ...[
                    _choiceExtras(),
                    ...(item['options'] as Map)
                        .cast<String, dynamic>()
                        .entries
                        .map((e) => _optionTile(e.key, e.value as String)),
                  ] else
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
          else if (_grading)
            _gradingIndicator()
          else if (_gradeUnavailable) ...[
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
              child: const Text('Next question'),
            ),
          ],
        ],
      ),
    );
  }

  // ── Module-style skin (Grammar/Vocabulary/Writing topic/mode pickers) ─────
  // Progress-bar header, filled colored option tiles — while reusing the
  // exact same engine methods above (_submit, _selfAssess, _advance,
  // _gradeAndPersist, checkpoint state) regardless of which module got here.

  PreferredSizeWidget _moduleAppBar() {
    final total = _flatQueue.length;
    final pos = total == 0 ? 0 : _queuePos.clamp(0, total);
    final progress = total == 0 ? 0.0 : pos / total;
    final topic =
        _focus != null ? (_codeToName[_focus!.subSkillCode] ?? '') : '';
    return AppBar(
      backgroundColor: Colors.transparent,
      elevation: 0,
      leading: IconButton(
        icon: const Icon(Icons.close),
        onPressed: () => Navigator.pop(context),
      ),
      title: Column(
        children: [
          Text(topic,
              style: TextStyle(
                  fontSize: 12, color: _accent, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress,
              backgroundColor: _accent.withValues(alpha: 0.15),
              valueColor: AlwaysStoppedAnimation(_accent),
              minHeight: 5,
            ),
          ),
        ],
      ),
      centerTitle: true,
      actions: [
        if (widget.contextPassage != null)
          IconButton(
            icon: Icon(Icons.article_outlined, color: _accent),
            tooltip: 'Read passage again',
            onPressed: _showPassage,
          ),
      ],
    );
  }

  /// Reading only: reopen the session's passage in a scrollable sheet so the
  /// student can reread it mid-quiz without losing their place in the queue.
  void _showPassage() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.85,
        builder: (_, controller) => Container(
          padding: const EdgeInsets.all(20),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(children: [
                Icon(Icons.article_outlined, color: _accent),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text('Passage',
                      style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ]),
              const Divider(),
              Expanded(
                child: SingleChildScrollView(
                  controller: controller,
                  child: Text(widget.contextPassage ?? '',
                      style: const TextStyle(fontSize: 15, height: 1.7)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildModuleLoop() {
    final item = _item!;
    final isChoice = item['is_choice'] == true;
    final options = (item['options'] as Map?)?.cast<String, dynamic>() ?? {};
    final correct = item['correct_answer'] as String?;
    final total = _flatQueue.length;
    final pos = total == 0 ? 1 : _queuePos.clamp(1, total);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            total == 0 ? '' : 'Question $pos of $total',
            style: const TextStyle(fontSize: 13, color: _moduleTextMid),
            textAlign: TextAlign.center,
          ),
          // Reading's KBAT slice (mcq_inference) — flag it so the student
          // knows to think rather than just re-read, same as the old design.
          if (item['format'] == 'mcq_inference') ...[
            const SizedBox(height: 10),
            Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                decoration: BoxDecoration(
                  color: AppColors.purple.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text('🧠 Thinking question',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: AppColors.purple)),
              ),
            ),
          ],
          const SizedBox(height: 16),
          Text(
            item['question'] as String? ?? '',
            style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: _moduleTextDark,
                height: 1.4),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          if (isChoice) ...[
            _choiceExtras(),
            ...options.entries
                .map((e) => _moduleOptionTile(e.key, e.value.toString(), correct)),
          ] else
            _openAnswerField(),
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
                backgroundColor: _accent,
                disabledBackgroundColor: Colors.grey[300],
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape:
                    RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              child: const Text('Submit',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            )
          else if (_grading)
            _gradingIndicator()
          else if (_gradeUnavailable) ...[
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
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
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
                backgroundColor: _accent,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape:
                    RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              child: Text(
                pos < total ? 'Next question' : 'See my result',
                style:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _moduleOptionTile(String key, String label, String? correct) {
    final isSelected = _selected == key;
    final isCorrect = key == correct;
    Color bg = _accent.withValues(alpha: 0.08);
    Color tc = _moduleTextDark;
    if (_answered) {
      if (isCorrect) {
        bg = Colors.green.shade100;
        tc = Colors.green.shade800;
      } else if (isSelected) {
        bg = Colors.red.shade100;
        tc = Colors.red.shade800;
      }
    } else if (isSelected) {
      bg = _accent;
      tc = Colors.white;
    }
    return GestureDetector(
      onTap: _answered ? null : () => setState(() => _selected = key),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        decoration:
            BoxDecoration(color: bg, borderRadius: BorderRadius.circular(14)),
        child: Row(
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.5)),
              child: Center(
                child: Text(key,
                    style: TextStyle(fontWeight: FontWeight.bold, color: tc)),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(label, style: TextStyle(fontSize: 14, color: tc))),
            if (_answered && isCorrect)
              Icon(Icons.check_circle, color: Colors.green.shade700, size: 18),
            if (_answered && isSelected && !isCorrect)
              Icon(Icons.cancel, color: Colors.red.shade700, size: 18),
          ],
        ),
      ),
    );
  }

  bool _canSubmit(bool isChoice) =>
      isChoice ? _selected != null : _answerCtrl.text.trim().isNotEmpty;

  /// Choice-item extras rendered between the question (the short
  /// instruction) and the answer options — each part gets its own line
  /// instead of being crammed into one paragraph:
  ///  1. an image, if this item has one (`vocab_image_mcq`).
  ///  2. a word-bank chip row, if this item has one
  ///     (`cloze_sentence_wordbank`) — the SAME 4 words as the options
  ///     below, just shown as a reference row before the sentence.
  ///  3. the context sentence, if this item has one (`vocab_context_mcq`,
  ///     `cloze_sentence_wordbank`) — the actual sentence-with-blank, kept
  ///     separate from the instruction above it.
  /// Every other skill's choice formats carry none of these fields, so this
  /// is a no-op for them.
  Widget _choiceExtras() {
    final imageB64 = _item?['image_b64'] as String?;
    final contextText = _item?['context_text'] as String?;
    final wordBank = (_item?['word_bank'] as List?)?.cast<dynamic>();
    if (imageB64 == null && contextText == null && (wordBank == null || wordBank.isEmpty)) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (imageB64 != null) ...[
          Center(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.memory(
                base64Decode(imageB64),
                width: 160,
                height: 160,
                fit: BoxFit.contain,
                errorBuilder: (_, _, _) =>
                    const Icon(Icons.image_not_supported_outlined, size: 40),
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],
        if (wordBank != null && wordBank.isNotEmpty) ...[
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: wordBank.map((w) => Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: _accent.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: _accent.withValues(alpha: 0.3)),
              ),
              child: Text(w.toString(),
                  style: TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w700, color: _accent)),
            )).toList(),
          ),
          const SizedBox(height: 12),
        ],
        if (contextText != null) ...[
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: _accent.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _accent.withValues(alpha: 0.2)),
            ),
            child: Text(contextText,
                style: const TextStyle(
                    fontSize: 15, fontStyle: FontStyle.italic, height: 1.5)),
          ),
          const SizedBox(height: 12),
        ],
      ],
    );
  }

  Widget _openAnswerField() {
    final imageB64 = _item?['image_b64'] as String?;
    final hint = _item?['hint'] as String?;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Vocabulary open items only — a picture and/or clue pointing at the
        // one target word the student's sentence should use, shown BEFORE
        // they type so they know what to write about.
        if (imageB64 != null) ...[
          Center(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.memory(
                base64Decode(imageB64),
                width: 160,
                height: 160,
                fit: BoxFit.contain,
                errorBuilder: (_, _, _) =>
                    const Icon(Icons.image_not_supported_outlined, size: 40),
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],
        if (hint != null) ...[
          Text(hint,
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 13,
                  fontStyle: FontStyle.italic,
                  color: Colors.grey.shade700)),
          const SizedBox(height: 12),
        ],
        TextField(
          controller: _answerCtrl,
          enabled: !_answered,
          onChanged: (_) => setState(() {}), // refresh Submit button state
          decoration: InputDecoration(
            hintText: 'Type your answer…',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),
      ],
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
          // Open items: prefer the grader's specific comment on THIS
          // response over the generic "Expected: ..." line.
          if (!isChoice && _gradeFeedback != null) ...[
            const SizedBox(height: 6),
            Text(_gradeFeedback!,
                style: TextStyle(color: Colors.grey.shade800, fontSize: 13)),
          ],
          if (!isChoice && _item?['answer'] != null) ...[
            const SizedBox(height: 6),
            Text('Example: ${_item!['answer']}',
                style: TextStyle(color: Colors.grey.shade700, fontSize: 13)),
          ],
          if (_item?['explanation'] != null) ...[
            const SizedBox(height: 6),
            Text(_item!['explanation'].toString(),
                style: TextStyle(color: Colors.grey.shade700, fontSize: 13)),
          ],
          // Vocabulary's vocab_context_mcq/vocab_synonyms_mcq: a per-option
          // breakdown alongside the plain explanation above, not instead of it.
          if (_item?['explanation_breakdown'] is List &&
              (_item!['explanation_breakdown'] as List).isNotEmpty) ...[
            const SizedBox(height: 8),
            ...(_item!['explanation_breakdown'] as List).map((entry) {
              final map = entry as Map;
              return Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: RichText(
                  text: TextSpan(
                    style: TextStyle(fontSize: 13, color: Colors.grey.shade800),
                    children: [
                      TextSpan(
                          text: '${map['label']} — ',
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                      TextSpan(text: map['note']?.toString() ?? ''),
                    ],
                  ),
                ),
              );
            }),
          ],
        ],
      ),
    );
  }

  /// Shown while the `grade` Edge Function judges a typed open-item answer.
  Widget _gradingIndicator() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
                strokeWidth: 2, color: widget.moduleStyle ? _accent : _blue),
          ),
          const SizedBox(width: 12),
          const Text('Checking your answer…',
              style: TextStyle(color: Colors.black54, fontSize: 13)),
        ],
      ),
    );
  }
}