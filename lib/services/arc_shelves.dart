import 'dart:math' as math;

import 'package:comic_reader_app/models/arc.dart';
import 'package:comic_reader_app/models/series.dart';

/// Splits an arc name into an upper-cased event "kicker" (from a leading
/// `"Quoted"` segment) and the remaining title.
///
/// `'"Avengers" One World Under Doom'` -> kicker `AVENGERS`, title
/// `'One World Under Doom'`. A quoted-only name (`'"Batman"'`) has no
/// remaining title, so the quoted text itself (as written, unquoted) becomes
/// the title and the kicker is empty. A name with no leading quoted part
/// just returns the trimmed name as the title.
({String kicker, String title}) arcDisplayName(String name) {
  final trimmed = name.trim();
  if (trimmed.startsWith('"')) {
    final closeIndex = trimmed.indexOf('"', 1);
    if (closeIndex != -1) {
      final quoted = trimmed.substring(1, closeIndex);
      final rest = trimmed.substring(closeIndex + 1).trim();
      if (rest.isNotEmpty) {
        return (kicker: quoted.toUpperCase(), title: rest);
      }
      if (quoted.isNotEmpty) {
        return (kicker: '', title: quoted);
      }
    }
  }
  return (kicker: '', title: trimmed);
}

/// Formats a start/end year range for display.
///
/// Empty when `start` is 0 (unknown). A single year when they're equal.
/// Same-century ranges abbreviate the end year (`'2025–26'`); otherwise the
/// end year is spelled out in full (`'1999–2001'`).
String arcYears(int start, int end) {
  if (start == 0) return '';
  if (start == end) return '$start';
  if (start ~/ 100 == end ~/ 100) {
    final shortEnd = (end % 100).toString().padLeft(2, '0');
    return '$start–$shortEnd';
  }
  return '$start–$end';
}

/// Formats the issue-count line shown under an arc's name.
///
/// Mylar arcs (`total > 0`) read as `'P OF T PRESENT'`; derived/ComicVine
/// arcs (`total == 0`) read as `'N ISSUES'`. The year range is appended with
/// a `' · '` separator when known.
String arcCountLabel(Arc a) {
  final base = _arcCount(a);
  final years = arcYears(a.startYear, a.endYear);
  return years.isEmpty ? base : '$base · $years';
}

String _arcCount(Arc a) => a.total > 0
    ? '${a.present} OF ${a.total} PRESENT'
    : '${a.present} ISSUES';

/// Detail-page meta line: `'DC COMICS · 2019–20 · 11 ISSUES'`, skipping
/// unknown parts.
String arcMetaLine(Arc a) => [
      a.publisher.toUpperCase(),
      arcYears(a.startYear, a.endYear),
      _arcCount(a),
    ].where((p) => p.isNotEmpty).join(' · ');

/// The issue to read next: the first in-progress issue, else the first
/// non-completed one; -1 when every issue is completed.
int arcCurrentIndex(List<SeriesIssue> issues) {
  final inProgress = issues.indexWhere((i) => i.status == 'in_progress');
  return inProgress >= 0
      ? inProgress
      : issues.indexWhere((i) => i.status != 'completed');
}

/// Page to open [i] at: completed issues restart from page 0.
int arcIssueStartPage(SeriesIssue i) =>
    i.status == 'completed' ? 0 : (i.currentPage ?? 0);

/// The arc's primary action: `'Start reading'` when nothing is started,
/// `'Read again'` when everything is read, else `'Continue #N'`.
String arcPrimaryLabel(List<SeriesIssue> issues) {
  final current = arcCurrentIndex(issues);
  if (current < 0) return 'Read again';
  if (issues.every((i) => i.status == 'unread')) return 'Start reading';
  return 'Continue ${issues[current].displayName}';
}

/// Start of a [size]-issue window showing [current] with two issues of
/// context above it, clamped so the window is always full.
int arcWindowStart(int count, int current, {int size = 20}) =>
    math.max(0, math.min(current - 2, count - size));

