import 'package:flutter/material.dart';
import '../models/series.dart';
import 'end_card.dart';

/// Builds an EndCard from a closure-captured set of inputs.
/// Used by PageReader/ScrollReader so the readers don't need to know
/// the EndCard's constructor surface.
WidgetBuilder buildEndCardPageBuilder({
  required String currentIssueTitle,
  required String currentSeriesName,
  required String currentCoverUrl,
  required int readCount,
  required int totalCount,
  required SeriesIssue? nextIssue,
  required VoidCallback onNext,
  required VoidCallback onBackToSeries,
  required VoidCallback onClose,
  String? offlineNote,
}) {
  return (context) => EndCard(
        currentIssueTitle: currentIssueTitle,
        currentSeriesName: currentSeriesName,
        currentCoverUrl: currentCoverUrl,
        readCount: readCount,
        totalCount: totalCount,
        nextIssue: nextIssue,
        onNext: onNext,
        onBackToSeries: onBackToSeries,
        onClose: onClose,
        offlineNote: offlineNote,
      );
}
