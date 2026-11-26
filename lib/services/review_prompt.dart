import 'package:in_app_review/in_app_review.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/flavor.dart';

/// Asks once for an App Store rating, after the reader has finished
/// [threshold] issues. Apple's dialog caps itself at 3 a year and may not
/// show at all, so asking once is enough.
class ReviewPrompt {
  // 3, not 10: few new readers finish 10 issues in their first weeks.
  static const threshold = 3;
  static const _countKey = 'review_finished_count';
  static const _askedKey = 'review_prompt_asked';
  static const _finishedIdsKey = 'review_finished_ids';

  /// Counts [issueKey] (source id + comic id) as finished, once: a re-read
  /// doesn't count again. Counts from older versions are kept.
  // ponytail: one prefs entry per finished issue; fine for thousands.
  static Future<void> recordFinish(String issueKey) async {
    final p = await SharedPreferences.getInstance();
    final ids = p.getStringList(_finishedIdsKey) ?? const <String>[];
    if (ids.contains(issueKey)) return;
    await p.setStringList(_finishedIdsKey, [...ids, issueKey]);
    await p.setInt(_countKey, (p.getInt(_countKey) ?? 0) + 1);
  }

  static int finishedCount(SharedPreferences p) => p.getInt(_countKey) ?? 0;

  /// Shows the rating dialog when it's due. Call it when the reader leaves a
  /// finished issue (Close, Back to series or Next issue), never mid-page. True when it asked. [request] is for tests.
  static Future<bool> maybeAsk({Future<void> Function()? request}) async {
    if (!isStore) return false; // the personal build isn't on the App Store
    final p = await SharedPreferences.getInstance();
    if (p.getBool(_askedKey) ?? false) return false;
    if (finishedCount(p) < threshold) return false;
    await p.setBool(_askedKey, true);
    if (request != null) {
      await request();
      return true;
    }
    final review = InAppReview.instance;
    if (await review.isAvailable()) await review.requestReview();
    return true;
  }
}
