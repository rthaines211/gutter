import '../models/series.dart';

/// Whole-number issues missing from a run, e.g. [4, 7] for #1–#10 without
/// #4 and #7.
///
/// Only plain integer numbers count; annuals, point issues (#1.MU) and
/// fractions are ignored, so they neither create nor fill gaps. Returns an
/// empty list when the run looks like a deliberate subset rather than a
/// collection with holes: fewer than two numbered issues, more missing than
/// present, or a span over [maxSpan] (legacy-numbered series).
List<int> missingIssueNumbers(
  Iterable<SeriesIssue> issues, {
  int maxSpan = 300,
}) {
  final present = <int>{};
  for (final issue in issues) {
    final n = int.tryParse(issue.number?.trim() ?? '');
    if (n != null && n >= 0) present.add(n);
  }
  if (present.length < 2) return const [];

  final sorted = present.toList()..sort();
  final lo = sorted.first;
  final hi = sorted.last;
  if (hi - lo > maxSpan) return const [];

  final missing = [
    for (var n = lo + 1; n < hi; n++)
      if (!present.contains(n)) n,
  ];
  if (missing.length > present.length) return const [];
  return missing;
}

/// One cell of the issue grid: a real issue, or a gap placeholder.
class IssueGridEntry {
  final SeriesIssue? issue;
  final int? missingNumber;

  const IssueGridEntry.issue(SeriesIssue this.issue) : missingNumber = null;
  const IssueGridEntry.missing(int this.missingNumber) : issue = null;

  bool get isMissing => missingNumber != null;
}

/// Interleaves gap placeholders into number-ordered [issues], each placed just
/// before the first issue numbered above it. Issues without an integer number
/// keep their position.
List<IssueGridEntry> withGaps(List<SeriesIssue> issues, List<int> missing) {
  if (missing.isEmpty) return [for (final i in issues) IssueGridEntry.issue(i)];
  final out = <IssueGridEntry>[];
  var m = 0;
  for (final issue in issues) {
    final n = int.tryParse(issue.number?.trim() ?? '');
    if (n != null) {
      while (m < missing.length && missing[m] < n) {
        out.add(IssueGridEntry.missing(missing[m++]));
      }
    }
    out.add(IssueGridEntry.issue(issue));
  }
  while (m < missing.length) {
    out.add(IssueGridEntry.missing(missing[m++]));
  }
  return out;
}
