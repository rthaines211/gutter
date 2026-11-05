/// Returns true if the image dimensions indicate a 2-page spread.
///
/// Any landscape image (wider than tall) is treated as a spread. Single comic
/// pages are always portrait (~0.65 aspect); a two-page spread doubles the
/// width, so its aspect is ~1.3 and up. The two populations are cleanly
/// separated with a huge gap between them, so a simple aspect > 1.0 cut is
/// robust across formats.
///
/// The previous threshold of 1.3 was set at the *lower edge* of the spread
/// cluster and silently failed on books whose spreads land at ~1.298–1.299
/// (e.g. the Jeff Lemire Green Arrow deluxe edition: singles 0.649, spreads
/// 1.299 — 35 of 36 spreads went undetected).
bool isSpread(int imageWidth, int imageHeight) {
  if (imageHeight <= 0) return false;
  return imageWidth / imageHeight > 1.0;
}
