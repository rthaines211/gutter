import '../config/creator_roles.dart';
import '../models/creator.dart';
import '../models/creator_profile.dart';
import 'mirror/library_view.dart' show splitCreators;
import 'mirror/mirror_database.dart' show MirrorSeries;

/// "In progress": has been read at least once, and isn't fully read.
bool isInProgress(MirrorSeries m) =>
    m.lastReadAt != null && m.series.readCount < m.series.issueCount;

/// Owned series credited to [id] (by ComicVine person id) or, when [id] is
/// 0, credited to [name] case-insensitively — either via ComicVine `creators`
/// or the legacy comma-separated `writer`/`penciller` fields.
List<MirrorSeries> ownedByCreator(
  List<MirrorSeries> all, {
  required int id,
  required String name,
}) {
  if (id != 0) {
    return all.where((m) => m.series.creators.any((c) => c.id == id)).toList();
  }
  final lowerName = name.toLowerCase();
  return all.where((m) {
    final s = m.series;
    if (s.creators.any((c) => c.name.toLowerCase() == lowerName)) return true;
    if (splitCreators(s.writer).any((n) => n.toLowerCase() == lowerName)) {
      return true;
    }
    if (splitCreators(s.penciller).any((n) => n.toLowerCase() == lowerName)) {
      return true;
    }
    return false;
  }).toList();
}

/// A bibliography-less profile built entirely from owned series — used when
/// the server is unreachable or doesn't know this creator.
CreatorProfile ownedOnlyProfile(int id, String name, List<MirrorSeries> owned) {
  final lowerName = name.toLowerCase();
  final roles = <String>{};
  for (final m in owned) {
    final s = m.series;
    for (final c in s.creators) {
      final isMatch = id != 0 ? c.id == id : c.name.toLowerCase() == lowerName;
      if (isMatch) roles.add(c.role);
    }
    if (id == 0) {
      if (splitCreators(s.writer).any((n) => n.toLowerCase() == lowerName)) {
        roles.add('writer');
      }
      if (splitCreators(s.penciller).any((n) => n.toLowerCase() == lowerName)) {
        roles.add('penciller');
      }
    }
  }
  return CreatorProfile(
    id: id,
    name: name,
    roles: roles.toList(),
    seriesIds: owned.map((m) => m.series.id).toList(),
    volumesOwned: owned.length,
    volumesTotal: owned.length,
    bibliography: null,
    bibliographyPending: false,
  );
}

/// Total issues read across [owned] series.
int issuesRead(List<MirrorSeries> owned) =>
    owned.fold(0, (sum, m) => sum + m.series.readCount);

/// The creator summary matching [c] in [candidates], by ID when [c.id] is
/// non-zero, otherwise by case-insensitive name.
CreatorSummary? _findSummary(List<CreatorSummary> candidates, Creator c) {
  for (final summary in candidates) {
    final isMatch = c.id != 0
        ? summary.id == c.id
        : summary.name.toLowerCase() == c.name.toLowerCase();
    if (isMatch) return summary;
  }
  return null;
}

/// Issues-read totals keyed by ComicVine person id and by lowercased name,
/// built in one pass over [all] — the fallback path of [pickSpotlight] used
/// to call `issuesRead(ownedByCreator(all, ...))` once per creator, which is
/// one full scan of every series (and its creator list) per creator. A
/// series contributes its `readCount` at most once per id/name, matching
/// [ownedByCreator]'s de-duplicated `.where` semantics.
({Map<int, int> byId, Map<String, int> byName}) _issuesReadIndex(
    List<MirrorSeries> all) {
  final byId = <int, int>{};
  final byName = <String, int>{};
  for (final m in all) {
    final s = m.series;
    final ids = <int>{};
    final names = <String>{};
    for (final c in s.creators) {
      if (c.id != 0) ids.add(c.id);
      names.add(c.name.toLowerCase());
    }
    names.addAll(splitCreators(s.writer).map((n) => n.toLowerCase()));
    names.addAll(splitCreators(s.penciller).map((n) => n.toLowerCase()));
    for (final id in ids) {
      byId[id] = (byId[id] ?? 0) + s.readCount;
    }
    for (final name in names) {
      byName[name] = (byName[name] ?? 0) + s.readCount;
    }
  }
  return (byId: byId, byName: byName);
}

/// The creator to feature on the home/library screen:
/// - The writer (or, failing that, an artist) of the most recently read
///   in-progress series, if that creator is in [creators].
/// - Otherwise, whichever creator in [creators] has read the most issues.
/// - Otherwise null.
CreatorSummary? pickSpotlight(List<CreatorSummary> creators, List<MirrorSeries> all) {
  final inProgress = all.where(isInProgress).toList()
    ..sort((a, b) => b.lastReadAt!.compareTo(a.lastReadAt!));
  if (inProgress.isNotEmpty) {
    final latest = inProgress.first.series;
    Creator? candidate;
    for (final c in latest.creators) {
      if (roleGroup(c.role) == CreatorRoleGroup.writer) {
        candidate = c;
        break;
      }
    }
    if (candidate == null) {
      for (final c in latest.creators) {
        if (roleGroup(c.role) == CreatorRoleGroup.art) {
          candidate = c;
          break;
        }
      }
    }
    if (candidate != null) {
      final match = _findSummary(creators, candidate);
      if (match != null) return match;
    }
  }

  final index = _issuesReadIndex(all);
  CreatorSummary? best;
  var bestCount = 0;
  for (final c in creators) {
    final count =
        c.id != 0 ? (index.byId[c.id] ?? 0) : (index.byName[c.name.toLowerCase()] ?? 0);
    if (count > bestCount) {
      bestCount = count;
      best = c;
    }
  }
  return bestCount > 0 ? best : null;
}

/// The next unread (or in-progress) issue for creator [c]: from the most
/// recently read in-progress owned series first, then the newest owned
/// series. Null when nothing is owned or everything is fully read.
({String seriesId, String issueId})? nextByCreator(
  CreatorSummary c,
  List<MirrorSeries> all,
) {
  final owned = ownedByCreator(all, id: c.id, name: c.name);
  if (owned.isEmpty) return null;

  final inProgress = owned.where(isInProgress).toList()
    ..sort((a, b) => b.lastReadAt!.compareTo(a.lastReadAt!));
  final newest = owned.toList()
    ..sort((a, b) => b.series.createdAt.compareTo(a.series.createdAt));

  for (final m in [...inProgress, ...newest]) {
    final issueId = m.nextUnreadIssueId;
    if (issueId != null) {
      return (seriesId: m.series.id, issueId: issueId);
    }
  }
  return null;
}

/// The role group with the most distinct bibliography volumes (a volume
/// counts once per group even if several of its roles map to that group),
/// ties broken writer > art > covers.
CreatorRoleGroup defaultGroup(List<BibliographyVolume> vols) {
  final counts = <CreatorRoleGroup, int>{};
  for (final v in vols) {
    final groups = <CreatorRoleGroup>{};
    for (final role in v.roles) {
      final g = roleGroup(role);
      if (g != null) groups.add(g);
    }
    for (final g in groups) {
      counts[g] = (counts[g] ?? 0) + 1;
    }
  }
  const order = [
    CreatorRoleGroup.writer,
    CreatorRoleGroup.art,
    CreatorRoleGroup.covers,
  ];
  var best = CreatorRoleGroup.writer;
  var bestCount = -1;
  for (final g in order) {
    final count = counts[g] ?? 0;
    if (count > bestCount) {
      bestCount = count;
      best = g;
    }
  }
  return best;
}
