import 'package:flutter/material.dart';

import 'colors/colors.dart';

/// Typography for the app, split into a light and dark [TextTheme].
class MyTextTheme {
  MyTextTheme._();

  static TextTheme light = _build(AppColors.lightText);
  static TextTheme dark = _build(AppColors.darkText);

  static TextTheme _build(Color color) {
    return TextTheme(
      displayLarge: TextStyle(
        fontSize: 32,
        fontWeight: FontWeight.bold,
        color: color,
      ),
      titleLarge: TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w600,
        color: color,
      ),
      bodyLarge: TextStyle(fontSize: 16, color: color),
      bodyMedium: TextStyle(fontSize: 14, color: color),
      labelLarge: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: color,
      ),
    );
  }
}
