// test/widgets/rename_templates_screen_test.dart
//
// I4 coverage: empty-field validation blocks save and shows inline error.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:comic_reader_app/providers/rename_templates_provider.dart';
import 'package:comic_reader_app/screens/rename_templates_screen.dart';
import 'package:comic_reader_app/widgets/metadata_edit_sheet.dart'
    show kIssueFormats;

// ---------------------------------------------------------------------------
// Fake notifier — returns seeded data, save() is a no-op.
// ---------------------------------------------------------------------------

class _FakeNotifier extends RenameTemplatesNotifier {
  final Map<String, String> initial;
  _FakeNotifier(this.initial);

  @override
  Future<Map<String, String>> build() async => initial;

  @override
  Future<void> save(Map<String, String> templates) async {
    state = AsyncData(templates);
  }
}

Map<String, String> _allFilled() => {
      for (final key in [...kIssueFormats, 'default'])
        key: '{series} #{number:03}',
    };

// ---------------------------------------------------------------------------
// Pump helper
// ---------------------------------------------------------------------------

Future<void> pumpScreen(
  WidgetTester tester, {
  Map<String, String>? templates,
}) async {
  final filled = templates ?? _allFilled();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        renameTemplatesProvider
            .overrideWith(() => _FakeNotifier(filled)),
      ],
      child: const MaterialApp(home: RenameTemplatesScreen()),
    ),
  );
  // Let the async provider resolve and the screen seed its controllers.
  await tester.pumpAndSettle();
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  testWidgets('I4: all fields filled — Save proceeds (no inline errors)',
      (tester) async {
    await pumpScreen(tester);

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    // No error text rendered
    expect(find.text('Template cannot be empty'), findsNothing);
    // SnackBar confirms save
    expect(find.text('Rename templates saved'), findsOneWidget);
  });

  testWidgets('I4: clearing one field shows inline error and blocks save',
      (tester) async {
    await pumpScreen(tester);

    // Clear the very first template field
    final firstField = find.byType(TextField).first;
    await tester.enterText(firstField, '');
    await tester.pump();

    // Tap Save — should be blocked
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    // Inline error must appear
    expect(find.text('Template cannot be empty'), findsWidgets);

    // 'Rename templates saved' snack bar must NOT appear
    expect(find.text('Rename templates saved'), findsNothing);
  });

  testWidgets('I4: error clears as soon as user starts typing', (tester) async {
    await pumpScreen(tester);

    // Clear first field and trigger validation
    final firstField = find.byType(TextField).first;
    await tester.enterText(firstField, '');
    await tester.pump();

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.text('Template cannot be empty'), findsWidgets);

    // Start typing — error should clear
    await tester.enterText(firstField, '{series}');
    await tester.pump();

    expect(find.text('Template cannot be empty'), findsNothing);
  });
}
