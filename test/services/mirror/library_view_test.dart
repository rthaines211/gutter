import 'package:flutter_test/flutter_test.dart';
import 'package:comic_reader_app/models/library_filter.dart';
import 'package:comic_reader_app/models/series.dart';
import 'package:comic_reader_app/services/mirror/library_view.dart';
import 'package:comic_reader_app/services/mirror/mirror_database.dart';

MirrorSeries ms({
  required String id,
  required String name,
  String? publisher,
  String? writer,
  List<String> genres = const [],
  int? year,
  int issueCount = 10,
  int readCount = 0,
  DateTime? createdAt,
  DateTime? updatedAt,
  DateTime? lastReadAt,
}) =>
    MirrorSeries(
      series: Series(
        id: id,
        name: name,
        folderPath: '/$id',
        issueCount: issueCount,
        readCount: readCount,
        coverUrl: '',
        writer: writer,
        publisher: publisher,
        genres: genres,
        year: year,
        createdAt: createdAt ?? updatedAt ?? DateTime.utc(2026, 1, 1),
        updatedAt: updatedAt ?? DateTime.utc(2026, 1, 1),
      ),
      lastReadAt: lastReadAt,
    );

void main() {
  final all = [
    ms(id: 'a', name: 'Batman', publisher: 'DC', writer: 'Tom King [40724], Scott Snyder', genres: ['Action'], year: 2016, readCount: 10),
    ms(id: 'b', name: 'X-Men', publisher: 'Marvel', writer: 'Jonathan Hickman', genres: ['Action', 'Sci-Fi'], year: 2019, readCount: 3, lastReadAt: DateTime.utc(2026, 1, 15)),
    ms(id: 'c', name: 'Saga', publisher: 'Image', writer: 'Brian K. Vaughan', genres: ['Sci-Fi'], year: 2012, lastReadAt: DateTime.utc(2026, 2, 1)),
  ];

  test('splitCreators handles commas and ComicVine IDs', () {
    expect(splitCreators('Tom King [40724], Scott Snyder'),
        ['Tom King', 'Scott Snyder']);
    expect(splitCreators(null), isEmpty);
  });

  test('query filters by name, case-insensitive', () {
    final out = applyLibraryFilter(all, const LibraryFilter(query: 'bat'));
    expect(out.single.name, 'Batman');
  });

  test('status filter', () {
    expect(applyLibraryFilter(all, const LibraryFilter(status: 'completed')).single.id, 'a');
    expect(applyLibraryFilter(all, const LibraryFilter(status: 'in_progress')).single.id, 'b');
    expect(applyLibraryFilter(all, const LibraryFilter(status: 'unread')).single.id, 'c');
    expect(
        applyLibraryFilter(all, const LibraryFilter(status: 'on_device'),
                onDevice: {'b'})
            .single
            .id,
        'b');
  });

  test('facet filters: publisher, genre, writer (split), year range', () {
    expect(applyLibraryFilter(all, const LibraryFilter(publisher: 'Marvel')).single.id, 'b');
    expect(applyLibraryFilter(all, const LibraryFilter(genre: 'Sci-Fi')).map((s) => s.id), ['c', 'b']);
    expect(applyLibraryFilter(all, const LibraryFilter(writer: 'Scott Snyder')).single.id, 'a');
    expect(applyLibraryFilter(all, const LibraryFilter(yearMin: 2015, yearMax: 2017)).single.id, 'a');
  });

  test('sorts: name asc default, year desc, recently_read puts nulls last', () {
    expect(applyLibraryFilter(all, const LibraryFilter()).map((s) => s.id), ['a', 'c', 'b']);
    expect(applyLibraryFilter(all, const LibraryFilter(sort: 'year', order: 'desc')).map((s) => s.id), ['b', 'a', 'c']);
    // recently_read desc: c (Feb 1) > b (Jan 15) > a (null, always last)
    expect(
      applyLibraryFilter(all, const LibraryFilter(sort: 'recently_read', order: 'desc')).map((s) => s.id),
      ['c', 'b', 'a'],
    );
    // recently_read asc: b (Jan 15) < c (Feb 1), a (null) still last
    expect(
      applyLibraryFilter(all, const LibraryFilter(sort: 'recently_read', order: 'asc')).map((s) => s.id),
      ['b', 'c', 'a'],
    );
  });

  test('recent sorts by createdAt, not updatedAt', () {
    // 'old' was added first but touched most recently (rescan/enrichment);
    // 'new' was added most recently. desc = newest-added first.
    final rows = [
      ms(id: 'old', name: 'Old', createdAt: DateTime.utc(2020, 1, 1), updatedAt: DateTime.utc(2026, 8, 1)),
      ms(id: 'new', name: 'New', createdAt: DateTime.utc(2026, 7, 1), updatedAt: DateTime.utc(2026, 7, 1)),
    ];
    expect(
      applyLibraryFilter(rows, const LibraryFilter(sort: 'recent', order: 'desc')).map((s) => s.id),
      ['new', 'old'],
    );
  });

  test('isRecentlyAdded: true inside window, false for epoch sentinel', () {
    final now = DateTime.now();
    expect(ms(id: 'x', name: 'X', createdAt: now.subtract(const Duration(days: 3)))
        .series.isRecentlyAdded, isTrue);
    expect(ms(id: 'y', name: 'Y', createdAt: now.subtract(const Duration(days: 30)))
        .series.isRecentlyAdded, isFalse);
    // Backend backfills pre-existing series to the epoch sentinel.
    expect(ms(id: 'z', name: 'Z', createdAt: DateTime.utc(1970, 1, 1))
        .series.isRecentlyAdded, isFalse);
  });

  test('computeFacets counts with other filters applied, ignoring query', () {
    final pubs = computeFacets(all, 'publisher', const LibraryFilter(genre: 'Sci-Fi', query: 'ignored'));
    expect(pubs.map((f) => '${f.value}:${f.count}'), ['Image:1', 'Marvel:1']);
    final writers = computeFacets(all, 'writer', const LibraryFilter());
    expect(writers.firstWhere((f) => f.value == 'Tom King').count, 1);
  });

  test('computeFacets: count-desc ordering, tie broken by value asc', () {
    // Add a fixture with genre 'Action' so Action=3, Sci-Fi=2 — distinct counts.
    final withExtra = [
      ...all,
      ms(id: 'd', name: 'Daredevil', genres: ['Action'], readCount: 0),
    ];
    final genres = computeFacets(withExtra, 'genre', const LibraryFilter());
    // Action:3 should come before Sci-Fi:2
    expect(genres.map((f) => '${f.value}:${f.count}'), ['Action:3', 'Sci-Fi:2']);
  });

  test('computeFacets: year facet excludes year==0', () {
    final withZero = [
      ...all,
      ms(id: 'z', name: 'Unknown Year', year: 0),
    ];
    final years = computeFacets(withZero, 'year', const LibraryFilter());
    expect(years.map((f) => f.value), isNot(contains('0')));
    // The three real years are still present
    expect(years.map((f) => f.value), containsAll(['2012', '2016', '2019']));
  });
}
