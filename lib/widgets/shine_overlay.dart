import 'package:flutter/material.dart';

/// Sweeping shine highlight that animates across its parent.
/// Place inside a Stack with the parent content. The parent must
/// have `clipBehavior: Clip.hardEdge` or be wrapped in ClipRRect.
///
/// Matches the v2 design `v2-shine` animation: 3s infinite sweep.
class ShineOverlay extends StatefulWidget {
  final Duration duration;

  const ShineOverlay({
    super.key,
    this.duration = const Duration(seconds: 3),
  });

  @override
  State<ShineOverlay> createState() => _ShineOverlayState();
}

class _ShineOverlayState extends State<ShineOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: widget.duration,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      _controller.stop();
      _controller.value = 1; // sweep parked off-card
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        // Sweep from -100% to +250% matching CSS translateX range
        final t = _controller.value;
        final startX = -1.0 + t * 3.5;
        final endX = startX + 0.4;
        return Positioned.fill(
          child: IgnorePointer(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment(startX, 0),
                  end: Alignment(endX, 0),
                  colors: const [
                    Colors.transparent,
                    Color(0x38FFFFFF), // ~22% white
                    Colors.transparent,
                  ],
                  stops: const [0.0, 0.5, 1.0],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
