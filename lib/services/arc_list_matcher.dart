import '../models/series.dart';

/// One pasted line and the library issue it matched (null = not found).
class ArcLineMatch {
  final String line;
  final SeriesIssue? issue;
  const ArcLineMatch(this.line, this.issue);
}

final _bullet = RegExp(r'^\s*(?:[-*•]\s*)?(?:\[[ xX]?\]\s*)?(?:\d+[.)]\s+)?');
final _hashNumber = RegExp(r'^(.*?)\s*#\s*(\d+(?:\.\d+)?[a-zA-Z]?)');
final _trailingNumber = RegExp(r'^(.*\D)\s+(\d+(?:\.\d+)?)[.,;:]*$');
final _year = RegExp(r'\((\d{4})(?:-\d{4})?\)');

/// Lower-case letters and digits only, years dropped, `&` read as "and".
/// "Ultimate Universe – Finale (2026)" and "Ultimate Universe: Finale" agree.
String _seriesKey(String name) => name
    .replaceAll(_year, '')
    .toLowerCase()
    .replaceAll('&', 'and')
    .replaceAll(RegExp(r'[^a-z0-9]'), '');

String _numberKey(String n) {
  final t = n.trim().toLowerCase();
  final stripped = t.replaceFirst(RegExp(r'^0+(?=\d)'), '');
  return stripped;
}

final _parens = RegExp(r'\([^)]*\)');
final _nameNumber = RegExp(r'(\d+(?:\.\d+)?)\s*$');

/// The issue's number, else the trailing number in its file name: the
/// scanner leaves `number` empty for names like "Ultimate Endgame 1 (2026).cbz".
String? _issueNumber(SeriesIssue i) {
  final n = i.number?.trim();
  if (n != null && n.isNotEmpty) return n;
  final bare = i.name.replaceFirst(RegExp(r'\.\w+$'), '').replaceAll(_parens, '').trim();
  return _nameNumber.firstMatch(bare)?.group(1);
}

int _yearOf(String name) =>
    int.tryParse(_year.firstMatch(name)?.group(1) ?? '') ?? 0;

/// Matches a pasted reading order ("- [ ] 3. Ultimates #19", one per line)
/// to library issues by series name + issue number. When several series
/// share a name ("Ultimates", "Ultimates (2024)"), a year on the line picks
/// one; otherwise the newest series that has that number wins.
/// ponytail: exact-name match only; add fuzzy matching if real lists miss.
List<ArcLineMatch> matchArcList(String text, List<SeriesIssue> issues) {
  final byKey = <String, List<SeriesIssue>>{};
  for (final i in issues) {
    final n = _issueNumber(i);
    final s = i.seriesName;
    if (n == null || s == null) continue;
    byKey.putIfAbsent('${_seriesKey(s)}#${_numberKey(n)}', () => []).add(i);
  }

  final out = <ArcLineMatch>[];
  for (final raw in text.split('\n')) {
    final line = raw.replaceFirst(_bullet, '').trim();
    if (line.isEmpty) continue;
    // A year can sit anywhere ("Ultimates (2024) #19", "Ultimates #19 (2024)").
    final year = _yearOf(line);
    final bare = line.replaceAll(_parens, ' ').trim();
    final m = _hashNumber.firstMatch(bare) ?? _trailingNumber.firstMatch(bare);
    if (m == null) {
      out.add(ArcLineMatch(line, null));
      continue;
    }
    final name = m.group(1)!;
    var candidates =
        byKey['${_seriesKey(name)}#${_numberKey(m.group(2)!)}'] ?? const [];
    if (year > 0) {
      final sameYear =
          candidates.where((c) => _yearOf(c.seriesName!) == year).toList();
      // No series carries that year in its name: keep them all.
      if (sameYear.isNotEmpty) candidates = sameYear;
    }
    SeriesIssue? best;
    for (final c in candidates) {
      if (best == null || _yearOf(c.seriesName!) > _yearOf(best.seriesName!)) {
        best = c;
      }
    }
    out.add(ArcLineMatch(line, best));
  }
  return out;
}
