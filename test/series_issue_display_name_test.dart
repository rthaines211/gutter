import 'package:flutter_test/flutter_test.dart';
import 'package:comic_reader_app/models/series.dart';

SeriesIssue _issue({String? number, required String name}) =>
    SeriesIssue.fromJson({'id': 'x', 'name': name, 'number': number});

void main() {
  test('numbered issue shows #N', () {
    expect(_issue(number: '3', name: 'Foo 003.cbz').displayName, '#3');
  });
  test('un-numbered issue drops the archive extension', () {
    expect(_issue(name: 'Justice League (2018).cbz').displayName, 'Justice League (2018)');
    expect(_issue(name: 'Saga Vol 1.CBR').displayName, 'Saga Vol 1');
  });
}
