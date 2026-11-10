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

  /// Counts one finished issue.
  static Future<void> recordFinish() async {
    final p = await SharedPreferences.getInstance();
    await p.setInt(_countKey, (p.getInt(_countKey) ?? 0) + 1);
  }

  /// Shows the rating dialog when it's due. Call it when the reader leaves a
  /// finished issue, never mid-page. [request] is for tests.
  static Future<void> maybeAsk({Future<void> Function()? request}) async {
    if (!isStore) return; // the personal build isn't on the App Store
    final p = await SharedPreferences.getInstance();
    if (p.getBool(_askedKey) ?? false) return;
    if ((p.getInt(_countKey) ?? 0) < threshold) return;
    await p.setBool(_askedKey, true);
    if (request != null) return request();
    final review = InAppReview.instance;
    if (await review.isAvailable()) await review.requestReview();
  }
}
