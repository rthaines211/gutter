import 'package:flutter_test/flutter_test.dart';
import 'package:comic_reader_app/config/sort_title.dart';

void main() {
  group('sortTitle', () {
    test('strips a leading article', () {
      expect(sortTitle('The Batman'), 'batman');
      expect(sortTitle('A Contract With God'), 'contract with god');
      expect(sortTitle('An American Tail'), 'american tail');
    });

    test('is case-insensitive about the article', () {
      expect(sortTitle('THE BATMAN'), 'batman');
      expect(sortTitle('the batman'), 'batman');
    });

    test('strips only the first article', () {
      expect(sortTitle('The A-Team'), 'a-team');
    });

    test('leaves a word that merely starts with an article alone', () {
      expect(sortTitle('Theron'), 'theron');
      expect(sortTitle('Animal Man'), 'animal man');
      expect(sortTitle('Astonishing X-Men'), 'astonishing x-men');
    });

    test('needs whitespace after the article', () {
      expect(sortTitle('The-Boys'), 'the-boys');
    });

    test('trims leading punctuation and whitespace', () {
      expect(sortTitle('  Saga'), 'saga');
      expect(sortTitle('"Nemesis"'), 'nemesis');
    });

    test('handles an empty or article-only name', () {
      expect(sortTitle(''), '');
      expect(sortTitle('The'), 'the');
      expect(sortTitle('The '), '');
    });
  });

  group('sectionKey', () {
    test('returns the first letter of the sort title, uppercased', () {
      expect(sectionKey('The Batman'), 'B');
      expect(sectionKey('saga'), 'S');
    });

    test('files digits and symbols under #', () {
      expect(sectionKey('100 Bullets'), '#');
      expect(sectionKey('30 Days of Night'), '#');
      expect(sectionKey(''), '#');
    });

    test('agrees with sortTitle ordering', () {
      // The invariant the index rail depends on: anything that sorts
      // between two members of a section must belong to that section.
      final names = ['The Astonishing', 'Avengers', 'The Batman', 'Batgirl'];
      final sorted = [...names]..sort(
          (a, b) => sortTitle(a).compareTo(sortTitle(b)));
      final keys = sorted.map(sectionKey).toList();
      final deduped = <String>[];
      for (final k in keys) {
        if (deduped.isEmpty || deduped.last != k) deduped.add(k);
      }
      // Each section appears exactly once — no interleaving.
      expect(deduped.length, deduped.toSet().length);
    });

    test('punctuation-prefixed titles file under their sortTitle letter', () {
      expect(sectionKey('"Nemesis"'), 'N');
      expect(sectionKey('(Almost) Perfect'), 'A');
      expect(sectionKey('...And Then'), 'A');
    });

    test('sectionKey always matches the first letter of sortTitle', () {
      for (final n in ['"Nemesis"', '(Almost) Perfect', '...And Then',
                       'The Wake', '100 Bullets', 'Saga', '']) {
        final s = sortTitle(n);
        final expected = s.isEmpty ? '#'
            : (RegExp(r'[a-z]').hasMatch(s[0]) ? s[0].toUpperCase() : '#');
        expect(sectionKey(n), expected, reason: 'for "$n"');
      }
    });
  });
}
