import 'package:flutter/material.dart';
import 'module_quiz_screen.dart';

class StandardSelectionScreen extends StatelessWidget {
  final String moduleName;
  final IconData moduleIcon;
  final Color moduleColor;

  const StandardSelectionScreen({
    super.key,
    required this.moduleName,
    required this.moduleIcon,
    required this.moduleColor,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          moduleName,
          style: TextStyle(
            fontWeight: FontWeight.w900,
            color: moduleColor,
            fontSize: 22,
          ),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Module icon
              Center(
                child: Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    color: moduleColor.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(moduleIcon, size: 52, color: moduleColor),
                ),
              ),
              const SizedBox(height: 24),

              Text(
                'Ready to practise $moduleName?',
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  color: Colors.black87,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                'Your questions will be tailored to your current level '
                'and continue from where you left off.',
                style: TextStyle(
                    fontSize: 14, color: Colors.grey[600], height: 1.5),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 40),

              // Info card
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: moduleColor.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                      color: moduleColor.withValues(alpha: 0.2)),
                ),
                child: Column(
                  children: [
                    _buildInfoRow(
                        Icons.auto_awesome,
                        'AI-generated questions',
                        'Fresh questions every session',
                        moduleColor),
                    const SizedBox(height: 12),
                    _buildInfoRow(
                        Icons.trending_up,
                        'Curriculum progression',
                        'Unlocks new topics as you improve',
                        moduleColor),
                    const SizedBox(height: 12),
                    _buildInfoRow(
                        Icons.lightbulb_outline,
                        'Instant feedback',
                        'Explanations after every answer',
                        moduleColor),
                  ],
                ),
              ),

              const Spacer(),

              ElevatedButton(
                onPressed: () => Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ModuleQuizScreen(
                      moduleName: moduleName,
                      moduleIcon: moduleIcon,
                      moduleColor: moduleColor,
                    ),
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: moduleColor,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                child: const Text(
                  'Start practising',
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.white),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoRow(
      IconData icon, String title, String subtitle, Color color) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: color, size: 18),
        ),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.bold)),
            Text(subtitle,
                style:
                    TextStyle(fontSize: 12, color: Colors.grey[600])),
          ],
        ),
      ],
    );
  }
}