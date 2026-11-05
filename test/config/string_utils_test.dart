import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:comic_reader_app/config/string_utils.dart';

void main() {
  test('comicIdToPath decodes a Gutter comic id', () {
    final id = base64Url.encode(utf8.encode('Saga/Saga 001.cbz')).replaceAll('=', '');
    expect(comicIdToPath(id), 'Saga/Saga 001.cbz');
  });

  test('comicIdToPath leaves an opaque (Komga) id alone', () {
    // Valid base64 that decodes to text, but not a comic path.
    expect(comicIdToPath('YWJjZGVm'), 'YWJjZGVm');
    expect(comicIdToPath('0B6JRNE8N3GCV'), '0B6JRNE8N3GCV');
  });
}
