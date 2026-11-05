import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:comic_reader_app/models/reading_queue.dart';
import 'package:comic_reader_app/services/api_client.dart';
import 'package:comic_reader_app/services/app_logger.dart';
import 'package:comic_reader_app/services/sync_queue.dart';
import 'package:comic_reader_app/services/sync_queue_drainer.dart';

class _FakeApi extends ApiClient {
  _FakeApi() : super(baseUrl: 'http://localhost:0', deviceId: 'test');
  final upserts = <String>[];
  final deletes = <String>[];

  @override
  Future<void> putQueue(ReadingQueue queue) async => upserts.add(queue.id);

  @override
  Future<void> deleteQueue(String id) async => deletes.add(id);
}

void main() {
  setUp(() async {
    await AppLogger.init(logDirFactory: () async => null);
  });

  tearDown(() {
    AppLogger.resetForTest();
  });

  test('drainer replays queue_upsert and queue_delete', () async {
    final dir = Directory.systemTemp.createTempSync('qdrain');
    addTearDown(() => dir.deleteSync(recursive: true));
    final queue = SyncQueue(queuePath: '${dir.path}/q.json');

    await queue.enqueue({
      'type': 'queue_upsert',
      'payload': {
        'id': 'q1',
        'name': 'Weekend',
        'icon': 'star',
        'color': '#FFD700',
        'position': 0,
        'series_ids': ['a'],
        'created_at': '2026-06-16T12:00:00Z',
        'updated_at': '2026-06-16T12:00:00Z',
      },
    });
    await queue.enqueue({
      'type': 'queue_delete',
      'payload': {'id': 'q2'},
    });

    final api = _FakeApi();
    await SyncQueueDrainer(queue: queue, client: api).drain();

    expect(api.upserts, ['q1']);
    expect(api.deletes, ['q2']);
    expect(await queue.pendingCount, 0);
  });
}
