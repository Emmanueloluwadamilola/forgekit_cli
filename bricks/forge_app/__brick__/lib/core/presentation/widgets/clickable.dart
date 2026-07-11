import 'package:flutter/material.dart';

/// A lightweight tap wrapper that gives any [child] a ripple-free,
/// opacity-friendly tap target without the boilerplate of [GestureDetector]
/// + [InkWell] plumbing.
class Clickable extends StatelessWidget {
  const Clickable({
    super.key,
    required this.child,
    this.onTap,
    this.borderRadius,
  });

  final Widget child;
  final VoidCallback? onTap;
  final BorderRadius? borderRadius;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: borderRadius ?? BorderRadius.circular(8),
        child: child,
      ),
    );
  }
}
