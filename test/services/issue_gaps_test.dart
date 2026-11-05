import 'package:flutter_test/flutter_test.dart';
import 'package:comic_reader_app/models/series.dart';
import 'package:comic_reader_app/services/issue_gaps.dart';

SeriesIssue _i(String? n) =>
    SeriesIssue(id: 'id-$n', name: 'Issue $n', number: n, coverUrl: '', status: 'unread');

List<SeriesIssue> _run(List<String?> numbers) => [for (final n in numbers) _i(n)];

void main() {
  group('missingIssueNumbers', () {
    test('finds holes between the lowest and highest issue', () {
      expect(missingIssueNumbers(_run(['1', '2', '3', '5', '6', '8'])), [4, 7]);
    });

    test('complete run has no gaps', () {
      expect(missingIssueNumbers(_run(['1', '2', '3'])), isEmpty);
    });

    test('ignores annuals, point issues and missing numbers', () {
      expect(missingIssueNumbers(_run(['1', '1.MU', 'Annual 1', null, '3'])), [2]);
    });

    test('tolerates padded numbers', () {
      expect(missingIssueNumbers(_run(['001', ' 2 ', '004'])), [3]);
    });

    test('a sparse subset is not treated as gaps', () {
      // 3 present, 97 missing: a pick of issues, not a run with holes.
      expect(missingIssueNumbers(_run(['1', '50', '100'])), isEmpty);
    });

    test('legacy numbering beyond maxSpan is skipped', () {
      expect(missingIssueNumbers(_run(['1', '2', '500'])), isEmpty);
    });

    test('fewer than two numbered issues yields nothing', () {
      expect(missingIssueNumbers(_run(['7'])), isEmpty);
      expect(missingIssueNumbers(const []), isEmpty);
    });
  });

  group('withGaps', () {
    test('places each gap before the first issue numbered above it', () {
      final entries = withGaps(_run(['1', '2', '5']), [3, 4]);
      expect(
        entries.map((e) => e.isMissing ? 'gap ${e.missingNumber}' : e.issue!.number),
        ['1', '2', 'gap 3', 'gap 4', '5'],
      );
    });

    test('non-numeric issues keep their place', () {
      final entries = withGaps(_run(['1', 'Annual', '3']), [2]);
      expect(
        entries.map((e) => e.isMissing ? 'gap' : e.issue!.number),
        ['1', 'Annual', 'gap', '3'],
      );
    });

    test('no gaps passes issues straight through', () {
      expect(withGaps(_run(['1', '2']), const []).length, 2);
    });
  });
}
