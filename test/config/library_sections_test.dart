import 'package:flutter_test/flutter_test.dart';
import 'package:comic_reader_app/config/library_sections.dart';
import 'package:comic_reader_app/config/sort_title.dart';
import 'package:comic_reader_app/models/series.dart';

// Verified against lib/models/series.dart — `id` is a String, and the field
// is `readCount`, not `unreadCount`.
Series _s(String name, {String? publisher}) => Series(
      id: name,
      name: name,
      folderPath: '/$name',
      issueCount: 1,
      readCount: 0,
      coverUrl: '',
      publisher: publisher,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );

List<Series> _sortedNames(List<String> names) {
  final list = names.map(_s).toList()
    ..sort((a, b) => sortTitle(a.name).compareTo(sortTitle(b.name)));
  return list;
}

void main() {
  test('groups a sorted list into contiguous sections', () {
    final sections = sectionize(_sortedNames(
        ['Batgirl', 'The Batman', 'Avengers', 'Saga']));
    expect(sections.map((s) => s.key).toList(), ['A', 'B', 'S']);
    expect(sections[1].series.map((s) => s.name).toList(),
        ['Batgirl', 'The Batman']);
  });

  test('files digits and symbols under # and sorts them first', () {
    final sections = sectionize(_sortedNames(['Saga', '100 Bullets']));
    expect(sections.first.key, '#');
  });

  test('an empty list yields no sections', () {
    expect(sectionize([]), isEmpty);
  });

  test('one series yields one section of one', () {
    final sections = sectionize(_sortedNames(['Saga']));
    expect(sections.length, 1);
    expect(sections.single.series.length, 1);
  });

  test('presentKeys lists each section once, in order', () {
    final sections = sectionize(_sortedNames(
        ['Avengers', 'Astro City', 'Batgirl']));
    expect(presentKeys(sections), ['A', 'B']);
  });

  test('section counts sum to the input length', () {
    final input = _sortedNames(
        ['Saga', 'Batgirl', 'The Batman', 'Avengers', '100 Bullets']);
    final sections = sectionize(input);
    final total = sections.fold<int>(0, (n, s) => n + s.series.length);
    expect(total, input.length);
  });

  // sectionize() requires already-name-sorted input (see its doc comment).
  // A list sorted some other way (year, name-descending, etc.) is not
  // alphabetically contiguous, so the same letter key can recur —
  // duplicate/repeating pinned headers in the UI. This is why
  // library_screen.dart must guard sectioning on filter.sort == 'name' &&
  // filter.order == 'asc' and fall back to the flat grid otherwise; don't
  // remove that guard thinking it's redundant.
  test('non-name-sorted input fragments into repeated section keys', () {
    // Not sorted by sortTitle — simulates e.g. sort-by-year order.
    final input = [_s('Avengers'), _s('Batgirl'), _s('Astro City'), _s('Batman')];
    final sections = sectionize(input);
    final keys = sections.map((s) => s.key).toList();
    expect(keys, ['A', 'B', 'A', 'B']);
    expect(keys.toSet().length, lessThan(keys.length));
  });

  group('sectionizeByPublisher', () {
    test('groups A-Z with Unknown last', () {
      final out = sectionizeByPublisher([
        _s('Saga', publisher: 'Image'),
        _s('Thor', publisher: 'Marvel'),
        _s('Orphan', publisher: null),
        _s('Batman', publisher: 'DC Comics'),
      ]);
      expect(out.map((e) => e.key), ['DC Comics', 'Image', 'Marvel', 'Unknown']);
    });

    test('folds duplicate publisher names onto one section', () {
      // The live library reports both "DC"(3) and "DC Comics"(152).
      final out = sectionizeByPublisher([
        _s('Batman', publisher: 'DC Comics'),
        _s('Superman', publisher: 'DC'),
        _s('Vault A', publisher: 'Vault'),
        _s('Vault B', publisher: 'Vault Comics'),
      ]);
      expect(out.map((e) => e.key), ['DC Comics', 'Vault Comics']);
      expect(out.first.series.length, 2);
      expect(out.last.series.length, 2);
    });

    test('empty publisher is Unknown, not its own blank section', () {
      final out = sectionizeByPublisher([
        _s('A', publisher: '   '),
        _s('B', publisher: ''),
      ]);
      expect(out.map((e) => e.key), ['Unknown']);
      expect(out.single.series.length, 2);
    });

    test('preserves incoming title order inside a group', () {
      final out = sectionizeByPublisher([
        _s('Zeta', publisher: 'Marvel'),
        _s('Alpha', publisher: 'Marvel'),
      ]);
      expect(out.single.series.map((e) => e.name), ['Zeta', 'Alpha']);
    });
  });
}
