/// Horizontal pixel offset (from the left edge of the slider area) at which a
/// bookmark tick for [page] should be painted, given a slider of [trackWidth]
/// px. Both ends are inset by [thumbRadius] so ticks line up with the thumb's
/// travel rather than the raw container edges.
///
/// Returns the left inset for single-page comics and clamps out-of-range pages
/// into the usable track.
double bookmarkTickOffset({
  required int page,
  required int totalPages,
  required double trackWidth,
  double thumbRadius = 9,
}) {
  final usable = trackWidth - 2 * thumbRadius;
  if (totalPages <= 1 || usable <= 0) return thumbRadius;
  final fraction = (page / (totalPages - 1)).clamp(0.0, 1.0);
  final offset = thumbRadius + fraction * usable;
  return offset.clamp(thumbRadius, trackWidth - thumbRadius);
}

/// Number of thumbnail columns for the page grid given the available [width].
int pageGridColumns(double width) {
  if (width < 600) return 4;
  if (width < 900) return 6;
  if (width < 1200) return 8;
  return 10;
}
