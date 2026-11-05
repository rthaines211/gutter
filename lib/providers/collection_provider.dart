import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/collection.dart';
import 'providers.dart';

final collectionsProvider =
    AsyncNotifierProvider<CollectionsNotifier, List<Collection>>(
  CollectionsNotifier.new,
);

class CollectionsNotifier extends AsyncNotifier<List<Collection>> {
  @override
  Future<List<Collection>> build() async {
    // Collections are a Gutter-server feature.
    if (!ref.watch(isCustomSourceProvider)) return const [];
    final client = ref.watch(apiClientProvider);
    return client.fetchCollections();
  }

  Future<void> create({
    required String name,
    String icon = 'bookmark',
    String color = '#FFB74D',
  }) async {
    final client = ref.read(apiClientProvider);
    await client.createCollection(name: name, icon: icon, color: color);
    ref.invalidateSelf();
  }

  Future<void> edit({
    required int id,
    required String name,
    required String icon,
    required String color,
  }) async {
    final client = ref.read(apiClientProvider);
    await client.updateCollection(id: id, name: name, icon: icon, color: color);
    ref.invalidateSelf();
  }

  Future<void> delete(int id) async {
    final client = ref.read(apiClientProvider);
    await client.deleteCollection(id);
    ref.invalidateSelf();
  }

  Future<void> addSeries(int collectionId, String seriesId) async {
    final client = ref.read(apiClientProvider);
    await client.addSeriesToCollection(collectionId, seriesId);
    ref.invalidateSelf();
  }

  Future<void> removeSeries(int collectionId, String seriesId) async {
    final client = ref.read(apiClientProvider);
    await client.removeSeriesFromCollection(collectionId, seriesId);
    ref.invalidateSelf();
  }
}

/// Tracks the currently active collection filter. Null means "All" (no collection filter).
class ActiveCollectionNotifier extends Notifier<int?> {
  @override
  int? build() => null;

  void select(int? id) => state = id;
}

final activeCollectionProvider =
    NotifierProvider<ActiveCollectionNotifier, int?>(
  ActiveCollectionNotifier.new,
);
