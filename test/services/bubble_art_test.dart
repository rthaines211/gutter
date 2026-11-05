import 'dart:typed_data';
import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:comic_reader_app/services/bubble_art.dart';

void main() {
  // 200 x 100 page, cell 4: left half flat grey, right half fine stripes (drawn art).
  Uint8List page() {
    final rgba = Uint8List(200 * 100 * 4);
    for (var y = 0; y < 100; y++) {
      for (var x = 0; x < 200; x++) {
        final v = x < 100 ? 128 : ((x ~/ 4).isEven ? 0 : 255);
        final o = (y * 200 + x) * 4;
        rgba[o] = rgba[o + 1] = rgba[o + 2] = v;
        rgba[o + 3] = 255;
      }
    }
    return rgba;
  }

  test('flat fill is not art, detailed drawing is, balloons never are', () {
    final bits = artBits(page(), 200, 100, 4, [const Rect.fromLTWH(150, 0, 50, 40)]);
    final art = ArtMap(4, 50, 25, bits);
    expect(art.cover(const Rect.fromLTWH(0, 0, 80, 100)), 0, reason: 'flat');
    expect(art.cover(const Rect.fromLTWH(110, 50, 30, 40)), greaterThan(0), reason: 'stripes');
    expect(art.cover(const Rect.fromLTWH(152, 0, 44, 36)), 0, reason: 'under a balloon');
  });

  test('the balloon\'s own spot is not counted', () {
    final art = ArtMap(4, 50, 25, artBits(page(), 200, 100, 4, []));
    const r = Rect.fromLTWH(120, 40, 40, 40);
    expect(art.cover(r, except: r), 0);
  });
}
