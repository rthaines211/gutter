import 'dart:ui';

/// A tap on the reader maps to one of these actions. `left`/`right` are
/// PHYSICAL screen regions; the reader flips them for RTL downstream.
/// `back`/`forward` are LOGICAL and never flipped (one-handed thumb layout).
enum TapAction { left, right, back, forward, menu }

/// Explicit non-menu regions per layout, in normalized (0..1) coordinates.
/// `menu` is the implicit fallback for any point not inside a listed region,
/// so every layout is total. `disabled` lists nothing → menu everywhere.
const Map<String, List<(Rect, TapAction)>> _layouts = {
  'standard': [
    (Rect.fromLTRB(0, 0, 1 / 3, 1), TapAction.left),
    (Rect.fromLTRB(2 / 3, 0, 1, 1), TapAction.right),
  ],
  // Prev = left quarter, menu = center band (covers the middle so a
  // center tap opens the toolbar), next = the wider right portion.
  'edge': [
    (Rect.fromLTRB(0, 0, 0.25, 1), TapAction.left),
    (Rect.fromLTRB(0.25, 0, 0.55, 1), TapAction.menu),
    (Rect.fromLTRB(0.55, 0, 1, 1), TapAction.right),
  ],
  // One-handed, right thumb: right 40% strip, top half back, bottom half
  // forward, regardless of reading direction. Rest of the page is menu.
  'thumb': [
    (Rect.fromLTRB(0.6, 0, 1, 0.5), TapAction.back),
    (Rect.fromLTRB(0.6, 0.5, 1, 1), TapAction.forward),
  ],
  'disabled': [],
};

/// Resolves a normalized tap position to its action for [layout].
/// Unknown layouts fall back to `standard`.
TapAction actionAt(String layout, Offset normalized) {
  final regions = _layouts[layout] ?? _layouts['standard']!;
  for (final (rect, action) in regions) {
    if (rect.contains(normalized)) return action;
  }
  return TapAction.menu;
}
