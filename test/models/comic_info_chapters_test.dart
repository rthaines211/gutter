import 'package:flutter_test/flutter_test.dart';
import 'package:comic_reader_app/models/comic_info.dart';

void main() {
  test('parses chapters array', () {
    final info = ComicInfo.fromJson({
      'title': 'Collected',
      'page_count': 10,
      'chapters': [
        {'page': 0, 'title': 'One'},
        {'page': 4, 'title': 'Two'},
      ],
    });
    expect(info.chapters.length, 2);
    expect(info.chapters[0].page, 0);
    expect(info.chapters[0].title, 'One');
    expect(info.chapters[1].page, 4);
  });

  test('missing chapters -> empty', () {
    final info = ComicInfo.fromJson({'title': 'Floppy', 'page_count': 22});
    expect(info.chapters, isEmpty);
  });
}
