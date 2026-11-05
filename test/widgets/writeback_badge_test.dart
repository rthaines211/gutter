import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:comic_reader_app/widgets/issue_list_view.dart';
import 'package:comic_reader_app/models/series.dart';

SeriesIssue _makeIssue({String? writebackStatus, String? writebackError}) {
  return SeriesIssue(
    id: 'issue-1',
    name: 'Amazing Spider-Man #1.cbz',
    coverUrl: '',
    status: 'unread',
    writebackStatus: writebackStatus,
    writebackError: writebackError,
  );
}

Widget _pump(SeriesIssue issue) {
  return MaterialApp(
    home: Scaffold(
      body: WritebackBadge(issue: issue),
    ),
  );
}

void main() {
  testWidgets('WritebackBadge renders sync_problem icon for error status',
      (tester) async {
    final issue = _makeIssue(
      writebackStatus: 'error',
      writebackError: 'Permission denied writing ComicInfo.xml',
    );
    await tester.pumpWidget(_pump(issue));
    expect(find.byIcon(Icons.sync_problem), findsOneWidget);
  });

  testWidgets('WritebackBadge renders nothing for clean issue',
      (tester) async {
    final issue = _makeIssue();
    await tester.pumpWidget(_pump(issue));
    expect(find.byIcon(Icons.sync_problem), findsNothing);
    expect(find.byType(WritebackBadge), findsOneWidget);
  });

  testWidgets('WritebackBadge tap shows SnackBar with error message',
      (tester) async {
    const errorMsg = 'Permission denied writing ComicInfo.xml';
    final issue = _makeIssue(
      writebackStatus: 'error',
      writebackError: errorMsg,
    );
    await tester.pumpWidget(_pump(issue));
    await tester.tap(find.byIcon(Icons.sync_problem));
    await tester.pump(); // trigger SnackBar
    expect(find.text(errorMsg), findsOneWidget);
  });

  testWidgets('WritebackBadge tap shows fallback SnackBar when no error message',
      (tester) async {
    final issue = _makeIssue(writebackStatus: 'error');
    await tester.pumpWidget(_pump(issue));
    await tester.tap(find.byIcon(Icons.sync_problem));
    await tester.pump();
    expect(
      find.text('Metadata could not be written to the file'),
      findsOneWidget,
    );
  });
}
