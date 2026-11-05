import 'package:flutter_test/flutter_test.dart';
import 'package:comic_reader_app/models/series.dart';

void main() {
  test('SeriesIssue parses metadata editing fields', () {
    final issue = SeriesIssue.fromJson(const {
      'id': 'abc',
      'name': 'a.cbz',
      'format': 'tpb',
      'writer': 'W',
      'penciller': 'P',
      'writeback_status': 'error',
      'writeback_error': 'disk full',
    });
    expect(issue.format, 'tpb');
    expect(issue.writer, 'W');
    expect(issue.penciller, 'P');
    expect(issue.writebackStatus, 'error');
    expect(issue.writebackError, 'disk full');
  });

  test('SeriesIssue metadata fields default to null', () {
    final issue = SeriesIssue.fromJson(const {'id': 'abc', 'name': 'a.cbz'});
    expect(issue.format, isNull);
    expect(issue.writebackStatus, isNull);
  });
}
