import 'package:comic_reader_app/services/bedtime_reminder.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('window runs from start to 4 AM', () {
    const nine = 21 * 60;
    expect(inBedtimeWindow(DateTime(2026, 1, 1, 20, 59), nine), isFalse);
    expect(inBedtimeWindow(DateTime(2026, 1, 1, 21), nine), isTrue);
    expect(inBedtimeWindow(DateTime(2026, 1, 2, 3, 59), nine), isTrue);
    expect(inBedtimeWindow(DateTime(2026, 1, 2, 4), nine), isFalse);
    // A start after midnight.
    expect(inBedtimeWindow(DateTime(2026, 1, 2, 0, 30), 60), isFalse);
    expect(inBedtimeWindow(DateTime(2026, 1, 2, 1, 30), 60), isTrue);
  });

  test('1 AM belongs to the evening before', () {
    expect(bedtimeNightKey(DateTime(2026, 1, 2, 1)),
        bedtimeNightKey(DateTime(2026, 1, 1, 22)));
    expect(bedtimeNightKey(DateTime(2026, 1, 2, 22)),
        isNot(bedtimeNightKey(DateTime(2026, 1, 1, 22))));
  });

  test('claims once a night, only when on', () async {
    SharedPreferences.setMockInitialValues({});
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final n = c.read(bedtimeReminderProvider.notifier);
    await c.read(bedtimeReminderProvider.future);

    expect(await n.claim(DateTime(2026, 1, 1, 20)), isFalse); // too early
    expect(await n.claim(DateTime(2026, 1, 1, 22)), isTrue);
    expect(await n.claim(DateTime(2026, 1, 2, 1)), isFalse); // same night
    expect(await n.claim(DateTime(2026, 1, 2, 22)), isTrue); // next night

    await n.setOn(false);
    expect(await n.claim(DateTime(2026, 1, 3, 22)), isFalse);
  });

  test('snooze asks again after 30m, repeatably, same night only', () async {
    SharedPreferences.setMockInitialValues({});
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final n = c.read(bedtimeReminderProvider.notifier);
    await c.read(bedtimeReminderProvider.future);

    expect(await n.claim(DateTime(2026, 1, 1, 22)), isTrue);
    await n.snooze(DateTime(2026, 1, 1, 22));
    expect(await n.claim(DateTime(2026, 1, 1, 22, 29)), isFalse);
    expect(await n.claim(DateTime(2026, 1, 1, 22, 30)), isTrue);
    expect(await n.claim(DateTime(2026, 1, 1, 22, 31)), isFalse); // used up
    await n.snooze(DateTime(2026, 1, 1, 22, 31));
    expect(await n.claim(DateTime(2026, 1, 1, 23, 1)), isTrue);

    // 3:50 AM snooze is stale by the next evening: one card, not two.
    await n.snooze(DateTime(2026, 1, 2, 3, 50));
    expect(await n.claim(DateTime(2026, 1, 2, 22)), isTrue);
    expect(await n.claim(DateTime(2026, 1, 2, 22, 1)), isFalse);
  });
}
