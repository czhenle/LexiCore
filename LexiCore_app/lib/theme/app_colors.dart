import 'package:flutter/material.dart';

/// LexiCore's shared color palette — the single source of truth for colors
/// that recur across screens. Every value here was copy-pasted, byte-for-
/// byte identical, into 2-17 separate files before this consolidation; a
/// future palette change (a rebrand, a contrast fix) is now a one-file edit
/// instead of hunting down every screen that hardcoded the same hex.
///
/// Screens keep their own short, private aliases for brevity at each call
/// site (e.g. `static const Color _navyText = AppColors.navy;`) — only the
/// VALUE moved here, so no call site anywhere had to change.
class AppColors {
  AppColors._();

  // ── Core brand ────────────────────────────────────────────────────────
  static const Color navy = Color(0xFF003C8F);
  static const Color blue = Color(0xFF1E88E5);

  // ── Backgrounds ───────────────────────────────────────────────────────
  static const Color skyBg = Color(0xFFF0F8FF); // page-level background
  static const Color skyLight = Color(0xFFDFF1FF); // card/section tint
  static const Color skyDark = Color(0xFF7AC9FA); // gradient accent
  static const Color moduleBg = Color(0xFFF5F5F7); // module screens' content background

  // ── Skill / status accents ───────────────────────────────────────────
  static const Color mintGreen = Color(0xFF4DB6AC); // Grammar, success
  static const Color brightOrange = Color(0xFFFF9800); // Vocabulary
  static const Color coralRed = Color(0xFFE57373); // Writing
  static const Color coralRedBright = Color(0xFFFF5252); // Profile's brighter danger red
  static const Color lightBlue = Color(0xFF64B5F6); // Reading (Home's lighter variant)
  static const Color purple = Color(0xFF6A1B9A); // Weekly Assessment
  static const Color starYellow = Color(0xFFFFD54F);
  static const Color errorRed = Color(0xFFEF4444);

  // ── Text / neutrals ───────────────────────────────────────────────────
  static const Color textDark = Color(0xFF1A1A2E);
  static const Color textMid = Color(0xFF6B7280);
  static const Color divider = Color(0xFFE5E7EB);
  static const Color darkGrey = Color(0xFF424242);
}
