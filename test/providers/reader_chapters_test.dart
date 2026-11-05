import 'package:flutter_test/flutter_test.dart';
import 'package:comic_reader_app/models/chapter.dart';

// Mirrors the dedupe + default-title rules in ReaderNotifier.addChapter,
// kept in lockstep with that method.
List<Chapter> applyAdd(List<Chapter> existing, String comicId, int pageNum, String title) {
  final resolved = title.trim().isEmpty ? 'Chapter ${existing.length + 1}' : title.trim();
  final next = existing.where((c) => c.pageNum != pageNum).toList()
    ..add(Chapter.create(comicId: comicId, pageNum: pageNum, title: resolved));
  next.sort((a, b) => a.pageNum.compareTo(b.pageNum));
  return next;
}

void main() {
  test('add dedupes by page and keeps sorted', () {
    var list = applyAdd(const [], 'c', 5, 'Five');
    list = applyAdd(list, 'c', 1, 'One');
    list = applyAdd(list, 'c', 5, 'Five again'); // replaces page 5
    expect(list.map((c) => c.pageNum), [1, 5]);
    expect(list.firstWhere((c) => c.pageNum == 5).title, 'Five again');
  });

  test('blank title defaults to Chapter N', () {
    final list = applyAdd(const [], 'c', 0, '   ');
    expect(list.single.title, 'Chapter 1');
  });
}
