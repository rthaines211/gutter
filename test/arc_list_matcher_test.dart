import 'package:comic_reader_app/models/series.dart';
import 'package:comic_reader_app/services/arc_list_matcher.dart';
import 'package:flutter_test/flutter_test.dart';

SeriesIssue _i(String id, String series, String number) => SeriesIssue(
      id: id,
      name: '$series $number',
      number: number,
      coverUrl: '',
      status: 'unread',
      seriesId: series,
      seriesName: series,
    );

void main() {
  final library = [
    _i('two1', 'Ultimate Universe: Two Years In (2026)', '1'),
    _i('end1', 'Ultimate Endgame (2026)', '1'),
    _i('old19', 'Ultimates', '19'),
    _i('new19', 'Ultimates (2024)', '19'),
    _i('fin1', 'Ultimate Universe – Finale (2026)', '001'),
    _i('pc1', 'Pepper&Carrot', '1'),
  ];

  test('matches a pasted checklist in order', () {
    const text = '''
- [ ] 1. Ultimate Universe: Two Years In #1
- [ ] 2. Ultimate Endgame #1
- [ ] 3. Ultimates #19
- [ ] 13. Ultimate Universe: Finale #1
''';
    final m = matchArcList(text, library);
    expect(m.map((e) => e.issue?.id), ['two1', 'end1', 'new19', 'fin1']);
  });

  test('a year on the line picks that series', () {
    final m = matchArcList('Ultimates (2016) #19\nUltimates (2024) 19', [
      _i('old19', 'Ultimates (2016)', '19'),
      _i('new19', 'Ultimates (2024)', '19'),
    ]);
    expect(m.map((e) => e.issue?.id), ['old19', 'new19']);
  });

  test('unknown lines stay, unmatched; blank lines go', () {
    final m = matchArcList('\nPepper and Carrot #1\nNot A Comic #4\nhello\n', library);
    expect(m.map((e) => e.line), ['Pepper and Carrot #1', 'Not A Comic #4', 'hello']);
    expect(m.map((e) => e.issue?.id), ['pc1', null, null]);
  });

  test('falls back to the number in the file name', () {
    final m = matchArcList('Ultimate Endgame #1', [
      SeriesIssue(id: 'e1', name: 'Ultimate Endgame 1 (2026).cbz', number: '',
          coverUrl: '', status: 'unread', seriesName: 'Ultimate Endgame (2026)'),
    ]);
    expect(m.single.issue?.id, 'e1');
  });

  test('trailing year and punctuation still match', () {
    final m = matchArcList(
        'Ultimates #19 (2016)\nUltimates #19,\nUltimate Endgame 1 (2026)\nUltimate Endgame (2099) #1',
        [
          _i('old19', 'Ultimates (2016)', '19'),
          _i('new19', 'Ultimates (2024)', '19'),
          _i('end1', 'Ultimate Endgame', '1'),
        ]);
    expect(m.map((e) => e.issue?.id), ['old19', 'new19', 'end1', 'end1']);
  });
}
