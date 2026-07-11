import 'package:flutter/material.dart';

/// Ergonomic named-route navigation on [BuildContext].
extension NavigationX on BuildContext {
  /// Push a named route, optionally passing [arguments].
  Future<T?> pushNamed<T>(String id, {Object? arguments}) {
    return Navigator.of(this).pushNamed<T>(id, arguments: arguments);
  }

  /// Push a named route and remove all previous routes from the stack.
  Future<T?> pushAndClear<T>(String id, {Object? arguments}) {
    return Navigator.of(this).pushNamedAndRemoveUntil<T>(
      id,
      (route) => false,
      arguments: arguments,
    );
  }

  /// Replace the current route with a named route.
  Future<T?> pushReplacement<T, TO>(String id, {Object? arguments}) {
    return Navigator.of(this).pushReplacementNamed<T, TO>(
      id,
      arguments: arguments,
    );
  }

  /// Pop the current route, optionally returning [result].
  void pop<T>([T? result]) => Navigator.of(this).pop<T>(result);
}
