import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// A hint chat with Lexi, grounded in the current practice item (PS3).
/// Open via `showModalBottomSheet(isScrollControlled: true, ...)`.
class TutorSheet extends StatefulWidget {
  final Map<String, dynamic> item;
  final int standard;
  const TutorSheet({super.key, required this.item, required this.standard});

  @override
  State<TutorSheet> createState() => _TutorSheetState();
}

class _TutorSheetState extends State<TutorSheet> {
  static const _blue = Color(0xFF1E88E5);
  static const _navy = Color(0xFF003C8F);

  final _ctrl = TextEditingController();
  final _scroll = ScrollController();
  final List<Map<String, String>> _messages = []; // {role, content}
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _send("I'm stuck. Can you give me a hint?", initial: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _send(String text, {bool initial = false}) async {
    final msg = text.trim();
    if (msg.isEmpty || _loading) return;
    setState(() {
      _messages.add({'role': 'user', 'content': msg});
      _loading = true;
      if (!initial) _ctrl.clear();
    });
    _scrollDown();
    try {
      final res =
          await Supabase.instance.client.functions.invoke('tutor', body: {
        'question': widget.item['question'],
        'options': widget.item['options'],
        'correct_answer': widget.item['correct_answer'],
        'answer': widget.item['answer'],
        'sub_skill_name': widget.item['sub_skill_name'],
        'rung': widget.item['rung'],
        'standard': widget.standard,
        'messages': _messages,
      });
      final data = res.data;
      final reply = (data is Map && data['reply'] != null)
          ? data['reply'].toString()
          : "Let's read the question again slowly. What word do you know?";
      if (mounted) {
        setState(() => _messages.add({'role': 'assistant', 'content': reply}));
      }
    } catch (e) {
      // Keep the child-facing message gentle, but never swallow the cause —
      // a silent catch here hid the fact that `tutor` was running a stale
      // deploy. Unlike the practice loop this fallback records nothing, so a
      // friendly reply is safe; it just must stay diagnosable.
      debugPrint('tutor invoke failed: $e');
      if (mounted) {
        setState(() => _messages.add({
              'role': 'assistant',
              'content':
                  "Hmm, I couldn't think just now. Try reading the question one more time!"
            }));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
      _scrollDown();
    }
  }

  void _scrollDown() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        builder: (context, _) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              _header(),
              Expanded(child: _messageList()),
              _inputBar(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header() => Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: Color(0x11000000))),
        ),
        child: Row(children: [
          const CircleAvatar(
              backgroundColor: _blue,
              radius: 16,
              child: Text('L', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800))),
          const SizedBox(width: 10),
          const Text('Lexi — your hint helper',
              style: TextStyle(fontWeight: FontWeight.w800, color: _navy)),
          const Spacer(),
          IconButton(
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.close)),
        ]),
      );

  Widget _messageList() => ListView.builder(
        controller: _scroll,
        padding: const EdgeInsets.all(12),
        itemCount: _messages.length + (_loading ? 1 : 0),
        itemBuilder: (context, i) {
          if (i >= _messages.length) return _typing();
          final m = _messages[i];
          final isUser = m['role'] == 'user';
          return Align(
            alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
            child: Container(
              margin: const EdgeInsets.symmetric(vertical: 4),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              constraints: BoxConstraints(
                  maxWidth: MediaQuery.of(context).size.width * 0.72),
              decoration: BoxDecoration(
                color: isUser ? _blue : const Color(0xFFEEF4FB),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(m['content'] ?? '',
                  style: TextStyle(
                      color: isUser ? Colors.white : Colors.black87,
                      fontSize: 15)),
            ),
          );
        },
      );

  Widget _typing() => Align(
        alignment: Alignment.centerLeft,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFFEEF4FB),
            borderRadius: BorderRadius.circular(14),
          ),
          child: const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2)),
        ),
      );

  Widget _inputBar() => Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        child: Row(children: [
          Expanded(
            child: TextField(
              controller: _ctrl,
              onSubmitted: _send,
              decoration: InputDecoration(
                hintText: 'Ask Lexi…',
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none),
                filled: true,
                fillColor: const Color(0xFFF0F4F8),
              ),
            ),
          ),
          const SizedBox(width: 8),
          CircleAvatar(
            backgroundColor: _blue,
            child: IconButton(
              icon: const Icon(Icons.send, color: Colors.white, size: 20),
              onPressed: _loading ? null : () => _send(_ctrl.text),
            ),
          ),
        ]),
      );
}