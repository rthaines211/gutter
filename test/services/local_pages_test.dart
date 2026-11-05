import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:comic_reader_app/services/local_pages.dart';

void main() {
  test('finds page files by 1-based number, with or without extension', () {
    final dir = Directory.systemTemp.createTempSync('pages_');
    addTearDown(() => dir.deleteSync(recursive: true));
    for (final name in ['001', '002.jpg', '1000', 'notes.txt']) {
      File(p.join(dir.path, name)).writeAsStringSync('x');
    }
    String? name(int page) =>
        localPageFile(dir.path, page)?.path.split('/').last;
    expect(name(0), '001');
    expect(name(1), '002.jpg');
    expect(name(999), '1000');
    expect(name(2), isNull);
  });
}
