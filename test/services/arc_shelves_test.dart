// test/services/arc_shelves_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:comic_reader_app/models/arc.dart';
import 'package:comic_reader_app/models/series.dart';
import 'package:comic_reader_app/services/arc_shelves.dart';

Arc _arc({
  required String id,
  required String name,
  int total = 0,
  int present = 0,
  String source = 'comicvine',
  String publisher = '',
  int startYear = 0,
  int endYear = 0,
  int read = 0,
  DateTime? lastReadAt,
}) {
  return Arc(
    id: id,
    name: name,
    imageUrl: '',
    selfContained: null,
    total: total,
    present: present,
    source: source,
    publisher: publisher,
    startYear: startYear,
    endYear: endYear,
    read: read,
    coverUrl: '',
    lastReadAt: lastReadAt,
  );
}

void main() {
  group('arcDisplayName', () {
    test('leading quoted part becomes upper-cased kicker', () {
      final r = arcDisplayName('"Avengers" One World Under Doom');
      expect(r.kicker, 'AVENGERS');
      expect(r.title, 'One World Under Doom');
    });

    test('no leading quoted part: kicker empty, title is trimmed name', () {
      final r = arcDisplayName('Doomwar');
      expect(r.kicker, '');
      expect(r.title, 'Doomwar');
    });

    test('quoted-only name: kicker empty, title is quoted text as written',
        () {
      final r = arcDisplayName('"Batman"');
      expect(r.kicker, '');
      expect(r.title, 'Batman');
    });

    test('never returns a blank title for a non-blank name', () {
      final r = arcDisplayName('""');
      expect(r.title, isNotEmpty);
    });
  });

  group('arcYears', () {
    test('both zero is empty', () {
      expect(arcYears(0, 0), '');
    });

    test('start zero is empty regardless of end', () {
      expect(arcYears(0, 2020), '');
    });

    test('equal years', () {
      expect(arcYears(2010, 2010), '2010');
    });

    test('same century abbreviates the end year', () {
      expect(arcYears(2025, 2026), '2025–26');
    });

    test('different century spells out the end year in full', () {
      expect(arcYears(1999, 2001), '1999–2001');
    });
  });

  group('arcCountLabel', () {
    test('Mylar arc (total > 0) uses present-of-total phrasing', () {
      final a = _arc(id: 'a1', name: 'X', total: 58, present: 0);
      expect(arcCountLabel(a), '0 OF 58 PRESENT');
    });

    test('non-Mylar arc (total == 0) uses issue count phrasing', () {
      final a = _arc(id: 'a2', name: 'X', total: 0, present: 12);
      expect(arcCountLabel(a), '12 ISSUES');
    });

    test('appends years with a dot separator when years are known', () {
      final a = _arc(
        id: 'a3',
        name: 'X',
        total: 0,
        present: 5,
        startYear: 2025,
        endYear: 2026,
      );
      expect(arcCountLabel(a), '5 ISSUES · 2025–26');
    });

    test('startYear 0 / endYear 0 omits the years suffix entirely', () {
      final a = _arc(
        id: 'a4',
        name: 'X',
        total: 0,
        present: 7,
        startYear: 0,
        endYear: 0,
      );
      expect(arcCountLabel(a), '7 ISSUES');
      expect(arcCountLabel(a).contains('–'), false);
    });
  });

  group('buildArcShelves', () {
    test('inProgress holds 0 < read < present, sorted by lastReadAt desc',
        () {
      final older = _arc(
        id: 'ip1',
        name: 'Older',
        present: 10,
        read: 3,
        lastReadAt: DateTime(2026, 1, 1),
      );
      final newer = _arc(
        id: 'ip2',
        name: 'Newer',
        present: 10,
        read: 5,
        lastReadAt: DateTime(2026, 6, 1),
      );
      final notStarted =
          _arc(id: 'ip3', name: 'NotStarted', present: 10, read: 0);
      final fullyRead = _arc(id: 'ip4', name: 'FullyRead', present: 10, read: 10);

      final result =
          buildArcShelves([older, newer, notStarted, fullyRead]);

      expect(result.inProgress.map((a) => a.id).toList(), ['ip2', 'ip1']);
    });

    test('featured are the two biggest by present, by name on ties', () {
      final big = _arc(id: 'f1', name: 'Big', present: 50);
      final bigger = _arc(id: 'f2', name: 'Bigger', present: 60);
      final tieA = _arc(id: 'f3', name: 'Alpha', present: 40);
      final tieB = _arc(id: 'f4', name: 'Beta', present: 40);
      final small = _arc(id: 'f5', name: 'Small', present: 10);

      final result = buildArcShelves([small, big, bigger, tieA, tieB]);

      expect(result.featured.map((a) => a.id).toList(), ['f2', 'f1']);
    });

    test(
        'remaining arcs group by publisher into named shelves (>=2 members); '
        'singletons and blank publisher fall into More events', () {
      // Two high-present arcs so they land in `featured`, keeping them out
      // of the publisher pool below.
      final featuredA = _arc(id: 'ft1', name: 'FeatA', publisher: 'Big', present: 100);
      final featuredB = _arc(id: 'ft2', name: 'FeatB', publisher: 'Big', present: 90);

      final marvel1 = _arc(id: 'm1', name: 'Marvel One', publisher: 'Marvel', present: 10);
      final marvel2 = _arc(id: 'm2', name: 'Marvel Two', publisher: 'Marvel', present: 8);
      final marvel3 = _arc(id: 'm3', name: 'Marvel Three', publisher: 'Marvel', present: 5);

      final dc1 = _arc(id: 'd1', name: 'DC One', publisher: 'DC', present: 7);
      final dc2 = _arc(id: 'd2', name: 'DC Two', publisher: 'DC', present: 6);

      final image1 = _arc(id: 'i1', name: 'Image One', publisher: 'Image', present: 4);
      final blank1 = _arc(id: 'b1', name: 'Blank One', publisher: '', present: 3);

      final result = buildArcShelves([
        featuredA,
        featuredB,
        marvel1,
        marvel2,
        marvel3,
        dc1,
        dc2,
        image1,
        blank1,
      ]);

      expect(result.inProgress, isEmpty);
      expect(result.featured.map((a) => a.id).toList(), ['ft1', 'ft2']);

      expect(result.shelves.map((s) => s.title).toList(),
          ['Marvel', 'DC', 'More events']);

      final marvelShelf = result.shelves[0];
      expect(marvelShelf.arcs.map((a) => a.id).toList(), ['m1', 'm2', 'm3']);

      final dcShelf = result.shelves[1];
      expect(dcShelf.arcs.map((a) => a.id).toList(), ['d1', 'd2']);

      final moreEvents = result.shelves[2];
      expect(moreEvents.arcs.map((a) => a.id).toList(), ['i1', 'b1']);
    });

    test('More events is omitted entirely when empty', () {
      final marvel1 = _arc(id: 'm1', name: 'Marvel One', publisher: 'Marvel', present: 10);
      final marvel2 = _arc(id: 'm2', name: 'Marvel Two', publisher: 'Marvel', present: 8);

      final result = buildArcShelves([marvel1, marvel2]);

      expect(result.shelves.every((s) => s.title != 'More events'), true);
    });

    test('a Mylar singleton (total 58, present 0, blank publisher) that is '
        'not featured lands in More events with 0 OF 58 PRESENT', () {
      final mylar = _arc(
        id: 'my1',
        name: 'Mylar Event',
        total: 58,
        present: 0,
        source: 'mylar',
        publisher: '',
      );
      final filler1 = _arc(id: 'x1', name: 'X1', present: 20);
      final filler2 = _arc(id: 'x2', name: 'X2', present: 19);

      final result = buildArcShelves([mylar, filler1, filler2]);

      expect(result.featured.any((a) => a.id == 'my1'), false);
      final moreEvents =
          result.shelves.firstWhere((s) => s.title == 'More events');
      expect(moreEvents.arcs.map((a) => a.id).toList(), contains('my1'));
      expect(arcCountLabel(mylar), '0 OF 58 PRESENT');
    });
  });

  group('arc detail helpers', () {
    SeriesIssue issue(String n, String status, {String? series}) => SeriesIssue(
          id: n,
          name: '$n.cbz',
          number: n,
          coverUrl: '',
          status: status,
          seriesName: series,
        );

    test('arcCurrentIndex is the first non-completed issue, -1 when all read',
        () {
      expect(arcCurrentIndex([issue('1', 'completed'), issue('2', 'unread')]), 1);
      expect(arcCurrentIndex([issue('1', 'completed')]), -1);
      expect(
          arcCurrentIndex([
            issue('1', 'completed'),
            issue('2', 'unread'),
            issue('3', 'in_progress'),
          ]),
          2,
          reason: 'an in-progress issue wins over an earlier unread one');
    });

    test('arcIssueStartPage reopens completed issues from the start', () {
      SeriesIssue at(String status, int? page) => SeriesIssue(
          id: 'x', name: 'x', coverUrl: '', status: status, currentPage: page);
      expect(arcIssueStartPage(at('completed', 24)), 0);
      expect(arcIssueStartPage(at('in_progress', 12)), 12);
      expect(arcIssueStartPage(at('unread', null)), 0);
    });

    test('arcPrimaryLabel', () {
      expect(arcPrimaryLabel([issue('1', 'unread'), issue('2', 'unread')]),
          'Start reading');
      expect(arcPrimaryLabel([issue('1', 'in_progress'), issue('2', 'unread')]),
          'Continue #1');
      expect(arcPrimaryLabel([issue('78', 'completed'), issue('79', 'unread')]),
          'Continue #79');
      expect(arcPrimaryLabel([issue('1', 'completed')]), 'Read again');
    });

    test('arcWindowStart centers the current issue and stays full', () {
      expect(arcWindowStart(67, 7), 5);
      expect(arcWindowStart(67, 0), 0);
      expect(arcWindowStart(67, -1), 0);
      expect(arcWindowStart(67, 66), 47);
      expect(arcWindowStart(10, 8), 0);
    });

    test('arcIssueHeading strips a trailing year from the series name', () {
      expect(arcIssueHeading(issue('79', 'unread', series: 'Batman (2016)')),
          'Batman #79');
      expect(arcIssueHeading(issue('3', 'unread')), '#3');
    });

    test('arcCoverDate formats YYYY-MM[-DD] as MMM YYYY', () {
      expect(arcCoverDate('2019-09-01'), 'SEP 2019');
      expect(arcCoverDate('2020-02'), 'FEB 2020');
      expect(arcCoverDate(''), '');
      expect(arcCoverDate(null), '');
    });

    test('arcMetaLine is publisher · years · count', () {
      final a = _arc(
          id: 'a', name: 'x', publisher: 'DC Comics', present: 11,
          startYear: 2019, endYear: 2020);
      expect(arcMetaLine(a), 'DC COMICS · 2019–20 · 11 ISSUES');
      expect(arcMetaLine(_arc(id: 'b', name: 'y', present: 2)), '2 ISSUES');
    });
  });
}
