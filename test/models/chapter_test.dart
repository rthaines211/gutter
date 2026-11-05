import 'package:flutter_test/flutter_test.dart';
import 'package:comic_reader_app/models/chapter.dart';

void main() {
  test('create derives deterministic id', () {
    final c = Chapter.create(comicId: 'abc', pageNum: 3, title: 'Intro');
    expect(c.id, 'abc:3');
    expect(c.pageNum, 3);
    expect(c.title, 'Intro');
  });

  test('json round-trip', () {
    final c = Chapter.create(comicId: 'abc', pageNum: 3, title: 'Intro');
    final back = Chapter.fromJson(c.toJson());
    expect(back.comicId, 'abc');
    expect(back.pageNum, 3);
    expect(back.title, 'Intro');
    expect(back.id, 'abc:3');
  });

  test('fromJson tolerates missing created_at', () {
    final c = Chapter.fromJson({'comic_id': 'x', 'page_num': 1, 'title': 'T'});
    expect(c.id, 'x:1');
    expect(c.title, 'T');
  });
}
