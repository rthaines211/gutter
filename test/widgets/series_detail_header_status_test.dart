import 'package:flutter_test/flutter_test.dart';
import 'package:comic_reader_app/models/series.dart';
import 'package:comic_reader_app/widgets/series_detail_header.dart';

SeriesDetail _detail({required int issueCount, required int readCount}) {
  return SeriesDetail(
    id: 's1',
    name: 'Test Series',
    folderPath: '/x',
    issueCount: issueCount,
    readCount: readCount,
    coverUrl: '',
    issues: const [],
  );
}

void main() {
  group('SeriesDetailHeader.statusCaption', () {
    test('all issues read returns FINISHED', () {
      final detail = _detail(issueCount: 5, readCount: 5);
      expect(SeriesDetailHeader.statusCaption(detail), 'FINISHED');
    });

    test('some issues unread returns null (no honest signal)', () {
      final detail = _detail(issueCount: 5, readCount: 2);
      expect(SeriesDetailHeader.statusCaption(detail), isNull);
    });

    test('no issues read returns null', () {
      final detail = _detail(issueCount: 5, readCount: 0);
      expect(SeriesDetailHeader.statusCaption(detail), isNull);
    });

    test('zero issue count returns null (nothing to derive)', () {
      final detail = _detail(issueCount: 0, readCount: 0);
      expect(SeriesDetailHeader.statusCaption(detail), isNull);
    });
  });
}
