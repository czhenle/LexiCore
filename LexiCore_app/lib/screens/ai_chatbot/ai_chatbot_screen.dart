import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../services/supabase_service.dart';
import '../../services/api_service.dart';
import '../../services/mastery_service.dart';
import '../../services/chat_history_service.dart';
import '../../theme/app_colors.dart';

class AiChatbotScreen extends StatefulWidget {
  const AiChatbotScreen({super.key});

  @override
  State<AiChatbotScreen> createState() => _AiChatbotScreenState();
}

class _AiChatbotScreenState extends State<AiChatbotScreen> {
  static const Color _bg = AppColors.skyBg;
  static const Color _navyText = AppColors.navy;
  static const Color _skyLight = AppColors.skyLight;
  static const Color _mintGreen = AppColors.mintGreen;
  static const Color _buttonBlue = AppColors.blue;

  final _supabaseService = SupabaseService();
  final _apiService = ApiService();
  final _chatHistory = ChatHistoryService();
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();

  final List<Map<String, dynamic>> _messages = [];
  final List<Map<String, String>> _history = []; // conversation memory sent to Lexi
  final _picker = ImagePicker();
  File? _pendingImage;
  bool _isTyping = false;
  String _weakness = 'Grammar';
  String _username = 'there';
  int _standard = 3;

  @override
  void initState() {
    super.initState();
    _loadStudentContext();
  }

  Future<void> _loadStudentContext() async {
    try {
      final profile = await _supabaseService.getStudentProfile();
      final summary = await MasteryService().masterySummary();

      // Check if the widget is still active before updating local variables
      if (!mounted) return;

      setState(() {
        _username = (profile?['username'] as String?) ?? 'friend';
        _standard = (profile?['standard'] as int?) ?? 3;
        if (summary != null) _weakness = summary.weakest;
      });
    } catch (e) {
      debugPrint(e.toString());
    }

    // Restore last time's conversation, if there is one, instead of always
    // starting fresh — the welcome message below is only ever shown when
    // there's nothing to restore (it isn't itself persisted, so it never
    // clutters a real conversation's history on later restores).
    final restored = await _chatHistory.loadRecent();
    if (!mounted) return;

    if (restored.isNotEmpty) {
      setState(() {
        for (final row in restored) {
          final text = row['text'] as String?;
          if (row['role'] == 'user') {
            _messages.add({'role': 'user', 'text': text ?? ''});
            if (text != null && text.trim().isNotEmpty) {
              _history.add({'role': 'user', 'text': text});
            }
          } else {
            final data = row['data'] is Map
                ? Map<String, dynamic>.from(row['data'] as Map)
                : {'type': 'simple_answer', 'text': text ?? ''};
            _messages.add({'role': 'lexi', 'data': data});
            _history.add({'role': 'lexi', 'text': _replyToText(data)});
          }
        }
        if (_history.length > 20) _history.removeRange(0, _history.length - 20);
      });
      return;
    }

    // Final check before adding the initial welcome message
    if (mounted) {
      setState(() {
        _messages.add({
          'role': 'lexi',
          'data': {
            'type': 'simple_answer',
            'text':
                'Hi $_username! I\'m Lexi 🦉 I heard you want to practice your $_weakness. What shall we talk about?',
          },
        });
      });
    }
  }

  Future<void> _pickImage(ImageSource source) async {
    final picked = await _picker.pickImage(
        source: source, maxWidth: 1024, imageQuality: 70);
    if (picked != null && mounted) {
      setState(() => _pendingImage = File(picked.path));
    }
  }

