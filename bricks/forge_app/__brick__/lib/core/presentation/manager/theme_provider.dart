import 'package:flutter/material.dart';
import 'package:injectable/injectable.dart';

/// Holds and toggles the active [ThemeMode] for the app.
@lazySingleton
class ThemeProvider extends ChangeNotifier {
  ThemeMode _themeMode = ThemeMode.system;

  ThemeMode get themeMode => _themeMode;

  bool get isDark => _themeMode == ThemeMode.dark;

  void setThemeMode(ThemeMode mode) {
    if (_themeMode == mode) return;
    _themeMode = mode;
    notifyListeners();
  }

  void toggle() {
    setThemeMode(isDark ? ThemeMode.light : ThemeMode.dark);
  }
}
