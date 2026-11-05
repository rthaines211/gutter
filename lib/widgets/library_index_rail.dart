import 'package:flutter/material.dart';
import '../config/scheme.dart';

/// Right-edge A–Z index. Tap a letter to jump to its section, or drag along
/// the rail to scrub through them — the iOS Contacts gesture.
///
/// The rail is a `Stack` sibling painted over the scroll view, so it wins the
/// hit test for anything inside its bounds. A tap-only implementation
/// therefore SWALLOWS vertical drags: the pointer is absorbed but no drag
/// recogniser is registered, so the list underneath never sees it and simply
/// does not scroll. With 27 keys the rail is ~405pt tall, which on a landscape
/// iPad is a dead band down nearly half the right edge — exactly where a thumb
/// rests. Handling the drag here is what makes the rest of the screen
/// scrollable, so `onScrub` is required, not optional.
class LibraryIndexRail extends StatelessWidget {
  final List<String> allKeys;
  final Set<String> presentKeys;

  /// Called when a letter is tapped, or when a scrub crosses onto a new
  /// present letter. Absent letters never fire it.
  final ValueChanged<String> onTap;
  final Color accent;

  const LibraryIndexRail({
    super.key,
    required this.allKeys,
    required this.presentKeys,
    required this.onTap,
    required this.accent,
  });

  static const _itemHeight = 15.0;

  /// The key under [localY], or null if that position has no present letter.
  String? _keyAt(double localY) {
    final i = (localY / _itemHeight).floor();
    if (i < 0 || i >= allKeys.length) return null;
    final k = allKeys[i];
    return presentKeys.contains(k) ? k : null;
  }

  void _handleAt(Offset local, String? last, void Function(String) emit) {
    final k = _keyAt(local.dy);
    if (k != null && k != last) emit(k);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    // Tracks the last emitted key across a single drag so scrubbing does not
    // re-fire on every pointer move within one letter.
    String? lastScrubbed;

    return SizedBox(
      width: 22,
      child: GestureDetector(
        // One detector for the whole rail rather than one per letter: a drag
        // must be recognised across letter boundaries, and per-letter
        // detectors would each claim the gesture arena for their own box.
        behavior: HitTestBehavior.opaque,
        onTapDown: (d) => _handleAt(d.localPosition, null, onTap),
        onVerticalDragStart: (d) {
          lastScrubbed = null;
          _handleAt(d.localPosition, lastScrubbed, (k) {
            lastScrubbed = k;
            onTap(k);
          });
        },
        onVerticalDragUpdate: (d) => _handleAt(d.localPosition, lastScrubbed, (k) {
          lastScrubbed = k;
          onTap(k);
        }),
        onVerticalDragEnd: (_) => lastScrubbed = null,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: allKeys.map((k) {
            final present = presentKeys.contains(k);
            return SizedBox(
              height: _itemHeight,
              child: Center(
                child: Text(
                  k,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    fontFamily: '.SF Mono',
                    fontFamilyFallback: const ['JetBrains Mono', 'monospace'],
                    color: present ? accent : scheme.t4,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}
