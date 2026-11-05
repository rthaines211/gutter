import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import '../config/app_theme.dart';
import 'progress_ring.dart';

class FloatingPagePill extends StatefulWidget {
  final int currentPage;
  final int totalPages;
  final Color accent;

  const FloatingPagePill({
    super.key,
    required this.currentPage,
    required this.totalPages,
    this.accent = AppTheme.accent,
  });

  @override
  State<FloatingPagePill> createState() => _FloatingPagePillState();
}

class _FloatingPagePillState extends State<FloatingPagePill>
    with SingleTickerProviderStateMixin {
  static const Duration _fadeInDuration = Duration(milliseconds: 150);
  static const Duration _fadeOutDuration = Duration(milliseconds: 250);
  static const Duration _holdDuration = Duration(milliseconds: 1500);

  late final AnimationController _controller;
  Timer? _fadeTimer;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: _fadeOutDuration,
      value: 1.0,
    );
    _scheduleFadeOut();
  }

  @override
  void didUpdateWidget(FloatingPagePill oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.currentPage != oldWidget.currentPage) {
      _controller.duration = _fadeInDuration;
      _controller.forward(from: _controller.value);
      _scheduleFadeOut();
    }
  }

  void _scheduleFadeOut() {
    _fadeTimer?.cancel();
    _fadeTimer = Timer(_holdDuration, () {
      if (!mounted) return;
      _controller.duration = _fadeOutDuration;
      _controller.reverse();
    });
  }

  @override
  void dispose() {
    _fadeTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final progress = widget.totalPages > 0
        ? ((widget.currentPage + 1) / widget.totalPages).clamp(0.0, 1.0)
        : 0.0;

    return Positioned(
      bottom: 22,
      left: 0,
      right: 0,
      child: Center(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            return IgnorePointer(
              // Treat as invisible below 5% opacity so taps pass through.
              ignoring: _controller.value < 0.05,
              child: Opacity(opacity: _controller.value, child: child),
            );
          },
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppTheme.pill),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(AppTheme.pill),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.1), width: 0.5),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ProgressRing(value: progress, size: 12, strokeWidth: 1.5, color: widget.accent),
                    const SizedBox(width: 8),
                    Text(
                      '${widget.currentPage + 1} / ${widget.totalPages}',
                      style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, fontFamily: '.SF Mono', fontFamilyFallback: ['JetBrains Mono', 'monospace'], color: Colors.white, letterSpacing: 0.3),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