  void _showImageSourceSheet() {
    showModalBottomSheet(
      context: context,
      builder: (_) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.camera_alt, color: _buttonBlue),
            title: const Text('Take a photo'),
            onTap: () {
              Navigator.pop(context);
              _pickImage(ImageSource.camera);
            },
          ),
          ListTile(
            leading: const Icon(Icons.photo_library, color: _buttonBlue),
            title: const Text('Choose from gallery'),
            onTap: () {
              Navigator.pop(context);
              _pickImage(ImageSource.gallery);
            },
          ),
        ]),
      ),
    );
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    final image = _pendingImage;
    if (text.isEmpty && image == null) return;

    String? imageB64;
    if (image != null) {
      imageB64 = base64Encode(await image.readAsBytes());
    }

    setState(() {
      _messages.add({
        'role': 'user',
        'text': text,
        if (imageB64 != null) 'image': imageB64,
      });
      _isTyping = true;
      _pendingImage = null;
    });
    _messageController.clear();
    _scrollToBottom();

    final historyToSend = List<Map<String, String>>.from(_history);
    if (text.isNotEmpty) {
      _history.add({'role': 'user', 'text': text});
      // Fire-and-forget — the image itself isn't persisted (see
      // ChatHistoryService.append's doc comment).
      _chatHistory.append(role: 'user', text: text);
    }

    final reply = await _apiService.chatWithLexi(
      text.isEmpty ? 'Please help me with this.' : text,
      _standard,
      weakness: _weakness,
      imageBase64: imageB64,
      history: historyToSend,
    );

    setState(() {
      _isTyping = false;
      _messages.add({
        'role': 'lexi',
        'data': reply,
      });
    });
    _history.add({'role': 'lexi', 'text': _replyToText(reply)});
    if (_history.length > 20) _history.removeRange(0, _history.length - 20);
    _chatHistory.append(role: 'lexi', data: reply); // fire-and-forget
    _scrollToBottom();
  }

  /// A plain-text version of a structured reply, for conversation memory
  /// replayed back to the model next turn. Keeps the reply's own `type` as a
  /// prefix (e.g. "[writing_feedback]") rather than dropping it entirely —
  /// the model otherwise has no way to tell a past hint from a past
  /// explanation once it's been flattened to a bare string.
  String _replyToText(Map<String, dynamic> d) {
    final parts = [
      d['text'], d['word'], d['meaning'], d['when_to_use'], d['hint'],
      d['did_well'], d['to_improve'], d['next_step'], d['tip'],
      d['question'], d['check_question'], d['example'],
    ].where((v) => v != null && v.toString().trim().isNotEmpty).map((v) => v.toString());
    final joined = parts.join(' ');
    final type = d['type']?.toString();
    if (joined.isEmpty) return type ?? '';
    return type != null ? '[$type] $joined' : joined;
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: const BorderRadius.vertical(
                bottom: Radius.circular(30),
              ),
              boxShadow: [
                BoxShadow(
                  color: _navyText.withValues(alpha: 0.05),
                  blurRadius: 10,
                ),
              ],
            ),
            child: Row(
              children: [
                const CircleAvatar(
                  backgroundColor: _skyLight,
                  radius: 22,
                  child: Icon(Icons.smart_toy, color: _buttonBlue),
                ),
                const SizedBox(width: 14),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Lexi',
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        color: _navyText,
                        fontSize: 18,
                      ),
                    ),
                    Text(
                      'Helping you with $_weakness',
                      style: TextStyle(
                        fontSize: 12,
                        color: _navyText.withValues(alpha: 0.6),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(20),
              itemCount: _messages.length + (_isTyping ? 1 : 0),
              itemBuilder: (context, index) {
                if (_isTyping && index == _messages.length) {
                  return _buildTypingIndicator();
                }
                final msg = _messages[index];
                if (msg['role'] == 'lexi') {
                  return _buildLexiReply(
                      (msg['data'] as Map).cast<String, dynamic>());
                }
                return _buildMessage(
                    msg['role'] as String, msg['text'] as String? ?? '',
                    msg['image'] as String?);
              },
            ),
          ),
          _buildInputBar(),
        ],
      ),
    );
  }

  Widget _buildInputBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_pendingImage != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Stack(clipBehavior: Clip.none, children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.file(_pendingImage!,
                        width: 84, height: 84, fit: BoxFit.cover),
                  ),
                  Positioned(
                    right: -10,
                    top: -10,
                    child: GestureDetector(
                      onTap: () => setState(() => _pendingImage = null),
                      child: const CircleAvatar(
                          radius: 12,
                          backgroundColor: Colors.white,
                          child: Icon(Icons.close, size: 16, color: Colors.red)),
                    ),
                  ),
                ]),
              ),
            ),
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.add_photo_alternate_rounded,
                    color: _buttonBlue, size: 28),
                onPressed: _showImageSourceSheet,
              ),
              Expanded(
                child: TextField(
              controller: _messageController,
              decoration: InputDecoration(
                hintText: 'Message Lexi...',
                filled: true,
                fillColor: _bg,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(25),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 14,
                ),
              ),
              onSubmitted: (_) => _sendMessage(),
            ),
          ),
          const SizedBox(width: 10),
          GestureDetector(
            onTap: _sendMessage,
            child: Container(
              width: 50,
              height: 50,
              decoration: const BoxDecoration(
                color: _buttonBlue,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.send_rounded,
                color: Colors.white,
                size: 22,
              ),
            ),
          ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Structured, kid-friendly Lexi replies ───────────────────────────────
  Widget _buildLexiReply(Map<String, dynamic> d) {
    final type = d['type'] as String? ?? 'simple_answer';
    switch (type) {
      case 'word_meaning':
        return _lexiBubble(_wordMeaningCard(d));
      case 'guiding_hint':
        return _lexiBubble(_hintCard(d));
      case 'writing_feedback':
        return _lexiBubble(_feedbackCard(d));
      case 'grammar_explanation':
        return _lexiBubble(_grammarCard(d));
      case 'practice_question':
        return _lexiBubble(_practiceCard(d));
      case 'reading_help':
      case 'writing_ideas':
      case 'example_generation':
      case 'study_advice':
        return _lexiBubble(_genericCard(d));
      default:
        return _lexiBubble(Text(
          (d['text'] ?? '').toString(),
          style: const TextStyle(
              fontSize: 15,
              color: _navyText,
              fontWeight: FontWeight.w600,
              height: 1.4),
        ));
    }
  }

  // grammar_explanation: topic, text, example, check_question
  Widget _grammarCard(Map<String, dynamic> d) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if ((d['topic'] ?? '').toString().isNotEmpty)
            Text((d['topic'] ?? '').toString(),
                style: const TextStyle(
                    fontSize: 17, fontWeight: FontWeight.w900, color: _navyText)),
          if ((d['topic'] ?? '').toString().isNotEmpty)
            const SizedBox(height: 6),
          if ((d['text'] ?? '').toString().isNotEmpty)
            Text((d['text'] ?? '').toString(),
                style: const TextStyle(
                    fontSize: 15, color: _navyText, fontWeight: FontWeight.w600, height: 1.4)),
          if ((d['example'] ?? '').toString().isNotEmpty) ...[
            const SizedBox(height: 8),
            _kv('Example', (d['example'] ?? '').toString(), italic: true),
          ],
          if ((d['check_question'] ?? '').toString().isNotEmpty)
            _questionBox((d['check_question'] ?? '').toString()),
        ],
      );

  // practice_question: question + hint (never the answer)
  Widget _practiceCard(Map<String, dynamic> d) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('📝 Try this', style: TextStyle(
              fontSize: 13, fontWeight: FontWeight.w800, color: _buttonBlue)),
          const SizedBox(height: 4),
          Text((d['question'] ?? '').toString(),
              style: const TextStyle(
                  fontSize: 16, color: _navyText, fontWeight: FontWeight.w800, height: 1.35)),
          if ((d['hint'] ?? '').toString().isNotEmpty) ...[
            const SizedBox(height: 8),
            _kv('Hint', (d['hint'] ?? '').toString()),
          ],
        ],
      );

  // reading_help / writing_ideas / example_generation / study_advice
  Widget _genericCard(Map<String, dynamic> d) {
    final lists = <String>[];
    for (final key in ['ideas', 'examples', 'tips']) {
      final v = d[key];
      if (v is List) lists.addAll(v.map((e) => e.toString()));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if ((d['text'] ?? '').toString().isNotEmpty)
          Text((d['text'] ?? '').toString(),
              style: const TextStyle(
                  fontSize: 15, color: _navyText, fontWeight: FontWeight.w600, height: 1.4)),
        if (lists.isNotEmpty) ...[
          const SizedBox(height: 8),
          ...lists.map((item) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('• ', style: TextStyle(color: _buttonBlue, fontWeight: FontWeight.w900)),
                  Expanded(
                    child: Text(item,
                        style: const TextStyle(
                            fontSize: 15, color: _navyText, fontWeight: FontWeight.w600, height: 1.35)),
                  ),
                ]),
              )),
        ],
        if ((d['tip'] ?? '').toString().isNotEmpty) ...[
          const SizedBox(height: 8),
          _kv('Tip', (d['tip'] ?? '').toString()),
        ],
        if ((d['question'] ?? '').toString().isNotEmpty)
          _questionBox((d['question'] ?? '').toString()),
      ],
    );
  }

  Widget _questionBox(String q) => Container(
        margin: const EdgeInsets.only(top: 10),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: _bg, borderRadius: BorderRadius.circular(12)),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('❓ ', style: TextStyle(fontSize: 16)),
          Expanded(
            child: Text(q,
                style: const TextStyle(
                    fontSize: 15, color: _buttonBlue, fontWeight: FontWeight.w800, height: 1.35)),
          ),
        ]),
      );

  Widget _lexiBubble(Widget child) => Align(
        alignment: Alignment.centerLeft,
        child: Container(
          margin: const EdgeInsets.only(bottom: 16),
          padding: const EdgeInsets.all(16),
          constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.82),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(20),
              topRight: Radius.circular(20),
              bottomLeft: Radius.circular(5),
              bottomRight: Radius.circular(20),
            ),
            boxShadow: [
              BoxShadow(
                  color: _navyText.withValues(alpha: 0.04), blurRadius: 6),
            ],
          ),
          child: child,
        ),
      );

  Widget _kv(String label, String value, {bool italic = false}) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: _buttonBlue)),
            const SizedBox(height: 2),
            Text(value,
                style: TextStyle(
                    fontSize: 15,
                    color: _navyText,
                    fontWeight: FontWeight.w600,
                    height: 1.35,
                    fontStyle: italic ? FontStyle.italic : FontStyle.normal)),
          ],
        ),
      );

  Widget _wordMeaningCard(Map<String, dynamic> d) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic, children: [
            Flexible(
              child: Text((d['word'] ?? '').toString(),
                  style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      color: _navyText)),
            ),
            const SizedBox(width: 8),
            if ((d['pronunciation'] ?? '').toString().isNotEmpty)
              Text('/${d['pronunciation']}/',
                  style: TextStyle(
                      fontSize: 14,
                      color: _navyText.withValues(alpha: 0.55),
                      fontStyle: FontStyle.italic)),
          ]),
          const Divider(height: 18),
          _kv('Meaning', (d['meaning'] ?? '').toString()),
          _kv('When to use', (d['when_to_use'] ?? '').toString()),
          _kv('Example', (d['example'] ?? '').toString(), italic: true),
        ],
      );

  Widget _hintCard(Map<String, dynamic> d) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if ((d['detected_task'] ?? '').toString().isNotEmpty) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                  color: _mintGreen.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20)),
              child: Text('📷 ${d['detected_task'].toString().replaceAll('_', ' ')}',
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w800, color: _mintGreen)),
            ),
            const SizedBox(height: 10),
          ],
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('💡 ', style: TextStyle(fontSize: 18)),
            Expanded(
              child: Text((d['hint'] ?? '').toString(),
                  style: const TextStyle(
                      fontSize: 15, color: _navyText, fontWeight: FontWeight.w600, height: 1.35)),
            ),
          ]),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
                color: _bg, borderRadius: BorderRadius.circular(12)),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('❓ ', style: TextStyle(fontSize: 16)),
              Expanded(
                child: Text((d['question'] ?? '').toString(),
                    style: const TextStyle(
                        fontSize: 15,
                        color: _buttonBlue,
                        fontWeight: FontWeight.w800,
                        height: 1.35)),
              ),
            ]),
          ),
        ],
      );

  Widget _feedbackRow(String emoji, String label, String value, Color color) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('$emoji $label',
                style: TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w800, color: color)),
            const SizedBox(height: 2),
            Text(value,
                style: const TextStyle(
                    fontSize: 15,
                    color: _navyText,
                    fontWeight: FontWeight.w600,
                    height: 1.35)),
          ],
        ),
      );

  Widget _feedbackCard(Map<String, dynamic> d) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _feedbackRow('✅', 'You did well', (d['did_well'] ?? '').toString(),
              _mintGreen),
          _feedbackRow('✏️', 'Make it better',
              (d['to_improve'] ?? '').toString(), _buttonBlue),
          _feedbackRow('➡️', 'Next step', (d['next_step'] ?? '').toString(),
              const Color(0xFFF9A825)),
        ],
      );

  Widget _buildMessage(String role, String text, [String? imageB64]) {
    final isLexi = role == 'lexi';
    return Align(
      alignment: isLexi ? Alignment.centerLeft : Alignment.centerRight,
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        decoration: BoxDecoration(
          color: isLexi ? Colors.white : _mintGreen,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(20),
            topRight: const Radius.circular(20),
            bottomLeft: Radius.circular(isLexi ? 5 : 20),
            bottomRight: Radius.circular(isLexi ? 20 : 5),
          ),
          boxShadow: [
            BoxShadow(color: _navyText.withValues(alpha: 0.03), blurRadius: 5),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (imageB64 != null) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.memory(base64Decode(imageB64),
                    width: 180, fit: BoxFit.cover),
              ),
              if (text.isNotEmpty) const SizedBox(height: 8),
            ],
            if (text.isNotEmpty)
              Text(
                text,
                style: TextStyle(
                  fontSize: 15,
                  color: isLexi ? _navyText : Colors.white,
                  fontWeight: FontWeight.w600,
                  height: 1.4,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildTypingIndicator() {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.all(12),
        child: const Text(
          'Lexi is hooting...',
          style: TextStyle(fontStyle: FontStyle.italic, color: Colors.grey),
        ),
      ),
    );
  }
}