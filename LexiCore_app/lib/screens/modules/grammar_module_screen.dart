import 'package:flutter/material.dart';
import '../../services/mastery_service.dart';
import '../../widgets/challenge_alert_dialog.dart';
import 'adaptive_practice_screen.dart';

const Color _grammarColor = Color(0xFF4DB6AC);
const Color _bg           = Color(0xFFF5F5F7);
const Color _textDark     = Color(0xFF1A1A2E);
const Color _textMid      = Color(0xFF6B7280);

// ─────────────────────────────────────────────────────────────────────────────
// ENTRY SCREEN — topic checklist, sourced live from `sub_skills` (skill =
// 'Grammar'). Content is never hard-locked by standard: every topic is always
// selectable, but picking one above the student's standard shows a soft
// "this might be a bit challenging" alert first (see challenge_alert_dialog).
// Starting practice routes through AdaptivePracticeScreen's fixed-queue mode,
// so a Grammar-module session updates Ability Count through the exact same
// generate -> grade -> skill_mastery pipeline as adaptive practice.
// ─────────────────────────────────────────────────────────────────────────────
class GrammarModuleScreen extends StatefulWidget {
  const GrammarModuleScreen({super.key});

  @override
  State<GrammarModuleScreen> createState() => _GrammarModuleScreenState();
}

class _GrammarModuleScreenState extends State<GrammarModuleScreen> {
  final _svc = MasteryService();

  bool _loading = true;
  int _standard = 3;
  List<Map<String, dynamic>> _topics = []; // sub_skills rows for Grammar
  final Set<String> _selected = {}; // selected sub_skill codes
  int _questionsPerTopic = 3;

