import 'package:flutter/material.dart';
import '../../models/learner_model.dart';
import '../../services/mastery_service.dart';
import '../../widgets/challenge_alert_dialog.dart';
import '../../theme/app_colors.dart';
import 'adaptive_practice_screen.dart';

const Color _textDark = AppColors.textDark;
const Color _textMid  = AppColors.textMid;
const Color _bg       = AppColors.moduleBg;

const int kSingleTopicQuestions = 10;
const int kWholeAreaQuestions   = 15;

/// Generic topic/whole-area picker, sourced live from `sub_skills` for a
/// given skill, grouped by `topic_group`. Practising ONE specific topic is
/// always a fixed 10 questions; practising a WHOLE area is always 15 mixed
/// questions (only one of the two selectable at a time). Content is never
/// hard-locked by standard — picking one above the student's standard shows
/// a soft challenge alert first. Starting practice routes through
/// AdaptivePracticeScreen's fixed-queue mode, so Modules sessions update
/// Ability Count through the same generate -> grade -> skill_mastery
/// pipeline as adaptive practice. Modules is the full-breadth practice area
/// (every topic always available); Today's Task is the narrow adaptive pick
/// — a student can always come here afterward for broader practice.
///
/// First built for Grammar, then Writing — shared here so a third/fourth
/// skill (Reading, Vocabulary) can adopt the same picker without duplicating
/// ~350 lines of near-identical UI.
class TopicPickerScreen extends StatefulWidget {
  final String skill; // matches sub_skills.skill
  final String appTitle;
  final String heroTitle;
  final IconData heroIcon;
  final List<Color> gradientColors; // exactly 3 stops
  final Color accentColor;
  final String emptyMessage;

  const TopicPickerScreen({
    super.key,
    required this.skill,
    required this.appTitle,
    required this.heroTitle,
    required this.heroIcon,
    required this.gradientColors,
    required this.accentColor,
    required this.emptyMessage,
  });

  @override
  State<TopicPickerScreen> createState() => _TopicPickerScreenState();
}

class _TopicPickerScreenState extends State<TopicPickerScreen> {
  final _svc = MasteryService();

  bool _loading = true;
  int _standard = 3;
  List<Map<String, dynamic>> _topics = []; // sub_skills rows for this skill

  // Exactly one of these two is active at a time.
  String? _selectedTopicCode;
  String? _selectedArea;

  // Which topic-group cards are expanded (accordion — several can be open
  // at once so the student can compare groups before choosing).
  final Set<String> _expandedGroups = {};

  static const List<IconData> _groupIcons = [
    Icons.category_rounded,
    Icons.auto_awesome_rounded,
    Icons.style_rounded,
    Icons.extension_rounded,
  ];

  bool get _canStart => _selectedTopicCode != null || _selectedArea != null;
  int get _questionCount =>
      _selectedArea != null ? kWholeAreaQuestions : kSingleTopicQuestions;