/// `'Batman #79'` for an arc row — the series name with any trailing
/// `' (YYYY)'` volume year stripped.
String arcIssueHeading(SeriesIssue i) {
  final series = i.seriesName?.replaceFirst(RegExp(r'\s*\(\d{4}\)$'), '');
  return series == null || series.isEmpty
      ? i.displayName
      : '$series ${i.displayName}';
}

const _months = [
  'JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN',
  'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC',
];

/// `'2019-09-01'` (or `'2019-09'`) -> `'SEP 2019'`; anything else is
/// returned upper-cased as-is.
String arcCoverDate(String? date) {
  if (date == null) return '';
  final m = RegExp(r'^(\d{4})-(\d{2})').firstMatch(date);
  final month = m == null ? 0 : int.parse(m.group(2)!);
  if (month < 1 || month > 12) return date.toUpperCase();
  return '${_months[month - 1]} ${m!.group(1)}';
}

class ArcShelf {
  final String title;
  final List<Arc> arcs;

  const ArcShelf({required this.title, required this.arcs});
}

const _moreEventsTitle = 'More events';

/// Groups arcs into the home-screen shelf layout.
///
/// - `inProgress`: arcs with `0 < read < present`, most recently read first.
/// - `featured`: the top 2 remaining arcs by `present` (ties by name).
/// - `shelves`: the rest, grouped by `publisher` — publishers with 2+ arcs
///   get their own shelf (ordered by arc count desc, then name); singletons
///   and blank-publisher arcs are collected into a trailing `'More events'`
///   shelf, omitted when empty. Arcs within every shelf are ordered by
///   `present` desc, then name.
({List<Arc> inProgress, List<Arc> featured, List<ArcShelf> shelves})
    buildArcShelves(List<Arc> arcs) {
  final inProgress = arcs.where((a) => a.read > 0 && a.read < a.present).toList()
    ..sort(_byLastReadAtDesc);

  final remaining = arcs.where((a) => !inProgress.contains(a)).toList()
    ..sort(_byPresentDescThenName);
  final featured = remaining.take(2).toList();

  final forShelves = remaining.skip(2).toList();

  final byPublisher = <String, List<Arc>>{};
  for (final a in forShelves) {
    byPublisher.putIfAbsent(a.publisher, () => []).add(a);
  }

  final namedGroups = <String, List<Arc>>{};
  final moreEvents = <Arc>[];
  for (final entry in byPublisher.entries) {
    if (entry.key.isNotEmpty && entry.value.length >= 2) {
      namedGroups[entry.key] = entry.value;
    } else {
      moreEvents.addAll(entry.value);
    }
  }

  final shelves = namedGroups.entries.toList()
    ..sort((x, y) {
      final byCount = y.value.length.compareTo(x.value.length);
      if (byCount != 0) return byCount;
      return x.key.compareTo(y.key);
    });

  final result = <ArcShelf>[
    for (final entry in shelves)
      ArcShelf(
        title: entry.key,
        arcs: entry.value.toList()..sort(_byPresentDescThenName),
      ),
  ];

  if (moreEvents.isNotEmpty) {
    result.add(ArcShelf(
      title: _moreEventsTitle,
      arcs: moreEvents..sort(_byPresentDescThenName),
    ));
  }

  return (inProgress: inProgress, featured: featured, shelves: result);
}

int _byLastReadAtDesc(Arc a, Arc b) {
  final aTime = a.lastReadAt;
  final bTime = b.lastReadAt;
  if (aTime == null && bTime == null) return 0;
  if (aTime == null) return 1;
  if (bTime == null) return -1;
  return bTime.compareTo(aTime);
}

int _byPresentDescThenName(Arc a, Arc b) {
  final byPresent = b.present.compareTo(a.present);
  if (byPresent != 0) return byPresent;
  return a.name.compareTo(b.name);
}
