import 'dart:async';

import 'package:flutter/material.dart';

/// A reusable fade+slide entrance animation widget that staggers child widgets.
///
/// Each child fades in and slides up sequentially based on its index.
/// Index 0 appears immediately, index 1 after staggerDelay, index 2 after staggerDelay*2, etc.
class StaggeredEntry extends StatefulWidget {
  /// The position in the staggered sequence (0-indexed).
  final int index;

  /// The widget to animate in.
  final Widget child;

  /// Total duration of the entrance animation.
  final Duration duration;

  /// Delay between each item's animation start (multiplied by index).
  final Duration staggerDelay;

  const StaggeredEntry({
    super.key,
    required this.index,
    required this.child,
    this.duration = const Duration(milliseconds: 300),
    this.staggerDelay = const Duration(milliseconds: 50),
  });

  @override
  State<StaggeredEntry> createState() => _StaggeredEntryState();
}

class _StaggeredEntryState extends State<StaggeredEntry>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  Timer? _timer;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(duration: widget.duration, vsync: this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_controller.isAnimating || _controller.value > 0 || _timer != null) return;
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      _controller.value = 1;
      return;
    }
    // Schedule the animation start with a staggered delay
    final delay = widget.staggerDelay * widget.index;
    _timer = Timer(delay, () {
      if (mounted) {
        _controller.forward();
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final fadeAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOut,
    );

    final slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.05),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeOut,
      ),
    );

    return FadeTransition(
      opacity: fadeAnimation,
      child: SlideTransition(
        position: slideAnimation,
        child: widget.child,
      ),
    );
  }
}
