import 'package:flutter/material.dart';
import 'vocabulary_module_screen.dart';
import 'grammar_module_screen.dart';
import 'reading_module_screen.dart';
import 'writing_module_screen.dart';

class ModuleSelectionScreen extends StatelessWidget {
  const ModuleSelectionScreen({super.key});

  // ✨ Sky Blue Theme Colors
  static const Color _bg       = Color(0xFFF0F8FF);
  static const Color _navyText = Color(0xFF003C8F);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        automaticallyImplyLeading: false,
        title: const Text('Modules',
            style: TextStyle(
                fontWeight: FontWeight.w900,
                color: _navyText, // Updated to Navy Blue
                fontSize: 26)),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 100),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Choose what to practise today',
                  style: TextStyle(
                      fontSize: 16, 
                      color: _navyText.withValues(alpha: 0.6), // Updated to soft Navy
                      fontWeight: FontWeight.w700)),
              const SizedBox(height: 24),

              _buildModuleCard(
                context,
                title:       'Vocabulary',
                description: 'Guess images, match meanings, and learn new words',
                icon:        Icons.abc_rounded,
                color:       const Color(0xFFFF9800),
                tags:        ['Guess image', 'Word meaning', 'In context'],
                destination: const VocabularyModuleScreen(),
              ),
              _buildModuleCard(
                context,
                title:       'Grammar',
                description: 'Pick your grammar topics and practise targeted exercises',
                icon:        Icons.rule_rounded,
                color:       const Color(0xFF4DB6AC),
                tags:        ['Nouns', 'Tenses', 'Articles', '+ more'],
                destination: const GrammarModuleScreen(),
              ),
              _buildModuleCard(
                context,
                title:       'Reading',
                description: 'Read an AI-generated article and answer comprehension questions',
                icon:        Icons.menu_book_rounded,
                color:       const Color(0xFF1E88E5),
                tags:        ['Long articles', 'MCQ', 'Save & submit'],
                destination: const ReadingModuleScreen(),
              ),
              _buildModuleCard(
                context,
                title:       'Writing',
                description: 'Guided writing exercises to sharpen your composition skills',
                icon:        Icons.edit_rounded,
                color:       const Color(0xFFE57373),
                tags:        ['Sentence completion', 'Error correction', 'Ordering'],
                destination: const WritingModuleScreen(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildModuleCard(
    BuildContext context, {
    required String       title,
    required String       description,
    required IconData     icon,
    required Color        color,
    required List<String> tags,
    required Widget       destination,
  }) {
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => destination),
      ),
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 12,
                offset: const Offset(0, 4)),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 64, height: 64,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Icon(icon, size: 32, color: color),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          color: color)),
                  const SizedBox(height: 4),
                  Text(description,
                      style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF6B7280),
                          height: 1.4)),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 6, runSpacing: 6,
                    children: tags.map((tag) => Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(tag,
                          style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: color)),
                    )).toList(),
                  ),
                ],
              ),
            ),
            Icon(Icons.arrow_forward_ios_rounded,
                size: 16, color: Colors.grey[400]),
          ],
        ),
      ),
    );
  }
}