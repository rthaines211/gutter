import '../../config/sort_title.dart';
import '../../models/comic_info.dart';
import '../../models/creator.dart';
import '../../models/facet_value.dart';
import '../../models/library_filter.dart';
import '../../models/series.dart';
import 'mirror_database.dart' show MirrorSeries;

/// Splits ComicInfo creator strings: "Tom King [40724], Scott Snyder"
/// -> ["Tom King", "Scott Snyder"]. Mirrors the server's splitCreators +
/// stripComicVineID (server/facets.go).
List<String> splitCreators(String? raw) {
  if (raw == null || raw.isEmpty) return const [];
  return raw
      .split(',')
      .map((s) => s.replaceAll(RegExp(r'\s*\[\d+\]\s*$'), '').trim())
      .where((s) => s.isNotEmpty)
      .toList();
}

final _trailingId = RegExp(r'^(.*?)\s*\[(\d+)\]\s*$');

/// Reader credits-sheet fallback for when ComicVine issue credits aren't
/// available: builds [Creator]s straight from ComicInfo's writer/penciller
/// fields. Same comma + trailing "[id]" shape as [splitCreators], but kept
/// separate since it also needs the parsed id, not just the stripped name.
List<Creator> creditsFromComicInfo(ComicInfo? info) {
  if (info == null) return const [];
  final out = <Creator>[];
  void addAll(String? raw, String role) {
    if (raw == null || raw.isEmpty) return;
    for (final part in raw.split(',')) {
      final match = _trailingId.firstMatch(part.trim());
      final name = (match?.group(1) ?? part).trim();
      if (name.isEmpty) continue;
      final id = int.tryParse(match?.group(2) ?? '') ?? 0;
      out.add(Creator(id: id, name: name, role: role));
    }
  }

  addAll(info.writer, 'writer');
  addAll(info.penciller, 'penciller');
  return out;
}

bool _matchesStatus(Series s, String status, Set<String>? onDevice) {
  switch (status) {
    case 'on_device':
      return onDevice?.contains(s.id) ?? true;
    case 'unread':
      return s.isUnread;
    case 'in_progress':
      return s.isInProgress;
    case 'completed':
      return s.isCompleted;
    default:
      return true;
  }
}

bool _matchesMeta(Series s, LibraryFilter f) {
  if (f.publisher != null && s.publisher != f.publisher) return false;
  if (f.genre != null && !s.genres.contains(f.genre)) return false;
  if (f.writer != null && !splitCreators(s.writer).contains(f.writer)) {
    return false;
  }
  if (f.penciller != null &&
      !splitCreators(s.penciller).contains(f.penciller)) {
    return false;
  }
  if (f.yearMin != null && (s.year == null || s.year! < f.yearMin!)) {
    return false;
  }
  if (f.yearMax != null && (s.year == null || s.year! > f.yearMax!)) {
    return false;
  }
  return true;
}

/// Note: for `recent`, `recently_read`, and `unread` sorts this implementation
/// uses natural direction semantics (desc = newest/most first). This
/// intentionally diverges from the legacy server comparators which were
/// pre-inverted; the UI defaults these sorts to desc and expects newest-first.
/// [onDevice] = series ids with a download, for the 'on_device' status.
List<Series> applyLibraryFilter(List<MirrorSeries> all, LibraryFilter f,
    {Set<String>? onDevice}) {
  final q = f.query.toLowerCase();
  final filtered = all.where((m) {
    final s = m.series;
    if (q.isNotEmpty && !s.name.toLowerCase().contains(q)) return false;
    if (!_matchesStatus(s, f.status, onDevice)) return false;
    return _matchesMeta(s, f);
  }).toList();

  final dir = f.order == 'desc' ? -1 : 1;
  int byName(MirrorSeries a, MirrorSeries b) =>
      sortTitle(a.series.name).compareTo(sortTitle(b.series.name));

  filtered.sort((a, b) {
    int c;
    switch (f.sort) {
      case 'unread':
      case 'unread_count':
        c = a.series.unreadCount.compareTo(b.series.unreadCount);
      case 'recent':
        // "Recently Added" = when the series entered the library (created_at),
        // not last touched by a rescan/cover/enrichment (updated_at).
        c = a.series.createdAt.compareTo(b.series.createdAt);
      case 'recently_read':
        final la = a.lastReadAt, lb = b.lastReadAt;
        if (la == null && lb == null) {
          c = 0;
        } else if (la == null) {
          return 1; // never-read always last, regardless of order
        } else if (lb == null) {
          return -1;
        } else {
          c = la.compareTo(lb);
        }
      case 'publisher':
        c = (a.series.publisher ?? '')
            .toLowerCase()
            .compareTo((b.series.publisher ?? '').toLowerCase());
      case 'year':
        c = (a.series.year ?? 0).compareTo(b.series.year ?? 0);
      case 'issue_count':
        c = a.series.issueCount.compareTo(b.series.issueCount);
      case 'progress':
        c = a.series.progress.compareTo(b.series.progress);
      default:
        c = byName(a, b);
    }
    if (c == 0) c = byName(a, b);
    return c * dir;
  });

  return filtered.map((m) => m.series).toList();
}

/// Filter-aware facet counts. Status + metadata filters apply; the text query
/// does not (the app never passed `q` to /facets either).
List<FacetValue> computeFacets(
    List<MirrorSeries> all, String facet, LibraryFilter f) {
  final base = all.where(
      (m) => _matchesStatus(m.series, f.status, null) && _matchesMeta(m.series, f));
  final counts = <String, int>{};
  for (final m in base) {
    final s = m.series;
    final values = switch (facet) {
      'publisher' => [
          if (s.publisher != null && s.publisher!.isNotEmpty) s.publisher!
        ],
      'genre' => s.genres.where((g) => g.isNotEmpty).toList(),
      'writer' => splitCreators(s.writer),
      'penciller' => splitCreators(s.penciller),
      'year' => [if (s.year != null && s.year != 0) s.year.toString()],
      _ => const <String>[],
    };
    for (final v in values) {
      counts[v] = (counts[v] ?? 0) + 1;
    }
  }
  return counts.entries
      .map((e) => FacetValue(value: e.key, count: e.value))
      .toList()
    ..sort((a, b) {
      if (a.count != b.count) return b.count.compareTo(a.count); // count desc
      return a.value.toLowerCase().compareTo(b.value.toLowerCase()); // value asc
    });
}
