# Clip a panel: button only (no long-press)

Status: approved 2026-11-22. Small change.

## Why
Carrying the iPad, a resting thumb on the page long-presses and starts a panel clip.

## Design
- Remove long-press → clip in the reader (`_handleLongPress`). The ⋯ → **Clip a panel** button (one-time armed tap) is the only way in.
- Keep long-press → next balloon (only when a balloon is popped out in balloon zoom).
- Hints that say "Long-press inside a panel to clip it" point at ⋯ → Clip a panel instead.

## Approaches
- **Remove the long-press trigger (picked):** the button already exists; smallest change.
- Setting to keep long-press: not built (YAGNI); add if missed.
- Longer hold time: still fires on a resting thumb; rejected.

## Non-goals
No change to the armed-tap flow, the clip itself, or balloon swapping.
