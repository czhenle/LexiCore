import 'package:flutter/material.dart';

/// Soft, non-blocking "this is a bit ahead of you" confirmation. Content is
/// never hard-locked by standard — this only asks the student to confirm they
/// still want to try something above their recommended starting standard.
/// Returns true if the student wants to proceed, false if they back out.
Future<bool> showChallengeAlert(
  BuildContext context, {
  required String topicName,
  required int recommendedStandard,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Text('A bit more advanced! 🌟',
          style: TextStyle(fontWeight: FontWeight.w800)),
      content: Text(
        '"$topicName" is usually learned from Standard $recommendedStandard '
        'onward, so it might feel a bit challenging — but you can absolutely '
        'give it a try!',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Maybe later'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Let\'s try!'),
        ),
      ],
    ),
  );
  return result ?? false;
}
