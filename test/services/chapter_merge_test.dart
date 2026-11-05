import 'package:flutter_test/flutter_test.dart';
import 'package:comic_reader_app/models/chapter.dart';
import 'package:comic_reader_app/models/comic_info.dart';
import 'package:comic_reader_app/services/chapter_merge.dart';

void main() {
  test('sorted by page, both sources', () {
    final out = mergeChapters(
      comicInfo: [
        const ComicInfoChapter(page: 4, title: 'CI Two'),
        const ComicInfoChapter(page: 0, title: 'CI One'),
      ],
      user: [Chapter.create(comicId: 'c', pageNum: 2, title: 'User Mid')],
    );
    expect(out.map((c) => c.pageNum), [0, 2, 4]);
    expect(out[1].editable, isTrue);
    expect(out[0].editable, isFalse);
    expect(out[1].id, 'c:2');
  });

  test('user wins on page collision', () {
    final out = mergeChapters(
      comicInfo: [const ComicInfoChapter(page: 3, title: 'CI')],
      user: [Chapter.create(comicId: 'c', pageNum: 3, title: 'User')],
    );
    expect(out.length, 1);
    expect(out.single.title, 'User');
    expect(out.single.editable, isTrue);
  });

  test('empty inputs', () {
    expect(mergeChapters(comicInfo: const [], user: const []), isEmpty);
  });

  group('chapterTitleAt', () {
    const chapters = [
      ReaderChapter(pageNum: 0, title: 'One', editable: false),
      ReaderChapter(pageNum: 10, title: 'Two', editable: false),
    ];
    test('last chapter at or before the page', () {
      expect(chapterTitleAt(chapters, 9), 'One');
      expect(chapterTitleAt(chapters, 10), 'Two');
    });
    test('no chapters is null', () {
      expect(chapterTitleAt(const [], 3), isNull);
    });
  });
}