  // Whether to a spinner while the whole session batch-generates upfront
  // (see MasteryService.batchGenerateQueue) — the session's shape is fully
  // known before the student starts, so it's generated in 1-2 calls
  // instead of one per question.
  bool _starting = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    _standard = await _svc.studentStandard();
    final tax = await _svc.taxonomy();
    final topics = tax.where((t) => t['skill'] == widget.skill).toList()
      ..sort((a, b) =>
          (a['sort_order'] as int? ?? 0).compareTo(b['sort_order'] as int? ?? 0));
    if (mounted) {
      setState(() {
        _topics = topics;
        _loading = false;
      });
    }
  }

  // Preserves sub_skills.sort_order within and across groups.
  List<MapEntry<String, List<Map<String, dynamic>>>> get _groups {
    final map = <String, List<Map<String, dynamic>>>{};
    for (final t in _topics) {
      final group = (t['topic_group'] as String?) ?? (t['name'] as String);
      map.putIfAbsent(group, () => []).add(t);
    }
    return map.entries.toList();
  }

  Future<void> _toggleTopic(Map<String, dynamic> topic) async {
    final code = topic['code'] as String;
    if (_selectedTopicCode == code) {
      setState(() => _selectedTopicCode = null);
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
    if (mounted) {
      setState(() {
        _selectedTopicCode = code;
        _selectedArea = null;
      });
    }
  }

  Future<void> _toggleArea(String groupName, List<Map<String, dynamic>> groupTopics) async {
    if (_selectedArea == groupName) {
      setState(() => _selectedArea = null);
      return;
    }
    final maxStandardMin = groupTopics
        .map((t) => (t['standard_min'] as int?) ?? 1)
        .reduce((a, b) => a > b ? a : b);
    if (_standard < maxStandardMin) {
      final proceed = await showChallengeAlert(
        context,
        topicName: groupName,
        recommendedStandard: maxStandardMin,
      );
      if (!proceed) return;
    }
    if (mounted) {
      setState(() {
        _selectedArea = groupName;
        _selectedTopicCode = null;
      });
    }
  }

  Future<void> _start() async {
    final List<PracticeQueueItem> queue;
    if (_selectedTopicCode != null) {
      queue = [PracticeQueueItem(_selectedTopicCode!, kSingleTopicQuestions)];
    } else {
      final groupTopics = _groups
          .firstWhere((e) => e.key == _selectedArea)
          .value
          .map((t) => t['code'] as String)
          .toList();
      queue = distributeQuestions(groupTopics, kWholeAreaQuestions);
    }

    setState(() => _starting = true);
    List<Map<String, dynamic>> items;
    try {
      items = await _svc.batchGenerateQueue(queue);
    } catch (e) {
      debugPrint('Batch generate failed: $e');
      if (!mounted) return;
      setState(() => _starting = false);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text("Couldn't prepare your questions. Please try again.")));
      return;
    }
    if (!mounted) return;
    setState(() => _starting = false);

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AdaptivePracticeScreen(
          fixedQueue: queue,
          preloadedItems: items,
          resultModuleName: widget.appTitle,
          resultColor: widget.accentColor,
          resultIcon: widget.heroIcon,
          moduleStyle: true,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.accentColor;
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: _textDark),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(widget.appTitle,
            style: TextStyle(
                fontWeight: FontWeight.w900,
                color: color,
                fontSize: 22)),
      ),
      body: _loading
          ? Center(child: CircularProgressIndicator(color: color))
          : _topics.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      widget.emptyMessage,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: _textMid),
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
                                gradient: LinearGradient(
                                  colors: widget.gradientColors,
                                  begin: Alignment.topLeft,
                                  end:   Alignment.bottomRight,
                                ),
                                borderRadius: BorderRadius.circular(20),
                                boxShadow: [
                                  BoxShadow(
                                    color: color.withValues(alpha: 0.3),
                                    blurRadius: 16,
                                    offset: const Offset(0, 6),
                                  ),
                                ],
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(widget.heroIcon, color: Colors.white, size: 32),
                                  const SizedBox(height: 10),
                                  Text(widget.heroTitle,
                                      style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 20,
                                          fontWeight: FontWeight.w900)),
                                  const SizedBox(height: 4),
                                  Text(
                                    _selectedTopicCode != null
                                        ? '1 topic selected — $kSingleTopicQuestions questions'
                                        : _selectedArea != null
                                            ? '"$_selectedArea" — $kWholeAreaQuestions mixed questions'
                                            : 'Pick one topic, or practise a whole area',
                                    style: const TextStyle(
                                        color: Colors.white70, fontSize: 13),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 24),

                            // Topics grouped by area, ordered by sort_order —
                            // one collapsible card per group (mirrors
                            // VocabularyModuleScreen's mode-card list).
                            ..._groups.asMap().entries.map((indexed) {
                              final groupIndex = indexed.key;
                              final groupName = indexed.value.key;
                              final groupTopics = indexed.value.value;
                              final isAreaSelected = _selectedArea == groupName;
                              final isExpanded = _expandedGroups.contains(groupName);
                              final icon = _groupIcons[groupIndex % _groupIcons.length];
                              final preview =
                                  groupTopics.map((t) => t['name'] as String).join(', ');

                              return Container(
                                margin: const EdgeInsets.only(bottom: 14),
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
                                child: Column(
                                  children: [
                                    GestureDetector(
                                      onTap: () => setState(() {
                                        if (isExpanded) {
                                          _expandedGroups.remove(groupName);
                                        } else {
                                          _expandedGroups.add(groupName);
                                        }
                                      }),
                                      child: Padding(
                                        padding: const EdgeInsets.all(18),
                                        child: Row(
                                          children: [
                                            Container(
                                              width: 56,
                                              height: 56,
                                              decoration: BoxDecoration(
                                                color: color.withValues(alpha: 0.12),
                                                borderRadius: BorderRadius.circular(16),
                                              ),
                                              child: Icon(icon, color: color, size: 28),
                                            ),
                                            const SizedBox(width: 14),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Row(
                                                    children: [
                                                      Flexible(
                                                        child: Text(groupName,
                                                            maxLines: 1,
                                                            overflow: TextOverflow.ellipsis,
                                                            style: const TextStyle(
                                                                fontSize: 15,
                                                                fontWeight: FontWeight.w800,
                                                                color: _textDark)),
                                                      ),
                                                      const SizedBox(width: 8),
                                                      Container(
                                                        padding: const EdgeInsets.symmetric(
                                                            horizontal: 8, vertical: 2),
                                                        decoration: BoxDecoration(
                                                          color: color.withValues(alpha: 0.12),
                                                          borderRadius: BorderRadius.circular(6),
                                                        ),
                                                        child: Text(
                                                          '${groupTopics.length} topic${groupTopics.length > 1 ? 's' : ''}',
                                                          style: TextStyle(
                                                              fontSize: 10,
                                                              fontWeight: FontWeight.w700,
                                                              color: color),
                                                        ),
                                                      ),
                                                      if (isAreaSelected) ...[
                                                        const SizedBox(width: 8),
                                                        Icon(Icons.check_circle_rounded,
                                                            color: color, size: 15),
                                                      ],
                                                    ],
                                                  ),
                                                  const SizedBox(height: 4),
                                                  Text(preview,
                                                      maxLines: 1,
                                                      overflow: TextOverflow.ellipsis,
                                                      style: const TextStyle(
                                                          fontSize: 12,
                                                          color: _textMid,
                                                          height: 1.4)),
                                                ],
                                              ),
                                            ),
                                            AnimatedRotation(
                                              turns: isExpanded ? 0.5 : 0,
                                              duration: const Duration(milliseconds: 200),
                                              child: Icon(Icons.keyboard_arrow_down_rounded,
                                                  color: Colors.grey[400]),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                    AnimatedCrossFade(
                                      duration: const Duration(milliseconds: 200),
                                      crossFadeState: isExpanded
                                          ? CrossFadeState.showFirst
                                          : CrossFadeState.showSecond,
                                      firstChild: Padding(
                                        padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            const Divider(height: 1),
                                            const SizedBox(height: 14),
                                            if (groupTopics.length > 1) ...[
                                              GestureDetector(
                                                onTap: () => _toggleArea(groupName, groupTopics),
                                                child: Container(
                                                  padding: const EdgeInsets.symmetric(
                                                      horizontal: 12, vertical: 6),
                                                  decoration: BoxDecoration(
                                                    color: isAreaSelected
                                                        ? color
                                                        : color.withValues(alpha: 0.1),
                                                    borderRadius: BorderRadius.circular(20),
                                                  ),
                                                  child: Text(
                                                    isAreaSelected
                                                        ? 'Whole area selected ✓'
                                                        : 'Practise whole area',
                                                    style: TextStyle(
                                                        fontSize: 11,
                                                        fontWeight: FontWeight.w800,
                                                        color: isAreaSelected
                                                            ? Colors.white
                                                            : color),
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(height: 10),
                                            ],
                                            Wrap(
                                              spacing: 8,
                                              runSpacing: 8,
                                              children: groupTopics.map((topic) {
                                                final code = topic['code'] as String;
                                                final name = topic['name'] as String;
                                                final standardMin =
                                                    (topic['standard_min'] as int?) ?? 1;
                                                final isSelected =
                                                    _selectedTopicCode == code;
                                                final isChallenge = _standard < standardMin;
                                                final dimmed = isAreaSelected;
                                                return GestureDetector(
                                                  onTap: dimmed
                                                      ? null
                                                      : () => _toggleTopic(topic),
                                                  child: Container(
                                                    padding: const EdgeInsets.symmetric(
                                                        horizontal: 14, vertical: 10),
                                                    decoration: BoxDecoration(
                                                      color: isSelected
                                                          ? color.withValues(alpha: 0.15)
                                                          : _bg,
                                                      borderRadius: BorderRadius.circular(12),
                                                      border: Border.all(
                                                        color: isSelected
                                                            ? color
                                                            : AppColors.divider,
                                                        width: isSelected ? 1.5 : 1,
                                                      ),
                                                    ),
                                                    child: Row(
                                                      mainAxisSize: MainAxisSize.min,
                                                      children: [
                                                        Text(name,
                                                            style: TextStyle(
                                                                fontSize: 13,
                                                                color: dimmed
                                                                    ? _textMid.withValues(alpha: 0.5)
                                                                    : isSelected
                                                                        ? color
                                                                        : _textDark,
                                                                fontWeight: isSelected
                                                                    ? FontWeight.w700
                                                                    : FontWeight.w500)),
                                                        if (isChallenge) ...[
                                                          const SizedBox(width: 6),
                                                          const Icon(Icons.star_rounded,
                                                              color: Color(0xFFFFA726),
                                                              size: 15),
                                                        ],
                                                      ],
                                                    ),
                                                  ),
                                                );
                                              }).toList(),
                                            ),
                                          ],
                                        ),
                                      ),
                                      secondChild: const SizedBox(width: double.infinity),
                                    ),
                                  ],
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
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (_starting)
                            const Padding(
                              padding: EdgeInsets.only(bottom: 8),
                              child: Text(
                                  'Preparing your questions — usually ready in about 15-30s',
                                  style: TextStyle(fontSize: 12, color: _textMid)),
                            ),
                          SizedBox(
                            width: double.infinity, height: 54,
                            child: ElevatedButton(
                              onPressed: (_canStart && !_starting) ? _start : null,
                              style: ElevatedButton.styleFrom(
                                backgroundColor:         color,
                                disabledBackgroundColor: Colors.grey[300],
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16)),
                              ),
                              child: _starting
                                  ? const SizedBox(
                                      width: 22, height: 22,
                                      child: CircularProgressIndicator(
                                          color: Colors.white, strokeWidth: 3),
                                    )
                                  : Text(
                                      _canStart
                                          ? 'Start practice ($_questionCount questions)'
                                          : 'Select a topic or a whole area',
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
