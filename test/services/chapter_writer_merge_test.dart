// test/services/chapter_writer_merge_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:comic_reader_app/models/chapter.dart';
import 'package:comic_reader_app/models/chapter_candidate.dart';
import 'package:comic_reader_app/services/chapter_writer.dart';

void main() {
  test('merges by page, existing wins, sorted', () {
    final existing = [
      Chapter.create(comicId: 'c', pageNum: 10, title: 'User Title'),
    ];
    final candidates = const [
      ChapterCandidate(page: 0, title: 'Issue 1', source: 'ocr', confidence: 'high'),
      ChapterCandidate(page: 10, title: 'Detected Dup', source: 'ocr', confidence: 'low'),
      ChapterCandidate(page: 5, title: 'Issue 2', source: 'ocr', confidence: 'medium'),
    ];
    final merged = mergeDetectedChapters('c', existing, candidates);

    expect(merged.map((c) => c.pageNum), [0, 5, 10]);
    // Existing user title at page 10 is preserved over the detected dup.
    expect(merged.firstWhere((c) => c.pageNum == 10).title, 'User Title');
    expect(merged.firstWhere((c) => c.pageNum == 0).title, 'Issue 1');
  });

  test('empty inputs yield empty list', () {
    expect(mergeDetectedChapters('c', const [], const []), isEmpty);
  });
}