  bool get _canStart => _selected.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    _standard = await _svc.studentStandard();
    final tax = await _svc.taxonomy();
    final topics = tax.where((t) => t['skill'] == 'Grammar').toList()
      ..sort((a, b) =>
          (a['sort_order'] as int? ?? 0).compareTo(b['sort_order'] as int? ?? 0));
    if (mounted) {
      setState(() {
        _topics = topics;
        _loading = false;
      });
    }
  }

  Future<void> _toggle(Map<String, dynamic> topic) async {
    final code = topic['code'] as String;
    if (_selected.contains(code)) {
      setState(() => _selected.remove(code));
      return;
    }
    final standardMin = (topic['standard_min'] as int?) ?? 1;
    if (_standard < standardMin) {
      final proceed = await showChallengeAlert(
        context,
        topicName: topic['name'] as String,
        recommendedStandard: standardMin,
      );
      if (!proceed) return;
    }
    if (mounted) setState(() => _selected.add(code));
  }

  void _start() {
    final queue = _selected
        .map((code) => PracticeQueueItem(code, _questionsPerTopic))
        .toList();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AdaptivePracticeScreen(
          fixedQueue: queue,
          resultModuleName: 'Grammar',
          resultColor: _grammarColor,
          resultIcon: Icons.rule_rounded,
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
        title: const Text('Grammar',
            style: TextStyle(
                fontWeight: FontWeight.w900,
                color: _grammarColor,
                fontSize: 22)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _grammarColor))
          : _topics.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'No Grammar topics available yet.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: _textMid),
                    ),
                  ),
                )
              : Column(
                  children: [
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Hero card
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(20),
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  colors: [Color(0xFF00796B), Color(0xFF4DB6AC),
                                           Color(0xFF80CBC4)],
                                  begin: Alignment.topLeft,
                                  end:   Alignment.bottomRight,
                                ),
                                borderRadius: BorderRadius.circular(20),
                                boxShadow: [
                                  BoxShadow(
                                    color: _grammarColor.withValues(alpha: 0.3),
                                    blurRadius: 16,
                                    offset: const Offset(0, 6),
                                  ),
                                ],
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Icon(Icons.rule_rounded,
                                      color: Colors.white, size: 32),
                                  const SizedBox(height: 10),
                                  const Text('Grammar Practice',
                                      style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 20,
                                          fontWeight: FontWeight.w900)),
                                  const SizedBox(height: 4),
                                  Text(
                                    _selected.isEmpty
                                        ? 'Select topics below to practise'
                                        : '${_selected.length} topic${_selected.length > 1 ? 's' : ''} selected',
                                    style: const TextStyle(
                                        color: Colors.white70, fontSize: 13),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 24),

                            // Questions per topic selector
                            const Text('Questions per topic',
                                style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w800,
                                    color: _textDark)),
                            const SizedBox(height: 10),
                            Row(
                              children: [3, 5, 10].map((n) {
                                final selected = n == _questionsPerTopic;
                                return GestureDetector(
                                  onTap: () =>
                                      setState(() => _questionsPerTopic = n),
                                  child: Container(
                                    margin: const EdgeInsets.only(right: 10),
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 20, vertical: 10),
                                    decoration: BoxDecoration(
                                      color: selected
                                          ? _grammarColor
                                          : Colors.white,
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: selected
                                            ? _grammarColor
                                            : const Color(0xFFE5E7EB),
                                      ),
                                    ),
                                    child: Text('$n',
                                        style: TextStyle(
                                            fontWeight: FontWeight.w800,
                                            color: selected
                                                ? Colors.white
                                                : _textMid,
                                            fontSize: 15)),
                                  ),
                                );
                              }).toList(),
                            ),
                            const SizedBox(height: 24),

                            // Topic checklist — flat, ordered by sort_order.
                            // (Category groupings aren't representable with
                            // today's schema — sub_skills has no group column.)
                            ..._topics.map((topic) {
                              final code = topic['code'] as String;
                              final name = topic['name'] as String;
                              final standardMin =
                                  (topic['standard_min'] as int?) ?? 1;
                              final isSelected = _selected.contains(code);
                              final isChallenge = _standard < standardMin;
                              return GestureDetector(
                                onTap: () => _toggle(topic),
                                child: Container(
                                  margin: const EdgeInsets.only(bottom: 8),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 16, vertical: 12),
                                  decoration: BoxDecoration(
                                    color: isSelected
                                        ? _grammarColor.withValues(alpha: 0.1)
                                        : Colors.white,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: isSelected
                                          ? _grammarColor
                                          : const Color(0xFFE5E7EB),
                                      width: isSelected ? 1.5 : 1,
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      AnimatedContainer(
                                        duration:
                                            const Duration(milliseconds: 200),
                                        width: 22, height: 22,
                                        decoration: BoxDecoration(
                                          shape:  BoxShape.circle,
                                          color:  isSelected
                                              ? _grammarColor
                                              : Colors.transparent,
                                          border: Border.all(
                                            color: isSelected
                                                ? _grammarColor
                                                : const Color(0xFFD1D5DB),
                                            width: 1.5,
                                          ),
                                        ),
                                        child: isSelected
                                            ? const Icon(Icons.check,
                                                color: Colors.white,
                                                size: 13)
                                            : null,
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Text(name,
                                            style: TextStyle(
                                                fontSize: 14,
                                                color: isSelected
                                                    ? _grammarColor
                                                    : _textDark,
                                                fontWeight: isSelected
                                                    ? FontWeight.w700
                                                    : FontWeight.w500)),
                                      ),
                                      if (isChallenge)
                                        const Padding(
                                          padding: EdgeInsets.only(left: 8),
                                          child: Icon(Icons.star_rounded,
                                              color: Color(0xFFFFA726), size: 18),
                                        ),
                                    ],
                                  ),
                                ),
                              );
                            }),
                          ],
                        ),
                      ),
                    ),

                    // Start button (sticky at bottom)
                    Container(
                      padding: const EdgeInsets.fromLTRB(24, 12, 24, 28),
                      color: _bg,
                      child: Column(
                        children: [
                          if (_selected.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Text(
                                '${_selected.length * _questionsPerTopic} questions total',
                                style: TextStyle(
                                    fontSize: 13, color: _textMid),
                              ),
                            ),
                          SizedBox(
                            width: double.infinity, height: 54,
                            child: ElevatedButton(
                              onPressed: _canStart ? _start : null,
                              style: ElevatedButton.styleFrom(
                                backgroundColor:         _grammarColor,
                                disabledBackgroundColor: Colors.grey[300],
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16)),
                              ),
                              child: Text(
                                _canStart ? 'Start practice' : 'Select at least one topic',
                                style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.white),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
    );
  }
}
