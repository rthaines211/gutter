import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/arc.dart';
import '../models/series.dart';
import 'mirror_provider.dart';

/// Live stream of all synced story arcs (read-only, offline-capable).
final arcsProvider = StreamProvider<List<Arc>>((ref) {
  return ref.watch(mirrorDbProvider).watchArcs();
});

/// Live stream of one arc's issues in reading order.
final arcIssuesProvider =
    StreamProvider.family<List<SeriesIssue>, String>((ref, arcId) {
  return ref.watch(mirrorDbProvider).watchArcIssues(arcId);
});
