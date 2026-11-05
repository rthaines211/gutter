import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/comic_style.dart';
import '../config/scheme.dart';
import '../services/bedtime_reminder.dart';
import 'liquid_glass.dart';

/// Bedtime reminder: a glass card that slides up from the bottom with the
/// time, a one-tap Start and a 30-minute Later. Only the card takes touches; the page stays
/// live around it. Fades out on its own after [visibleFor].
class BedtimeCard extends ConsumerStatefulWidget {
  const BedtimeCard({
    super.key,
    required this.minutes,
    required this.accent,
    required this.onStart,
    required this.onDismiss,
    required this.onSnooze,
    this.visibleFor = const Duration(seconds: 8),
  });

  final int minutes;
  final Color accent;
  final VoidCallback onStart;
  final VoidCallback onDismiss;
  final VoidCallback onSnooze;
  final Duration visibleFor;

  @override
  ConsumerState<BedtimeCard> createState() => _BedtimeCardState();
}

class _BedtimeCardState extends ConsumerState<BedtimeCard>
    with SingleTickerProviderStateMixin {
  late final _anim = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 350))
    ..forward();
  late final _curve = CurvedAnimation(parent: _anim, curve: Curves.easeOutBack);
  late final Timer _timeout;
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    _timeout = Timer(widget.visibleFor, () => _close(widget.onDismiss));
  }

  bool get _reduced => MediaQuery.maybeDisableAnimationsOf(context) ?? false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_reduced) _anim.value = 1;
  }

  @override
  void dispose() {
    _timeout.cancel();
    _curve.dispose();
    _anim.dispose();
    super.dispose();
  }

  Future<void> _close(VoidCallback then) async {
    if (_closing) return;
    _closing = true;
    _timeout.cancel();
    if (!_reduced) await _anim.reverse();
    then();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    final comic = ComicTokens.watch(ref, context, widget.accent);
    final time = TimeOfDay.fromDateTime(clock.now()).format(context);

    Widget button(String label, {required bool primary, required VoidCallback onTap}) =>
        Expanded(
          child: GestureDetector(
            onTap: () {
              HapticFeedback.selectionClick();
              _close(onTap);
            },
            child: Container(
              height: 48,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: primary ? widget.accent : scheme.s2,
                borderRadius: BorderRadius.circular(14),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 8),
              // Three buttons share a phone-width card; shrink rather than wrap.
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(label,
                    style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: primary ? Scheme.onAccent(widget.accent) : scheme.tx)),
              ),
            ),
          ),
        );

    final card = Container(
      // Comic styles get the same ink border + hard shadow as the toolbar glass.
      decoration: comic.hardShadow
          ? BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: comic.ink, width: comic.borderWidth),
              boxShadow: comic.cardShadow,
            )
          : null,
      child: LiquidGlass(
        radius: 24,
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(children: [
              Icon(Icons.bedtime, size: 40, color: widget.accent),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("It's $time",
                        style: TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.w700,
                            color: scheme.tx)),
                    const SizedBox(height: 2),
                    Text('Set a sleep timer?',
                        style: TextStyle(fontSize: 16, color: scheme.t2)),
                  ],
                ),
              ),
            ]),
            const SizedBox(height: 18),
            Row(children: [
              button('Not tonight', primary: false, onTap: widget.onDismiss),
              const SizedBox(width: 12),
              button('Later ${kBedtimeSnooze.inMinutes}m',
                  primary: false, onTap: widget.onSnooze),
              const SizedBox(width: 12),
              button('Start ${widget.minutes}m', primary: true, onTap: widget.onStart),
            ]),
          ],
        ),
      ),
    );

    return SafeArea(
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: AnimatedBuilder(
              animation: _curve,
              builder: (context, child) => Opacity(
                opacity: _anim.value,
                child: Transform.translate(
                    offset: Offset(0, 60 * (1 - _curve.value)), child: child),
              ),
              child: card,
            ),
          ),
        ),
      ),
    );
  }
}
