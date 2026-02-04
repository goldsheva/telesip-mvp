import 'package:flutter/material.dart';

/// A button that shows a spinner instead of its child while [isLoading] is true.
class LoadingButton extends StatelessWidget {
  const LoadingButton({
    super.key,
    required this.onPressed,
    required this.child,
    this.isLoading = false,
    this.style,
  });

  final VoidCallback? onPressed;
  final Widget child;
  final bool isLoading;
  final ButtonStyle? style;

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: isLoading ? null : onPressed,
      style: style,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 150),
        transitionBuilder: (widget, animation) =>
            FadeTransition(opacity: animation, child: widget),
        child: isLoading
            ? const SizedBox(
                key: ValueKey('loading_spinner'),
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : KeyedSubtree(key: const ValueKey('label'), child: child),
      ),
    );
  }
}
