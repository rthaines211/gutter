import 'dart:async';
import 'dart:io';

import 'package:comic_reader_app/services/mirror/cover_syncer.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('evictCover drops the tile-size decode of a replaced cover', () async {
    final file = FileImage(File('/covers/s1.jpg'));
    final resized = ResizeImage(file, width: coverDecodeWidth);
    final key = await resized.obtainKey(ImageConfiguration.empty);
    final cache = PaintingBinding.instance.imageCache;
    cache.putIfAbsent(key, () => OneFrameImageStreamCompleter(Completer<ImageInfo>().future));
    expect(cache.containsKey(key), isTrue);

    evictCover('/covers/s1.jpg');
    await Future<void>.delayed(Duration.zero); // evict resolves the key async

    expect(cache.containsKey(key), isFalse);
  });
}
