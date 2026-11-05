import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/facet_value.dart';
import '../services/mirror/library_view.dart';
import 'library_provider.dart';
import 'mirror_provider.dart';

final facetProvider = FutureProvider.autoDispose
    .family<List<FacetValue>, String>((ref, facet) async {
  final all = await ref.watch(mirrorLibraryProvider.future);
  final filter = ref.watch(libraryFilterProvider);
  return computeFacets(all, facet, filter);
});
