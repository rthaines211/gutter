import 'package:comic_reader_app/models/server_source.dart';
import 'package:comic_reader_app/providers/mirror_provider.dart';
import 'package:comic_reader_app/providers/source_provider.dart';
import 'package:comic_reader_app/models/sync_response.dart';
import 'package:comic_reader_app/services/mirror/mirror_database.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the mirror maps each issue to its synced cover path', () async {
    final db = MirrorDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await db.applySync(SyncResponse(
      serverTime: 1,
      series: const [
        {
          'id': 's1',
          'name': 'Saga',
          'updated_at': '2026-01-01T00:00:00Z',
          'issues': [
            {'id': 'b1', 'name': 'Saga 1', 'cover_url': '/api/v1/books/b1/thumbnail?v=2'},
            {'id': 'b2', 'name': 'Saga 2'},
          ],
        },
      ],
      progress: const [],
      seriesIds: const ['s1'],
      progressIds: const [],
    ));
    expect(await db.watchIssueCoverPaths().first, {'b1': '/api/v1/books/b1/thumbnail?v=2'});
  });

  test('issue covers use the versioned synced path, else the id-built URL', () async {
    const source = ServerSource(
        id: 'k', name: 'Komga', type: SourceType.komga,
        baseUrl: 'https://k.example', authType: AuthType.none);
    final c = ProviderContainer(overrides: [
      activeSourceProvider.overrideWithValue(source),
      issueCoverPathsProvider.overrideWith(
          (ref) => Stream.value({'b1': '/api/v1/books/b1/thumbnail?v=2'})),
    ]);
    addTearDown(c.dispose);
    final sub = c.listen(issueCoverPathsProvider, (_, _) {});
    addTearDown(sub.close);
    await c.read(issueCoverPathsProvider.future);

    expect(c.read(issueCoverUrlProvider('b1')),
        'https://k.example/api/v1/books/b1/thumbnail?v=2');
    expect(c.read(issueCoverUrlProvider('b9')),
        'https://k.example/api/v1/books/b9/thumbnail');
  });
}
