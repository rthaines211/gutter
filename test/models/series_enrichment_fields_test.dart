import 'package:flutter_test/flutter_test.dart';
import 'package:comic_reader_app/models/series.dart';

void main() {
  final enrichedJson = {
    'id': 'batman',
    'name': 'Batman',
    'folder_path': '/batman',
    'issue_count': 5,
    'read_count': 0,
    'cover_url': '/library/batman/cover',
    'publisher': 'DC Comics',
    'year': 2011,
    'updated_at': '2026-06-10T12:00:00Z',
    'description': 'The Dark Knight.',
    'start_year': 2011,
    'enrichment_status': 'auto',
    'creators': [
      {'name': 'Scott Snyder', 'role': 'writer'},
      {'name': 'Greg Capullo', 'role': 'penciler, cover'},
    ],
  };

  test('Series parses enrichment fields', () {
    final s = Series.fromJson(enrichedJson);
    expect(s.description, 'The Dark Knight.');
    expect(s.startYear, 2011);
    expect(s.enrichmentStatus, 'auto');
    expect(s.creators.length, 2);
    expect(s.creators.first.name, 'Scott Snyder');
    expect(s.creators.first.role, 'writer');
  });

  test('Series tolerates absent enrichment fields', () {
    final s = Series.fromJson({
      'id': 'saga',
      'name': 'Saga',
      'updated_at': '2026-06-10T12:00:00Z',
    });
    expect(s.description, isNull);
    expect(s.startYear, isNull);
    expect(s.enrichmentStatus, isNull);
    expect(s.creators, isEmpty);
  });

  test('SeriesDetail parses enrichment fields and issue extras', () {
    final d = SeriesDetail.fromJson({
      ...enrichedJson,
      'issues': [
        {
          'id': 'batman-001',
          'name': 'Batman 001',
          'number': '1',
          'cover_url': '',
          'status': 'unread',
          'title': 'Knife Trick',
          'summary': 'Gotham is mine.',
          'cover_date': '2011-11-30',
        },
        {
          'id': 'batman-002',
          'name': 'Batman 002',
          'number': '2',
          'cover_url': '',
          'status': 'unread',
        },
      ],
    });
    expect(d.description, 'The Dark Knight.');
    expect(d.creators.length, 2);
    expect(d.issues.first.title, 'Knife Trick');
    expect(d.issues.first.coverDate, '2011-11-30');
    expect(d.issues.last.title, isNull);
  });

  test('enrichedDisplayTitle combines number and title, null when absent', () {
    final withTitle = SeriesIssue.fromJson({
      'id': 'x', 'name': 'Batman 001', 'number': '1',
      'cover_url': '', 'status': 'unread', 'title': 'Knife Trick',
    });
    expect(withTitle.enrichedDisplayTitle, '#1 · Knife Trick');
    final without = SeriesIssue.fromJson({
      'id': 'y', 'name': 'Batman 002', 'number': '2',
      'cover_url': '', 'status': 'unread',
    });
    expect(without.enrichedDisplayTitle, isNull);
  });
}
