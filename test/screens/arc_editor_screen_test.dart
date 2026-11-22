import 'package:comic_reader_app/models/sync_response.dart';
import 'package:comic_reader_app/providers/mirror_provider.dart';
import 'package:comic_reader_app/providers/user_arc_provider.dart';
import 'package:comic_reader_app/screens/arc_editor_screen.dart';
import 'package:comic_reader_app/services/mirror/mirror_database.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeActions extends UserArcActions {
  final saves = <(String, String, List<String>)>[];
  _FakeActions() : super(outbox: null, syncEngine: null);
  @override
  Future<void> save(String id, String name, List<String> issueIds) async =>
      saves.add((id, name, issueIds));
}

Map<String, dynamic> _series(String id, String name, List<String> numbers) => {
      'id': id, 'name': name, 'folder_path': '/p/$id', 'updated_at': '',
      'issues': [
        for (final n in numbers)
          {'id': '$id-$n', 'name': '$name $n', 'number': n, 'status': 'unread'}
      ],
    };

void main() {
  testWidgets('paste a list, then Save sends the issues in pasted order',
      (t) async {
    final db = MirrorDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await t.runAsync(() => db.applySync(SyncResponse(
          serverTime: 0,
          series: [
            _series('end', 'Ultimate Endgame (2026)', ['1', '2']),
            _series('ult', 'Ultimates (2024)', ['19']),
          ],
          progress: const [],
          seriesIds: const ['end', 'ult'],
          progressIds: const [],
        )));
    final actions = _FakeActions();
    await t.pumpWidget(ProviderScope(
      overrides: [
        mirrorDbProvider.overrideWithValue(db),
        userArcActionsProvider.overrideWithValue(actions),
      ],
      child: const MaterialApp(home: ArcEditorScreen()),
    ));

    await t.enterText(find.widgetWithText(TextField, 'Name'), 'Endgame');
    await t.tap(find.text('Paste list'));
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField).last,
        '- [ ] 1. Ultimate Endgame #1\n- [ ] 2. Ultimates #19\n3. Ultimate Endgame #2\nNope #9');
    await t.tap(find.text('Add'));
    // Matching reads the mirror: real async work.
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await t.pumpAndSettle();

    expect(find.text('1. Ultimate Endgame (2026) #1'), findsOneWidget);
    expect(find.textContaining('Not in your library: Nope #9'), findsOneWidget);

    await t.tap(find.text('Save'));
    await t.pumpAndSettle();
    expect(actions.saves.single.$2, 'Endgame');
    expect(actions.saves.single.$3, ['end-1', 'ult-19', 'end-2']);
    expect(actions.saves.single.$1, startsWith('u_'));
  });
}
