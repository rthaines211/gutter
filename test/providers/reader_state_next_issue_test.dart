// test/providers/reader_state_next_issue_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:comic_reader_app/models/series.dart';
import 'package:comic_reader_app/providers/reader_provider.dart';

SeriesIssue _issue(String id) => SeriesIssue(
      id: id,
      name: id,
      number: null,
      coverUrl: '',
      status: 'unread',
      currentPage: null,
      totalPages: null,
    );

void main() {
  group('ReaderState.nextIssue', () {
    test('returns the next issue when not at the last index', () {
      final issues = [_issue('a'), _issue('b'), _issue('c')];
      final state = ReaderState(
        comicId: 'b',
        comicPath: 'b',
        seriesIssues: issues,
        currentIssueIndex: 1,
      );
      expect(state.nextIssue?.id, 'c');
    });

    test('returns null at the last index', () {
      final issues = [_issue('a'), _issue('b')];
      final state = ReaderState(
        comicId: 'b',
        comicPath: 'b',
        seriesIssues: issues,
        currentIssueIndex: 1,
      );
      expect(state.nextIssue, isNull);
    });

    test('returns null when seriesIssues is null', () {
      final state = ReaderState(
        comicId: 'x',
        comicPath: 'x',
        seriesIssues: null,
        currentIssueIndex: 0,
      );
      expect(state.nextIssue, isNull);
    });

    test('returns null when currentIssueIndex is null', () {
      final issues = [_issue('a')];
      final state = ReaderState(
        comicId: 'a',
        comicPath: 'a',
        seriesIssues: issues,
        currentIssueIndex: null,
      );
      expect(state.nextIssue, isNull);
    });
  });
}
