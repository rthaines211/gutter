// test/widgets/chapter_review_sheet_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:comic_reader_app/models/chapter_candidate.dart';
import 'package:comic_reader_app/widgets/chapter_review_sheet.dart';

void main() {
  testWidgets('lists candidates and returns accepted on confirm', (tester) async {
    final cands = [
      const ChapterCandidate(page: 0, title: 'One', source: 'ocr', confidence: 'high'),
      const ChapterCandidate(page: 20, title: 'Two', source: 'ocr', confidence: 'low'),
    ];
    List<ChapterCandidate>? result;
    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (ctx) => ElevatedButton(
        onPressed: () async { result = await showChapterReviewSheet(ctx, candidates: cands); },
        child: const Text('open'),
      )),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('One'), findsOneWidget);
    expect(find.text('Two'), findsOneWidget);
    // dismiss the second candidate, then confirm
    await tester.tap(find.byKey(const Key('dismiss-20')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('review-confirm')));
    await tester.pumpAndSettle();
    expect(result, isNotNull);
    expect(result!.map((c) => c.page), [0]);
  });

  testWidgets('title-edit propagates to returned candidate', (tester) async {
    final cands = [
      const ChapterCandidate(page: 5, title: 'Original', source: 'ocr', confidence: 'high'),
    ];
    List<ChapterCandidate>? result;
    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (ctx) => ElevatedButton(
        onPressed: () async { result = await showChapterReviewSheet(ctx, candidates: cands); },
        child: const Text('open'),
      )),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // Tap the edit button for page 5
    await tester.tap(find.byKey(const Key('edit-5')));
    await tester.pumpAndSettle();

    // AlertDialog with TextField should be visible
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Edited Title');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    // Now confirm the sheet
    await tester.tap(find.byKey(const Key('review-confirm')));
    await tester.pumpAndSettle();

    expect(result, isNotNull);
    expect(result!.length, 1);
    expect(result!.single.title, 'Edited Title');
  });
}
