import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/series.dart';
import '../models/smart_filter.dart';
import 'providers.dart';

final smartFilterListProvider =
    FutureProvider.autoDispose<List<SmartFilter>>((ref) async {
  // Smart filters live on a Gutter server; Komga and Kavita have none.
  if (!ref.watch(isCustomSourceProvider)) return const [];
  final client = ref.watch(apiClientProvider);
  return client.fetchSmartFilters();
});

final smartFilterSeriesProvider =
    FutureProvider.autoDispose.family<List<Series>, int>((ref, filterId) async {
  final client = ref.watch(apiClientProvider);
  return client.fetchSmartFilterSeries(filterId);
});

class SmartFilterNotifier extends Notifier<AsyncValue<void>> {
  @override
  AsyncValue<void> build() => const AsyncValue.data(null);

  Future<int> create(SmartFilter filter) async {
    final client = ref.read(apiClientProvider);
    final id = await client.createSmartFilter(filter);
    ref.invalidate(smartFilterListProvider);
    return id;
  }

  Future<void> update(int id, SmartFilter filter) async {
    final client = ref.read(apiClientProvider);
    await client.updateSmartFilter(id, filter);
    ref.invalidate(smartFilterListProvider);
  }

  Future<void> delete(int id) async {
    final client = ref.read(apiClientProvider);
    await client.deleteSmartFilter(id);
    ref.invalidate(smartFilterListProvider);
  }
}

final smartFilterNotifierProvider =
    NotifierProvider<SmartFilterNotifier, AsyncValue<void>>(
        SmartFilterNotifier.new);
