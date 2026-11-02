import 'package:flutter/material.dart';

/// Light and dark surfaces for screens that paint their own colors.
extension AppTone on BuildContext {
  bool get isDark => Theme.of(this).brightness == Brightness.dark;

  Color get cPage => isDark ? const Color(0xFF0E1512) : const Color(0xFFF3F6F4);

  Color get cCard => isDark ? const Color(0xFF17211C) : Colors.white;

  Color get cText => isDark ? const Color(0xFFF4F7F5) : const Color(0xFF0F172A);

  Color get cMuted => isDark ? const Color(0xFFA8B5AE) : const Color(0xFF64748B);

  Color get cLine => isDark ? const Color(0xFF2C3B34) : const Color(0xFFE2E8F0);

  Color get cField => isDark ? const Color(0xFF1C2822) : const Color(0xFFF8FAF9);

  Color get cMint => isDark ? const Color(0xFF143024) : const Color(0xFFE8F8EF);

  Color get cTrack => isDark ? const Color(0xFF3A4A42) : const Color(0xFFE5E7EB);
}
