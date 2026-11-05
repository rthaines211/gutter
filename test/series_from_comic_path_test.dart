import 'package:comic_reader_app/screens/reader_screen.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the folder names the series', () {
    final s = seriesFromComicPath('Batman by Paul Dini (2006)/Batman by Paul Dini (fan-made v2).cbz');
    expect(s?.id, 'batman-by-paul-dini-2006');
    expect(s?.name, 'Batman by Paul Dini (2006)');
  });

  test('punctuation collapses like the server slug', () {
    expect(seriesFromComicPath('Batman: Dark Patterns (2025)/x.cbz')?.id, 'batman-dark-patterns-2025');
  });

  test('a comic at the root has no series', () {
    expect(seriesFromComicPath('loose.cbz'), isNull);
  });
}
