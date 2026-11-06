import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:comic_reader_app/models/series.dart';
import 'package:comic_reader_app/providers/cache_providers.dart';
import 'package:comic_reader_app/providers/mirror_provider.dart';
import 'package:comic_reader_app/providers/providers.dart';
import 'package:comic_reader_app/providers/stats_provider.dart';
import 'package:comic_reader_app/services/local_session_store.dart';
import 'package:comic_reader_app/services/mirror/mirror_database.dart';

void main() {
  test('Komga: Stats come from device sessions, named from the mirror', () async {
    final dir = await Directory.systemTemp.createTemp('stats_');
    addTearDown(() => dir.delete(recursive: true));
    final store = LocalSessionStore('${dir.path}/sessions.json');
    await store.append(LocalSession(
        comicId: 'b1', seriesId: 's1', startedAt: DateTime.now(),
        pagesRead: 12, durationS: 300));
    final c = ProviderContainer(overrides: [
      isCustomSourceProvider.overrideWithValue(false),
      localSessionStoreProvider.overrideWithValue(store),
      apiClientProvider.overrideWith((_) => throw StateError('no network')),
      mirrorLibraryProvider.overrideWith((_) => Stream.value([
            MirrorSeries(
                series: Series(
                    id: 's1', name: 'Saga', folderPath: '', issueCount: 3,
                    readCount: 0, coverUrl: '/api/v1/series/s1/thumbnail',
                    createdAt: DateTime(2026), updatedAt: DateTime(2026))),
          ])),
    ]);
    addTearDown(c.dispose);
    final sub = c.listen(statsSummaryProvider, (_, _) {});
    addTearDown(sub.close);
    final st = await c.read(statsSummaryProvider.future);
    expect(st.allTime.pagesRead, 12);
    expect(st.topSeries.single.name, 'Saga');
  });
}
