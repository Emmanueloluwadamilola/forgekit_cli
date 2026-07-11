import 'package:flutter/material.dart';
{{^useRouter}}import 'package:go_router/go_router.dart';
{{/useRouter}}

{{#useRouter}}
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
{{/useRouter}}
{{^useRouter}}
/// Ergonomic go_router navigation on [BuildContext].
extension NavigationX on BuildContext {
  /// Navigate to a location.
  void goTo(String location, {Object? extra}) => go(location, extra: extra);

  /// Push a location onto the navigation stack.
  Future<T?> pushTo<T>(String location, {Object? extra}) {
    return push<T>(location, extra: extra);
  }

  /// Replace the current location.
  void replaceWith(String location, {Object? extra}) {
    replace(location, extra: extra);
  }

  /// Pop the current route, optionally returning [result].
  void popRoute<T>([T? result]) => pop<T>(result);
}
{{/useRouter}}
