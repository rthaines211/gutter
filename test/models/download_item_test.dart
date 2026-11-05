import 'package:flutter_test/flutter_test.dart';
import 'package:comic_reader_app/models/download_item.dart';

void main() {
  group('DownloadItem', () {
    test('toJson and fromJson round-trip', () {
      final item = DownloadItem(
        comicId: 'abc123',
        sourceId: 'default',
        seriesId: 'batman-2016',
        seriesName: 'Batman (2016)',
        comicName: 'Batman 001',
        totalBytes: 52428800,
        downloadedBytes: 26214400,
        status: DownloadStatus.downloading,
        addedAt: DateTime.utc(2026, 4, 21, 14, 0),
      );
      final json = item.toJson();
      final restored = DownloadItem.fromJson(json);
      expect(restored.comicId, 'abc123');
      expect(restored.sourceId, 'default');
      expect(restored.seriesName, 'Batman (2016)');
      expect(restored.totalBytes, 52428800);
      expect(restored.status, DownloadStatus.downloading);
    });

    test('progress returns correct fraction', () {
      final item = DownloadItem(
        comicId: 'x', sourceId: 's', seriesId: '',
        seriesName: '', comicName: '',
        totalBytes: 100, downloadedBytes: 75,
        status: DownloadStatus.downloading,
        addedAt: DateTime.now(),
      );
      expect(item.progress, 0.75);
    });

    test('progress returns 0 when totalBytes is 0', () {
      final item = DownloadItem(
        comicId: 'x', sourceId: 's', seriesId: '',
        seriesName: '', comicName: '',
        totalBytes: 0, downloadedBytes: 0,
        status: DownloadStatus.queued,
        addedAt: DateTime.now(),
      );
      expect(item.progress, 0.0);
    });

    test('formattedSize formats megabytes', () {
      final item = DownloadItem(
        comicId: 'x', sourceId: 's', seriesId: '',
        seriesName: '', comicName: '',
        totalBytes: 52428800, downloadedBytes: 52428800,
        status: DownloadStatus.completed,
        addedAt: DateTime.now(),
      );
      expect(item.formattedSize, '50.0 MB');
    });
  });
}
