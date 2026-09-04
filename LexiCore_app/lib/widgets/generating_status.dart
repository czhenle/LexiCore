import 'package:flutter/material.dart';

/// A small "please wait" status for any screen waiting on question/passage
/// generation. Deliberately just a spinner + a static reassurance line —
/// earlier versions ticked up an elapsed-seconds counter, but a live number
/// in front of a child (or a parent/examiner watching) reads as something
/// going wrong the moment it passes the quoted estimate, even when
/// generation is proceeding completely normally. A calm "this usually takes
/// about X — that's plenty of time" says the same thing without inviting
/// anyone to start a stopwatch.
class GeneratingStatus extends StatelessWidget {
  /// e.g. "about 15-30 seconds".
  final String estimate;
  final String label;
  final Color color;
  const GeneratingStatus({
    super.key,
    this.estimate = 'about 10-20 seconds',
    this.label = 'Preparing your questions…',
    this.color = Colors.white,
  });

  @override
  Widget build(BuildContext context) {
    // Some call sites show this inside a bare showDialog builder with no
    // Dialog/Material ancestor of its own — without one, Text falls back to
    // Flutter's "missing Material ancestor" debug style (huge, underlined,
    // unstyled). MaterialType.transparency gives every Text below a proper
    // ancestor without painting anything or changing layout.
    return Material(
      type: MaterialType.transparency,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(color: color),
          const SizedBox(height: 16),
          Text(label,
              textAlign: TextAlign.center,
              style: TextStyle(color: color, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text('Takes $estimate — plenty of time!',
              textAlign: TextAlign.center,
              style: TextStyle(color: color.withValues(alpha: 0.75), fontSize: 12)),
        ],
      ),
    );
  }
}
