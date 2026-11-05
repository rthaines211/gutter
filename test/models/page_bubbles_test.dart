import 'dart:convert';
import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:comic_reader_app/models/page_bubbles.dart';

void main() {
  final json = {
    'v': 1,
    'w': 1000,
    'h': 1500,
    'bubbles': [
      {
        'r': [10, 20, 30, 40],
        'label': 1,
      },
      {
        'r': [50, 60, 70, 80],
        'label': 2,
      },
      {
        'r': [90, 90, 10, 10],
        'label': 3,
      },
    ],
    'mask': base64Encode([1, 2, 3]),
  };

  test('parses rects, labels and mask', () {
    final pb = PageBubbles.fromJson(json);
    expect(pb.width, 1000);
    expect(pb.bubbles.first.rect, const Rect.fromLTWH(10, 20, 30, 40));
    expect(pb.labels, [1, 2, 3]);
    expect(pb.mask, [1, 2, 3]);
  });

  test('zero balloons and missing mask', () {
    final pb = PageBubbles.fromJson({'v': 1, 'w': 1, 'h': 1, 'bubbles': []});
    expect(pb.bubbles, isEmpty);
    expect(pb.mask, isNull);
    expect(PageBubbles.fromJson({'v': 1, 'w': 1, 'h': 1}).bubbles, isEmpty);
  });

  test('swapWithNext swaps, undoes, and refuses the last balloon', () {
    final pb = PageBubbles.fromJson(json);
    expect(pb.swapWithNext(0), isTrue);
    expect(pb.labels, [2, 1, 3]);
    expect(pb.swapWithNext(0), isTrue);
    expect(pb.labels, [1, 2, 3]);
    expect(pb.swapWithNext(2), isFalse);
    expect(pb.swapWithNext(-1), isFalse);
  });

  test('bubble toJson round-trips', () {
    final b = PageBubbles.fromJson(json).bubbles[1];
    expect(b.toJson(), {
      'r': [50, 60, 70, 80],
      'label': 2,
    });
  });

  test('panels parse as LTRB page rects, absent means none', () {
    final pb = PageBubbles.fromJson({
      'v': 1, 'w': 100, 'h': 150, 'bubbles': [],
      'panels': [[0, 0, 48, 150], [52, 0, 100, 150]],
    });
    expect(pb.panels, [const Rect.fromLTRB(0, 0, 48, 150), const Rect.fromLTRB(52, 0, 100, 150)]);
    expect(PageBubbles.fromJson({'v': 1, 'w': 100, 'h': 150, 'bubbles': []}).panels, isEmpty);
  });

  test('a malformed panel entry is skipped, not fatal', () {
    final pb = PageBubbles.fromJson({
      'v': 1, 'w': 100, 'h': 150,
      'bubbles': [{'r': [1, 2, 3, 4], 'label': 1}],
      'panels': [[0, 0, 48], 'junk', [52, 0, 100, 150]],
    });
    expect(pb.panels, [const Rect.fromLTRB(52, 0, 100, 150)]);
    expect(pb.bubbles, hasLength(1));
  });
}
