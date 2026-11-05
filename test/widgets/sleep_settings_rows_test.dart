import 'package:comic_reader_app/models/reader_settings.dart';
import 'package:comic_reader_app/widgets/reader_settings_form.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('sleep rows: timer, warning, Shortcut, bedtime', (t) async {
    SharedPreferences.setMockInitialValues({});
    ReaderSettings? changed;
    await t.pumpWidget(ProviderScope(
      child: MaterialApp(
        home: Scaffold(
          body: ListView(
            children: sleepSettingsRows(
              settings: const ReaderSettings(),
              onChanged: (s) => changed = s,
              accent: Colors.blue,
            ),
          ),
        ),
      ),
    ));
    await t.pump();
    for (final label in ['Starting time', '5m', '45m', 'Warning', '2m',
        'Run Shortcut at sleep', 'Bedtime reminder']) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
    expect(find.text('Keep screen on'), findsNothing);
    await t.tap(find.text('45m'));
    expect(changed?.sleepTimerMin, 45);
  });
}
