import 'package:flutter/material.dart';

/// mobileLM brand palette — docs/brand/palette.md
class AppColors {
  AppColors._();

  // Brand accents
  static const Color primary = Color(0xFFB9F53E); // Volt 500
  static const Color primaryDim = Color(0xFF8FD42A); // Volt 600
  static const Color secondary = Color(0xFF8B7CFF); // Pulse 500

  // Semantic
  static const Color success = Color(0xFF34C759);
  static const Color warning = Color(0xFFFF9500);
  static const Color error = Color(0xFFFF3B30);
  static const Color info = Color(0xFF5AC8FA);

  // Text
  static const Color textPrimary = Color(0xFFFFFFFF);
  static const Color textSecondary = Color(0xFF94A3B8);
  static const Color textMuted = Color(0xFF64748B);

  // Surfaces (Ink scale)
  static const Color bg = Color(0xFF0B1018);
  static const Color surface = Color(0xFF131B27);
  static const Color surfaceLight = Color(0xFF1D2838);
  static const Color card = Color(0xFF131B27);

  // Chat bubbles
  static const Color userBubble = Color(0xFFB9F53E);
  static const Color aiBubble = Color(0xFF1D2838);
  static const Color cmdBubble = Color(0xFF1A2E1A);

  // Borders
  static const Color border = Color(0xFF26303F);
  static const Color borderLight = Color(0xFF334052);

  // Dark ink used on top of Volt fills (buttons, bubbles)
  static const Color onVolt = Color(0xFF0B1018);
}
