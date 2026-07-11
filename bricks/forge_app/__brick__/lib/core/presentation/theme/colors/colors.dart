import 'package:flutter/material.dart';

/// Central color palette. Reference these constants everywhere instead of
/// hard-coding `Color(0x...)` values.
class AppColors {
  AppColors._();

  static const Color primary = Color(0xFF2962FF);
  static const Color secondary = Color(0xFF00BFA5);
  static const Color error = Color(0xFFD32F2F);

  static const Color lightBackground = Color(0xFFFFFFFF);
  static const Color lightSurface = Color(0xFFF5F5F5);
  static const Color lightText = Color(0xFF1A1A1A);

  static const Color darkBackground = Color(0xFF121212);
  static const Color darkSurface = Color(0xFF1E1E1E);
  static const Color darkText = Color(0xFFEDEDED);
}
