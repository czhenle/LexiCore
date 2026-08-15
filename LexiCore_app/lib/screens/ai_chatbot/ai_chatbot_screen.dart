import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../services/supabase_service.dart';
import '../../services/api_service.dart';

class AiChatbotScreen extends StatefulWidget {
  const AiChatbotScreen({super.key});

  @override
  State<AiChatbotScreen> createState() => _AiChatbotScreenState();
}

class _AiChatbotScreenState extends State<AiChatbotScreen> {
  static const Color _bg = Color(0xFFF0F8FF);
  static const Color _navyText = Color(0xFF003C8F);
  static const Color _skyLight = Color(0xFFDFF1FF);
  static const Color _mintGreen = Color(0xFF4DB6AC);
  static const Color _buttonBlue = Color(0xFF1E88E5);

  final _supabaseService = SupabaseService();
  final _apiService = ApiService();
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();

  final List<Map<String, String>> _messages = [];
  final _picker = ImagePicker();
  File? _pendingImage;
  bool _isTyping = false;
  String _weakness = 'Grammar';
  String _username = 'there';

  @override
  void initState() {
    super.initState();
    _loadStudentContext();
  }

  Future<void> _loadStudentContext() async {
    try {
      final profile = await _supabaseService.getStudentProfile();
      final assessment = await _supabaseService.getAssessmentResults();

      // Check if the widget is still active before updating local variables
      if (!mounted) return;

      if (profile != null && assessment != null) {
        setState(() {
          _username = profile['username'] ?? 'friend';
          _weakness = 'Vocabulary'; // Simplified for demo
        });
      }
    } catch (e) {
      debugPrint(e.toString());
    }

    // Final check before adding the initial welcome message
    if (mounted) {
      setState(() {
        _messages.add({
          'role': 'lexi',
          'text':
              'Hi $_username! I\'m Lexi 🦉 I heard you want to practice your $_weakness. What shall we talk about?',
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

    final reply = await _apiService.chatWithLexi(
      text.isEmpty ? 'Please help me with this.' : text,
      3,
      imageBase64: imageB64,
    );

    setState(() {
      _isTyping = false;
      _messages.add({
        'role': 'lexi',
        'text': reply ?? 'Oops! My wings got tangled. Try again!',
      });
    });
    _scrollToBottom();
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
                return _buildMessage(
                    msg['role']!, msg['text'] ?? '', msg['image']);
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