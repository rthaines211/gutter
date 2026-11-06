import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:comic_reader_app/models/download_item.dart';
import 'package:comic_reader_app/providers/download_provider.dart';
import 'package:comic_reader_app/providers/providers.dart';
import 'package:comic_reader_app/services/download_manager.dart';

DownloadItem _done(String source, String comic, String series) => DownloadItem(
    comicId: comic,
    sourceId: source,
    seriesId: series,
    seriesName: series,
    comicName: comic,
    totalBytes: 1,
    downloadedBytes: 1,
    status: DownloadStatus.completed,
    addedAt: DateTime(2026));

void main() {
  test('onDeviceProvider counts only the active source', () async {
    SharedPreferences.setMockInitialValues({'active_source_id': 'a'});
    final prefs = await SharedPreferences.getInstance();
    final c = ProviderContainer(overrides: [
      sharedPrefsProvider.overrideWithValue(prefs),
      downloadStateProvider.overrideWith((_) => Stream.value(
          DownloadManagerState(completed: [
            _done('a', 'c1', 's1'),
            _done('b', 'c2', 's1'),
          ]))),
    ]);
    addTearDown(c.dispose);
    c.listen(onDeviceProvider, (_, _) {});
    await c.read(downloadStateProvider.future);
    final onDevice = c.read(onDeviceProvider);
    expect(onDevice.comicIds, {'c1'});
    expect(onDevice.perSeries, {'s1': 1});
  });
}
