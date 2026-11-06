import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:comic_reader_app/models/series.dart';
import 'package:comic_reader_app/providers/collection_provider.dart';
import 'package:comic_reader_app/providers/providers.dart';
import 'package:comic_reader_app/widgets/series_action_sheet.dart';

const _issue = SeriesIssue(id: 'b1', name: 'Saga 001', coverUrl: '', status: 'unread');

Future<void> openIssueSheet(WidgetTester t, {required bool gutterServer}) async {
  await t.pumpWidget(ProviderScope(
    overrides: [isCustomSourceProvider.overrideWithValue(gutterServer)],
    child: MaterialApp(
      home: Consumer(
        builder: (context, ref, _) => TextButton(
          onPressed: () => showIssueActionSheet(
              context: context, ref: ref, issue: _issue, seriesId: 's1',
              accent: Colors.orange),
          child: const Text('open'),
        ),
      ),
    ),
  ));
  await t.tap(find.text('open'));
  await t.pumpAndSettle();
}

void main() {
  testWidgets('Komga: issue sheet has no Gutter-server actions', (t) async {
    await openIssueSheet(t, gutterServer: false);
    expect(find.text('Mark as Read'), findsOneWidget);
    expect(find.text('Rename File'), findsNothing);
    expect(find.text('Edit Metadata'), findsNothing);
  });

  testWidgets('Gutter server: issue sheet keeps them', (t) async {
    await openIssueSheet(t, gutterServer: true);
    expect(find.text('Rename File'), findsOneWidget);
    expect(find.text('Edit Metadata'), findsOneWidget);
  });

  test('Komga: no collections, and no request for them', () async {
    final c = ProviderContainer(overrides: [
      isCustomSourceProvider.overrideWithValue(false),
      apiClientProvider.overrideWith((_) => throw StateError('no network')),
    ]);
    addTearDown(c.dispose);
    expect(await c.read(collectionsProvider.future), isEmpty);
  });
}
