import 'package:flutter/material.dart';

/// {{name.titleCase()}} — a shared design-system widget.
///
/// Example:
/// ```dart
/// {{name.pascalCase()}}(
///   label: 'Tap me',
///   onTap: () => print('tapped'),
/// )
/// ```
class {{name.pascalCase()}} extends StatelessWidget {
  const {{name.pascalCase()}}({
    super.key,
    required this.label,
    this.onTap,
  });

  /// Text rendered inside the widget.
  final String label;

  /// Invoked when the widget is tapped.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelLarge,
        ),
      ),
    );
  }
}
