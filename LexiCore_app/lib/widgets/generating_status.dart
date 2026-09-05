import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

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

/// [GeneratingStatus] wrapped in an actual dialog surface.
///
/// Every other screen shows the status against its own page background, so a
/// bare [GeneratingStatus] looks right there. Inside `showDialog` there is no
/// such background — a bare one floats the spinner and text straight onto the
/// dimmed barrier, which reads as unstyled text pasted over the screen rather
/// than a deliberate "working on it" state. This gives it a card to sit on.
class GeneratingDialog extends StatelessWidget {
  final String estimate;
  final String label;

  /// Accent for the spinner and heading. Defaults to the app's blue; pass the
  /// module's own colour so the wait looks like part of that module.
  final Color color;

  const GeneratingDialog({
    super.key,
    this.estimate = 'about 10-20 seconds',
    this.label = 'Preparing your questions…',
    this.color = AppColors.blue,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white,
      elevation: 8,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 48),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
        child: GeneratingStatus(
          label: label,
          estimate: estimate,
          // Dark-on-white here, unlike the white-on-colour used full-screen.
          color: color,
        ),
      ),
    );
  }
}
