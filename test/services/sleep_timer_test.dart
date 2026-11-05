import 'package:flutter_test/flutter_test.dart';
import 'package:fake_async/fake_async.dart';
import 'package:clock/clock.dart';
import 'package:comic_reader_app/services/sleep_timer.dart';

/// Attaches recording callbacks to a fresh [SleepTimer] under test, keyed by
/// a throwaway owner object (mirrors how a reader screen would attach).
({SleepTimer timer, Object owner, List<String> events}) _build() {
  final events = <String>[];
  final timer = SleepTimer();
  final owner = Object();
  timer.attach(owner,
      onWarning: () => events.add('warned'),
      onFired: () {
        // isOn must already read false by the time onFired runs.
        expect(timer.isOn, isFalse);
        events.add('fired');
      });
  return (timer: timer, owner: owner, events: events);
}

void main() {
  group('SleepTimer', () {
    test('warns warningLead before firing, then fires once', () {
      fakeAsync((async) {
        final t = _build();
        t.timer.start(30);

        async.elapse(const Duration(minutes: 28, seconds: 59));
        expect(t.events, isEmpty);

        async.elapse(const Duration(seconds: 1));
        expect(t.events, ['warned']);

        async.elapse(const Duration(minutes: 1));
        expect(t.events, ['warned', 'fired']);
        expect(t.timer.isOn, isFalse);
      });
    });

    test('custom lead of 2 minutes warns at 28:00', () {
      fakeAsync((async) {
        final t = _build();
        t.timer.warningLead = const Duration(minutes: 2);
        t.timer.start(30);

        async.elapse(const Duration(minutes: 27, seconds: 59));
        expect(t.events, isEmpty);

        async.elapse(const Duration(seconds: 1));
        expect(t.events, ['warned']);

        t.timer.cancel();
      });
    });

    test('start(0) disarms and never fires', () {
      fakeAsync((async) {
        final t = _build();
        t.timer.start(0);
        expect(t.timer.isOn, isFalse);

        async.elapse(const Duration(hours: 2));
        expect(t.events, isEmpty);
      });
    });

    test('lead >= remaining skips the warning', () {
      fakeAsync((async) {
        final t = _build();
        t.timer.warningLead = const Duration(minutes: 2);
        t.timer.start(1);

        async.elapse(const Duration(minutes: 1));
        expect(t.events, ['fired']);
      });
    });

    test('changing warningLead after start(30) still warns at 29:00', () {
      fakeAsync((async) {
        final t = _build();
        t.timer.start(30);
        t.timer.warningLead = const Duration(minutes: 2);

        async.elapse(const Duration(minutes: 28, seconds: 59));
        expect(t.events, isEmpty,
            reason: 'the already-armed warning keeps its original 1-minute lead');

        async.elapse(const Duration(seconds: 1));
        expect(t.events, ['warned']);

        t.timer.cancel();
      });
    });

    test('extend adds to remaining; no-op when off', () {
      fakeAsync((async) {
        final t = _build();
        t.timer.extend(15);
        expect(t.timer.isOn, isFalse);
        expect(t.events, isEmpty);

        t.timer.start(1);
        t.timer.extend(1);

        async.elapse(const Duration(minutes: 1, seconds: 59));
        expect(t.events, isNot(contains('fired')),
            reason: 'extended past the original 1-minute deadline');

        async.elapse(const Duration(seconds: 1));
        expect(t.events, contains('fired'));
      });
    });

    test('resync after lapse fires immediately', () {
      final start = DateTime(2026, 1, 1, 23, 0);
      var now = start;
      fakeAsync((async) {
        withClock(Clock(() => now), () {
          final t = _build();
          t.timer.start(5);

          // Wall clock advances past the deadline without letting the
          // pending Timer run (simulates a backgrounded app).
          now = start.add(const Duration(minutes: 10));

          t.timer.resync();
          expect(t.events, ['fired']);
          expect(t.timer.isOn, isFalse);

          async.elapse(const Duration(hours: 1));
          expect(t.events, ['fired']);
        });
      });
    });

    test('detach by a stale owner keeps the new owner\'s callbacks', () {
      fakeAsync((async) {
        final timer = SleepTimer();
        final events = <String>[];
        final a = Object();
        final b = Object();
        timer.attach(a, onWarning: () => events.add('a-warned'), onFired: () => events.add('a-fired'));
        timer.attach(b, onWarning: () => events.add('b-warned'), onFired: () => events.add('b-fired'));
        timer.detach(a);

        timer.start(1);
        async.elapse(const Duration(minutes: 1));
        expect(events, ['b-fired']);
      });
    });

    test('deadline survives detach and re-attach', () {
      fakeAsync((async) {
        final timer = SleepTimer();
        final events = <String>[];
        final a = Object();
        final b = Object();
        timer.attach(a, onWarning: () {}, onFired: () {});
        timer.start(15);
        timer.detach(a);
        timer.attach(b, onWarning: () => events.add('warned'), onFired: () => events.add('fired'));

        async.elapse(const Duration(minutes: 15));
        expect(events, ['warned', 'fired']);
      });
    });

    group('nextMoonStep', () {
      test('off goes to the starting minutes', () {
        expect(nextMoonStep(remaining: null, startingMin: 15), 15);
        expect(nextMoonStep(remaining: null, startingMin: 5), 5);
      });

      test('running goes to the smallest step above the ceiled remainder', () {
        expect(
            nextMoonStep(remaining: const Duration(minutes: 4), startingMin: 15),
            5);
        expect(
            nextMoonStep(remaining: const Duration(minutes: 8), startingMin: 15),
            10);
        expect(
            nextMoonStep(
                remaining: const Duration(minutes: 14, seconds: 59),
                startingMin: 15),
            30);
        expect(
            nextMoonStep(remaining: const Duration(minutes: 20), startingMin: 15),
            30);
        expect(
            nextMoonStep(remaining: const Duration(minutes: 16), startingMin: 15),
            30);
        expect(
            nextMoonStep(remaining: const Duration(minutes: 27), startingMin: 15),
            30);
        expect(
            nextMoonStep(
                remaining:
                    const Duration(minutes: 29, milliseconds: 100),
                startingMin: 15),
            45);
        expect(
            nextMoonStep(remaining: const Duration(minutes: 44), startingMin: 15),
            45);
      });

      test('no step left turns it off', () {
        expect(
            nextMoonStep(remaining: const Duration(minutes: 50), startingMin: 15),
            0);
      });
    });

    group('snapStartingMin', () {
      final cases = <int, int>{
        0: 15,
        5: 5,
        15: 15,
        60: 45,
        20: 15,
        23: 30,
        7: 5,
        8: 10,
      };

      cases.forEach((raw, expected) {
        test('$raw -> $expected', () {
          expect(snapStartingMin(raw), expected);
        });
      });
    });
  });
}
