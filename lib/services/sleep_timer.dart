import 'dart:async';
import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart';

/// Minutes offered by the moon button, in order.
const kSleepSteps = [5, 10, 15, 30, 45];

/// Starting time from a stored `sleep_timer_min`: 0 (the old "Off") maps to
/// 15; anything else snaps to the nearest step, ties going to the lower one.
int snapStartingMin(int raw) {
  if (raw == 0) return 15;
  var best = kSleepSteps.first;
  var bestDiff = (raw - best).abs();
  for (final step in kSleepSteps.skip(1)) {
    final diff = (raw - step).abs();
    if (diff < bestDiff) {
      best = step;
      bestDiff = diff;
    }
  }
  return best;
}

/// Whole minutes rounded up, as the moon pill's countdown label shows them.
int ceilMinutes(Duration d) {
  final whole = d.inMinutes;
  return d > Duration(minutes: whole) ? whole + 1 : whole;
}

/// Minutes the next moon tap arms. Off arms [startingMin]; running jumps to
/// the smallest step past the ceiled time left; past the last step turns it
/// off (0).
int nextMoonStep({required Duration? remaining, required int startingMin}) {
  if (remaining == null) return startingMin;
  final left = ceilMinutes(remaining);
  for (final step in kSleepSteps) {
    if (step > left) return step;
  }
  return 0;
}

/// App-level sleep-timer deadline: one instance for the whole app, so the
/// countdown survives swapping one reader screen for another (end card,
/// series detail round-trip). Readers attach/detach their warning and fired
/// callbacks as they come and go; the deadline itself is unaffected by that.
class SleepTimer {
  SleepTimer();

  static final SleepTimer instance = SleepTimer();

  /// How long before the deadline the warning fires. Default 1 minute.
  /// Changing this only takes effect at the next [start], [extend], or
  /// [resync] — an already-armed warning keeps the lead it was armed with.
  Duration warningLead = const Duration(seconds: 60);

  Timer? _fireTimer;
  Timer? _warnTimer;
  DateTime? _deadline;

  Object? _owner;
  VoidCallback? _onWarning;
  VoidCallback? _onFired;

  DateTime? get deadline => _deadline;

  /// Time left before the screen sleeps, or null if disarmed. Never
  /// negative — once the deadline is reached this reads zero until resync
  /// or cancel clears it.
  Duration? get remaining {
    final deadline = _deadline;
    if (deadline == null) return null;
    final left = deadline.difference(clock.now());
    return left.isNegative ? Duration.zero : left;
  }

  bool get isOn => _deadline != null;

  /// Arms (or re-arms) for [minutes] from now. 0 or less disarms.
  void start(int minutes) {
    if (minutes <= 0) {
      cancel();
      return;
    }
    _armFor(Duration(minutes: minutes));
  }

  /// Adds [minutes] to the remaining time. No-op when disarmed — extending a
  /// timer that isn't running would arm it from nowhere.
  void extend(int minutes) {
    final remaining = this.remaining;
    if (remaining == null || minutes <= 0) return;
    _armFor(remaining + Duration(minutes: minutes));
  }

  void cancel() {
    _fireTimer?.cancel();
    _warnTimer?.cancel();
    _fireTimer = null;
    _warnTimer = null;
    _deadline = null;
  }

  /// Re-checks the deadline after the app was backgrounded. Fires
  /// immediately if it lapsed while suspended (`Timer` does not run
  /// reliably while suspended), otherwise re-arms against wall-clock time.
  void resync() {
    final remaining = this.remaining;
    if (remaining == null) return;
    if (remaining == Duration.zero) {
      cancel();
      _onFired?.call();
      return;
    }
    _armFor(remaining);
  }

  void _armFor(Duration remaining) {
    _fireTimer?.cancel();
    _warnTimer?.cancel();
    final lead = warningLead;
    _deadline = clock.now().add(remaining);
    _fireTimer = Timer(remaining, () {
      // Clear state before firing so isOn reads false inside the callback.
      cancel();
      _onFired?.call();
    });
    // ponytail: durations at or under the lead skip straight to the fire
    // timer rather than warning immediately — a banner that appears already
    // expiring is noise.
    if (remaining > lead) {
      _warnTimer = Timer(remaining - lead, () => _onWarning?.call());
    }
  }

  /// Registers [owner] as the current callback target. The latest
  /// attach wins; a stale [owner] calling [detach] later does nothing.
  void attach(Object owner,
      {required VoidCallback onWarning, required VoidCallback onFired}) {
    _owner = owner;
    _onWarning = onWarning;
    _onFired = onFired;
  }

  /// Clears callbacks only if [owner] is still the current one. Does not
  /// touch the deadline — carry-over between readers relies on that.
  void detach(Object owner) {
    if (_owner != owner) return;
    _owner = null;
    _onWarning = null;
    _onFired = null;
  }
}
