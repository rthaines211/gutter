import 'package:flutter_test/flutter_test.dart';
import 'package:comic_reader_app/models/sync_response.dart';

void main() {
  test('parses full payload', () {
    final resp = SyncResponse.fromJson({
      'server_time': 1700000000000,
      'series': [
        {'id': 's1', 'name': 'Batman', 'updated_at': '2026-01-01T00:00:00Z', 'issues': []}
      ],
      'progress': [
        {'comic_id': 'c1', 'current_page': 3, 'total_pages': 20, 'updated_at': '2026-01-01T00:00:00Z'}
      ],
      'series_ids': ['s1'],
      'progress_ids': ['c1'],
    });
    expect(resp.serverTime, 1700000000000);
    expect(resp.series.single['id'], 's1');
    expect(resp.progress.single['comic_id'], 'c1');
    expect(resp.seriesIds, ['s1']);
    expect(resp.progressIds, ['c1']);
  });

  test('tolerates missing fields', () {
    final resp = SyncResponse.fromJson({});
    expect(resp.serverTime, 0);
    expect(resp.series, isEmpty);
    expect(resp.seriesIds, isEmpty);
  });
}
