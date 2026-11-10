import 'package:comic_reader_app/config/flavor.dart';
import 'package:comic_reader_app/services/review_prompt.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late int asked;
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
      await ReviewPrompt.recordFinish();
    }
    await ReviewPrompt.maybeAsk(request: request);
    expect(asked, 0);

    await ReviewPrompt.recordFinish();
    await ReviewPrompt.maybeAsk(request: request);
    expect(asked, 1);

    await ReviewPrompt.recordFinish();
    await ReviewPrompt.maybeAsk(request: request);
    expect(asked, 1);
  });

  test('never asks in the personal build', () async {
    isStore = false;
    for (var i = 0; i < ReviewPrompt.threshold; i++) {
      await ReviewPrompt.recordFinish();
    }
    await ReviewPrompt.maybeAsk(request: request);
    expect(asked, 0);
  });
}
