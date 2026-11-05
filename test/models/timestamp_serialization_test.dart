// Regression: the Go backend decodes created_at as time.Time (RFC3339, which
// requires a timezone). A local toIso8601String() omits the offset and 400s the
// whole PUT /reading payload, so chapter/bookmark writes must serialize as UTC.
import 'package:flutter_test/flutter_test.dart';
import 'package:comic_reader_app/models/chapter.dart';
import 'package:comic_reader_app/models/bookmark.dart';

void main() {
  test('Chapter.toJson created_at is UTC (Z-suffixed, RFC3339)', () {
    final json = Chapter.create(comicId: 'c', pageNum: 3, title: 'T').toJson();
    final createdAt = json['created_at'] as String;
    expect(createdAt.endsWith('Z'), isTrue, reason: 'must carry a UTC timezone');
    // Go's time.RFC3339 parser is satisfied by a Z-suffixed instant.
    expect(DateTime.parse(createdAt).isUtc, isTrue);
  });

  test('Bookmark.toJson created_at is UTC (Z-suffixed, RFC3339)', () {
    final json = Bookmark(
      id: 'b',
      comicId: 'c',
      pageNum: 3,
      createdAt: DateTime(2026, 6, 23, 20, 30), // local, no tz
    ).toJson();
    final createdAt = json['created_at'] as String;
    expect(createdAt.endsWith('Z'), isTrue, reason: 'must carry a UTC timezone');
    expect(DateTime.parse(createdAt).isUtc, isTrue);
  });
}
