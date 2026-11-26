import 'package:comic_reader_app/config/flavor.dart';
import 'package:comic_reader_app/services/review_prompt.dart';
import 'package:comic_reader_app/widgets/pro_sheet.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late int asked;
  var n = 0;
  Future<void> finish() => ReviewPrompt.recordFinish('s/${n++}');
  Future<void> request() async => asked++;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    asked = 0;
    isStore = true;
  });
  tearDown(() => isStore = false);

  test('asks once, only after the 3rd finished issue', () async {
    expect(ReviewPrompt.threshold, 3);
    for (var i = 0; i < ReviewPrompt.threshold - 1; i++) {
      await finish();
    }
    await ReviewPrompt.maybeAsk(request: request);
    expect(asked, 0);

    await finish();
    await ReviewPrompt.maybeAsk(request: request);
    expect(asked, 1);

    await finish();
    await ReviewPrompt.maybeAsk(request: request);
    expect(asked, 1);
  });

  test('never asks in the personal build', () async {
    isStore = false;
    for (var i = 0; i < ReviewPrompt.threshold; i++) {
      await finish();
    }
    await ReviewPrompt.maybeAsk(request: request);
    expect(asked, 0);
  });

  test('maybeAsk says whether it asked', () async {
    for (var i = 0; i < ReviewPrompt.threshold; i++) {
      await finish();
    }
    expect(await ReviewPrompt.maybeAsk(request: request), isTrue);
    expect(await ReviewPrompt.maybeAsk(request: request), isFalse);
  });

  group('Pro offer after a finished issue', () {
    test('once, from the 3rd finish, without Pro', () async {
      final p = await SharedPreferences.getInstance();
      for (var i = 0; i < ReviewPrompt.threshold - 1; i++) {
        await finish();
      }
      expect(takeFinishOffer(p, pro: false), isFalse);
      await finish();
      expect(takeFinishOffer(p, pro: false), isTrue);
      expect(takeFinishOffer(p, pro: false), isFalse);
    });

    test('never with Pro or in the personal build', () async {
      final p = await SharedPreferences.getInstance();
      for (var i = 0; i < ReviewPrompt.threshold; i++) {
        await finish();
      }
      expect(takeFinishOffer(p, pro: true), isFalse);
      isStore = false;
      expect(takeFinishOffer(p, pro: false), isFalse);
    });
  });

  test('a re-read issue counts once', () async {
    final p = await SharedPreferences.getInstance();
    for (var i = 0; i < 5; i++) {
      await ReviewPrompt.recordFinish('s/same');
    }
    expect(ReviewPrompt.finishedCount(p), 1);
    await ReviewPrompt.recordFinish('other/same'); // same id, other source
    expect(ReviewPrompt.finishedCount(p), 2);
  });

  test('keeps a count from an older version', () async {
    SharedPreferences.setMockInitialValues({'review_finished_count': 2});
    final p = await SharedPreferences.getInstance();
    await ReviewPrompt.recordFinish('s/new');
    expect(ReviewPrompt.finishedCount(p), 3);
    expect(await ReviewPrompt.maybeAsk(request: request), isTrue);
  });
}
