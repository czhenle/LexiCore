import 'package:flutter/material.dart';
import '../home/home_screen.dart';

class ResultScreen extends StatelessWidget {
  final String moduleName;
  final Color moduleColor;
  final IconData moduleIcon;
  final int unitNumber;
  final String topic;
  final int score;
  final int totalQuestions;
  final int correctAnswers;

  const ResultScreen({
    super.key,
    required this.moduleName,
    required this.moduleColor,
    required this.moduleIcon,
    required this.unitNumber,
    required this.topic,
    required this.score,
    required this.totalQuestions,
    required this.correctAnswers,
  });

  String get _feedback {
    if (score >= 80) return 'Excellent work! You\'ve mastered this unit!';
    if (score >= 60) return 'Good job! Keep practising to improve further.';
    if (score >= 40) return 'Not bad! Review the topic and try again.';
    return 'Keep going! Practise makes perfect.';
  }

  String get _nextStepMessage {
    if (score >= 60) {
      return 'You\'ve unlocked the next unit! Keep up the great work.';
    }
    return 'Try this unit again to unlock the next one.';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 20),

              // Module icon
              Center(
                child: Container(
                  width: 90,
                  height: 90,
                  decoration: BoxDecoration(
                    color: moduleColor.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(moduleIcon, size: 48, color: moduleColor),
                ),
              ),
              const SizedBox(height: 20),

              // Module + unit label
              Text(
                '$moduleName — Unit $unitNumber',
                style: TextStyle(
                  fontSize: 14,
                  color: moduleColor,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 4),
              Text(
                topic,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: Colors.black87,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),

              // Score circle
              Center(
                child: Container(
                  width: 140,
                  height: 140,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: moduleColor.withValues(alpha: 0.1),
                    border: Border.all(
                        color: moduleColor.withValues(alpha: 0.4), width: 4),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        '$score%',
                        style: TextStyle(
                          fontSize: 36,
                          fontWeight: FontWeight.w900,
                          color: moduleColor,
                        ),
                      ),
                      Text(
                        '$correctAnswers / $totalQuestions correct',
                        style: TextStyle(
                            fontSize: 12, color: Colors.grey[600]),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 28),

              // Feedback message
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: moduleColor.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  children: [
                    Text(
                      _feedback,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: moduleColor,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _nextStepMessage,
                      style: TextStyle(
                          fontSize: 13, color: Colors.grey[600]),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),

              // Progress bar
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Unit $unitNumber progress',
                          style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey[600],
                              fontWeight: FontWeight.w500)),
                      Text('$score%',
                          style: TextStyle(
                              fontSize: 13,
                              color: moduleColor,
                              fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: score / 100,
                      backgroundColor: Colors.grey[200],
                      valueColor: AlwaysStoppedAnimation(moduleColor),
                      minHeight: 10,
                    ),
                  ),
                ],
              ),

              const Spacer(),

              // Back to home button
              ElevatedButton(
                onPressed: () => Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (_) => const HomeScreen()),
                  (route) => false,
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: moduleColor,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                child: const Text(
                  'Back to home',
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.white),
                ),
              ),
              const SizedBox(height: 12),

              // Try again button
              OutlinedButton(
                onPressed: () => Navigator.pop(context),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  side: BorderSide(color: moduleColor),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                child: Text(
                  'Try this unit again',
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: moduleColor),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}