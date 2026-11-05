import 'package:flutter_test/flutter_test.dart';
import 'package:comic_reader_app/config/reading_estimate.dart';

void main() {
  group('reading_estimate', () {
    group('kMinutesPerPage', () {
      test('constant is 0.5', () {
        expect(kMinutesPerPage, equals(0.5));
      });
    });

    group('formatMinutesLeft', () {
      test('zero pages remaining returns empty string', () {
        expect(formatMinutesLeft(0), equals(''));
      });

      test('small remainder (6 pages) formats as minutes', () {
        // 6 pages * 0.5 min/page = 3 min
        expect(formatMinutesLeft(6), equals('3 min left'));
      });

      test('medium remainder (20 pages) formats as minutes', () {
        // 20 pages * 0.5 min/page = 10 min
        expect(formatMinutesLeft(20), equals('10 min left'));
      });

      test('ceiling rounds up partial minutes', () {
        // 1 page * 0.5 min/page = 0.5 min, ceil = 1
        expect(formatMinutesLeft(1), equals('1 min left'));
      });

      test('large remainder (288 pages) formats as hours with 1 decimal', () {
        // 288 pages * 0.5 min/page = 144 min > 120, so hours format = 2.4h
        expect(formatMinutesLeft(288), equals('2.4h'));
      });

      test('very large remainder (1440 pages) formats as hours', () {
        // 1440 pages * 0.5 min/page = 720 min = 12.0h
        expect(formatMinutesLeft(1440), equals('12.0h'));
      });

      test('72-issue unread series (1728 pages) formats as hours', () {
        // 1728 pages * 0.5 min/page = 864 min = 14.4h (design spec example)
        expect(formatMinutesLeft(1728), equals('14.4h'));
      });

      test('just at threshold (240 pages = 120 min) formats as minutes', () {
        // 240 pages * 0.5 min/page = 120 min, not > 120, stays as minutes
        expect(formatMinutesLeft(240), equals('120 min left'));
      });

      test('just below threshold (239 pages) formats as minutes', () {
        // 239 pages * 0.5 min/page = 119.5 min, ceil = 120
        expect(formatMinutesLeft(239), equals('120 min left'));
      });

      test('just above threshold (241 pages) formats as hours', () {
        // 241 pages * 0.5 min/page = 120.5 min > 120, so hours = 2.008..h, rounds to 2.0h
        expect(formatMinutesLeft(241), equals('2.0h'));
      });
    });
  });
}
