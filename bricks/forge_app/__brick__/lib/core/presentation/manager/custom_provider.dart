import 'package:flutter/material.dart';

/// Base [ChangeNotifier] for all feature providers.
///
/// Guards against calling [notifyListeners] after the provider has been
/// disposed (a common source of "setState() called after dispose" errors).
class CustomProvider extends ChangeNotifier {
  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }
}
