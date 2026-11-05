import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The late window ends at this minute of the day (4:00 AM).
const kBedtimeEndMin = 4 * 60;

/// How long "Later" pushes the reminder back.
const kBedtimeSnooze = Duration(minutes: 30);

/// A night runs until [kBedtimeEndMin], so 1 AM belongs to the evening
/// before. Keyed by that evening's date.
String bedtimeNightKey(DateTime now) {
  final d = now.subtract(const Duration(minutes: kBedtimeEndMin));
  return '${d.year}-${d.month}-${d.day}';
}

/// Inside the window from [startMin] (minute of day) to 4 AM.
bool inBedtimeWindow(DateTime now, int startMin) {
  final m = now.hour * 60 + now.minute;
  return startMin >= kBedtimeEndMin
      ? m >= startMin || m < kBedtimeEndMin
      : m >= startMin && m < kBedtimeEndMin;
}

class BedtimeReminder {
  const BedtimeReminder({this.on = true, this.startMin = 21 * 60});
  final bool on;
  final int startMin;
}

/// Bedtime reminder settings. Device-local (SharedPreferences), like the
/// sleep Shortcut toggle.
class BedtimeReminderNotifier extends AsyncNotifier<BedtimeReminder> {
  static const _onKey = 'bedtime_reminder_on';
  static const _startKey = 'bedtime_reminder_start_min';
  static const _shownKey = 'bedtime_reminder_shown_night';
  static const _snoozeKey = 'bedtime_reminder_snooze_until';

  @override
  Future<BedtimeReminder> build() async {
    final p = await SharedPreferences.getInstance();
    return BedtimeReminder(
      on: p.getBool(_onKey) ?? true,
      startMin: p.getInt(_startKey) ?? 21 * 60,
    );
  }

  Future<void> setOn(bool on) async {
    state = AsyncData(BedtimeReminder(on: on, startMin: _current.startMin));
    await (await SharedPreferences.getInstance()).setBool(_onKey, on);
  }

  Future<void> setStart(int startMin) async {
    state = AsyncData(BedtimeReminder(on: _current.on, startMin: startMin));
    await (await SharedPreferences.getInstance()).setInt(_startKey, startMin);
  }

  BedtimeReminder get _current => state.value ?? const BedtimeReminder();

  /// True at most once a night, plus once per elapsed snooze, inside the
  /// window, when on. Claims the night (and clears the snooze) as it
  /// answers true.
  Future<bool> claim(DateTime now) async {
    final r = await future;
    if (!r.on || !inBedtimeWindow(now, r.startMin)) return false;
    final p = await SharedPreferences.getInstance();
    final night = bedtimeNightKey(now);
    final until = await snoozedUntil();
    // A snooze from an earlier night (say 3:50 AM) is stale; drop it.
    if (until != null &&
        bedtimeNightKey(until.subtract(kBedtimeSnooze)) != night) {
      await p.remove(_snoozeKey);
    } else if (until != null) {
      if (now.isBefore(until)) return false;
      await p.remove(_snoozeKey);
      return true;
    }
    if (p.getString(_shownKey) == night) return false;
    await p.setString(_shownKey, night);
    return true;
  }

  /// Ask again [kBedtimeSnooze] from [now].
  Future<void> snooze(DateTime now) async {
    await (await SharedPreferences.getInstance())
        .setInt(_snoozeKey, now.add(kBedtimeSnooze).millisecondsSinceEpoch);
  }

  /// When a pending snooze is due, or null.
  Future<DateTime?> snoozedUntil() async {
    final ms = (await SharedPreferences.getInstance()).getInt(_snoozeKey);
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }
}

final bedtimeReminderProvider =
    AsyncNotifierProvider<BedtimeReminderNotifier, BedtimeReminder>(
        BedtimeReminderNotifier.new);
