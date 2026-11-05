import '../models/series.dart';
import 'sort_title.dart';

/// One A–Z group in the library.
class LibrarySection {
  final String key;
  final List<Series> series;
  LibrarySection(this.key, this.series);
}

/// Groups an ALREADY-SORTED list into contiguous sections.
///
/// The caller sorts (via `applyLibraryFilter`, which uses `sortTitle`); this
/// only groups. Sorting here as well would let the two diverge and break the
/// index rail's offset math.
List<LibrarySection> sectionize(List<Series> sorted) {
  final out = <LibrarySection>[];
  var currentKey = '';
  var run = <Series>[];
  void flush() {
    if (run.isNotEmpty) out.add(LibrarySection(currentKey, List.unmodifiable(run)));
  }

  for (final s in sorted) {
    final k = sectionKey(s.name);
    if (run.isNotEmpty && currentKey == k) {
      run.add(s);
    } else {
      flush();
      currentKey = k;
      run = [s];
    }
  }
  flush();
  return out;
}

/// The section keys present, in order.
List<String> presentKeys(List<LibrarySection> sections) =>
    sections.map((s) => s.key).toList();

/// Publishers the scanner reports under more than one name, keyed by the
/// lowercased variant. The real fix belongs in the backend scan, but that is a
/// separate repo — this keeps the library from showing "DC" and "DC Comics" as
/// two sections in the meantime.
const _publisherAliases = {
  'dc': 'DC Comics',
  'vault': 'Vault Comics',
};

const _unknownPublisher = 'Unknown';

/// Canonical display name for a series' publisher.
String publisherKey(String? raw) {
  final trimmed = (raw ?? '').trim();
  if (trimmed.isEmpty) return _unknownPublisher;
  return _publisherAliases[trimmed.toLowerCase()] ?? trimmed;
}

/// Groups by publisher, A–Z, with `Unknown` last.
///
/// Unlike [sectionize] this *does* sort: the incoming list is ordered by
/// `sortTitle`, which says nothing about publisher. Titles keep their incoming
/// order within each group.
List<LibrarySection> sectionizeByPublisher(List<Series> series) {
  final groups = <String, List<Series>>{};
  for (final s in series) {
    groups.putIfAbsent(publisherKey(s.publisher), () => []).add(s);
  }

  final keys = groups.keys.toList()
    ..sort((a, b) {
      // Unknown sinks to the bottom regardless of alphabet.
      if (a == _unknownPublisher) return 1;
      if (b == _unknownPublisher) return -1;
      return a.toLowerCase().compareTo(b.toLowerCase());
    });

  return [
    for (final k in keys) LibrarySection(k, List.unmodifiable(groups[k]!)),
  ];
}
