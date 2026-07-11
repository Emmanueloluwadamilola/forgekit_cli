import 'package:flutter/material.dart';

import 'colors/colors.dart';
import 'text_theme.dart';

/// Assembles light/dark [ThemeData] from the app palette and typography.
///
/// Mix into a widget or call statically: `AppTheme.lightTheme()`.
mixin AppTheme {
  static ThemeData lightTheme() {
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      brightness: Brightness.light,
      error: AppColors.error,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: AppColors.lightBackground,
      textTheme: MyTextTheme.light,
    );
  }

  static ThemeData darkTheme() {
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      brightness: Brightness.dark,
      error: AppColors.error,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: AppColors.darkBackground,
      textTheme: MyTextTheme.dark,
    );
  }
}
