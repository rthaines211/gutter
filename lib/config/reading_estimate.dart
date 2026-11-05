
/// Average reading speed: 0.5 minutes per comic page.
/// Used by resume hero card, next-up card, and TO FINISH stat tile.
const double kMinutesPerPage = 0.5;

/// Format a remaining page count as a human-readable reading time estimate.
///
/// Returns empty string if pages is 0. For small remainders (< 120 minutes),
/// formats as minutes with "min left" suffix. For large remainders (>= 120 minutes),
/// formats as hours with one decimal place and "h" suffix.
///
/// Examples:
/// - 0 pages → ""
/// - 6 pages → "3 min left"
/// - 144 pages → "1.2h"
String formatMinutesLeft(int pages) {
  if (pages == 0) {
    return '';
  }

  final totalMinutes = (pages * kMinutesPerPage).ceil();

  // Switch to hours format at 120 minutes (2 hours)
  if (totalMinutes > 120) {
    final hours = totalMinutes / 60.0;
    // Format with one decimal place
    return '${hours.toStringAsFixed(1)}h';
  }

  return '$totalMinutes min left';
}
