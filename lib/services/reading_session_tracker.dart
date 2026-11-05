import '../services/api_client.dart';
import '../services/sync_queue.dart';

class ReadingSessionTracker {
  DateTime? _sessionStart;
  int _sessionStartPage;
  /// Pages read before the last jump; pages read is measured from the start
  /// page, so a jump re-bases it instead of counting the pages it skipped.
  int _pagesBeforeJump = 0;
  final String comicId;
  final String Function() deriveSeriesId;

  ApiClient? client;
  SyncQueue? syncQueue;

  ReadingSessionTracker({
    required this.comicId,
    required this.deriveSeriesId,
    required int initialPage,
  }) : _sessionStartPage = initialPage {
    _sessionStart = DateTime.now();
  }

  void updateCaptures({required ApiClient client, SyncQueue? syncQueue}) {
    this.client = client;
    this.syncQueue = syncQueue;
  }

  void pause(int currentPage) {
    endSessionWithPage(currentPage);
  }

  void resume(int currentPage) {
    _sessionStart = DateTime.now();
    _sessionStartPage = currentPage;
    _pagesBeforeJump = 0;
  }

  void jumped(int from, int to) {
    _pagesBeforeJump += (from - _sessionStartPage).abs();
    _sessionStartPage = to;
  }

  void endSessionWithPage(int currentPage) {
    if (_sessionStart == null || client == null) return;
    final startedAt = _sessionStart!;
    final durationS = DateTime.now().difference(startedAt).inSeconds;
    if (durationS < 5) return;

    final pagesRead =
        _pagesBeforeJump + (currentPage - _sessionStartPage).abs();
    final seriesId = deriveSeriesId();

    client!.postReadingSession(
      comicId: comicId,
      seriesId: seriesId,
      startedAt: startedAt,
      pagesRead: pagesRead,
      durationS: durationS,
    ).catchError((_) {
      syncQueue?.enqueue({
        'type': 'session',
        'payload': {
          'comic_id': comicId,
          'series_id': seriesId,
          'started_at': startedAt.toIso8601String(),
          'pages_read': pagesRead,
          'duration_s': durationS,
        },
      });
    });

    _sessionStart = null;
  }
}
