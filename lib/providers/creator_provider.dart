import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/creator.dart';
import '../models/creator_profile.dart';
import '../services/creator_view.dart';
import '../services/mirror/mirror_database.dart';
import 'connectivity_provider.dart';
import 'mirror_provider.dart';
import 'providers.dart';

/// Key for [creatorProfileProvider]: an id of 0 means "no ComicVine id yet"
/// (name is kept for a future offline-lookup fallback) and short-circuits
/// to null without calling the API.
typedef CreatorKey = ({int id, String name});

final creatorsProvider =
    FutureProvider.autoDispose<List<CreatorSummary>>(
  (ref) async {
    // CreatorsScreen stays mounted in the home IndexedStack, so this watcher
    // never goes away on its own (autoDispose never fires) — rebuild on
    // every connectivity transition so a launch-while-offline failure
    // recovers once the app comes back online, instead of being stuck.
    if (!ref.watch(gutterFeaturesProvider)) return const [];
    ref.watch(connectivityProvider);
    final client = ref.watch(apiClientProvider);
    return client.fetchCreators();
  },
  // See issueCreditsProvider: fail fast offline rather than retrying up to
  // 10x with backoff and showing shimmer for ~40s.
  retry: (_, _) => null,
);

/// null only when there's nothing to show at all (no server profile and no
/// owned series matching this creator).
({CreatorProfile profile, bool offline})? _ownedFallback(
  CreatorKey key,
  List<MirrorSeries> mirror, {
  required bool offline,
}) {
  final owned = ownedByCreator(mirror, id: key.id, name: key.name);
  if (owned.isEmpty) return null;
  return (profile: ownedOnlyProfile(key.id, key.name, owned), offline: offline);
}

final creatorProfileProvider = FutureProvider.autoDispose
    .family<({CreatorProfile profile, bool offline})?, CreatorKey>((ref, key) async {
  if (key.id == 0) {
    final mirror = await ref.watch(mirrorLibraryProvider.future);
    return _ownedFallback(key, mirror, offline: false);
  }

  final client = ref.watch(apiClientProvider);
  CreatorProfile? profile;
  try {
    profile = await client.fetchCreator(key.id);
  } catch (_) {
    // The creator page is never an error screen: a SocketException, an
    // ApiException other than 404 (fetchCreator already turns a literal
    // 404 into a null return), a TimeoutException, or a malformed response
    // (FormatException/TypeError) all fall back the same way.
    final mirror = await ref.watch(mirrorLibraryProvider.future);
    return _ownedFallback(key, mirror, offline: true);
  }

  // A null result here is a real 404 from fetchCreator.
  if (profile == null) {
    final mirror = await ref.watch(mirrorLibraryProvider.future);
    return _ownedFallback(key, mirror, offline: false);
  }
  return (profile: profile, offline: false);
});

final volumeInfoProvider = FutureProvider.autoDispose.family<VolumeInfo, int>(
  (ref, id) async {
    final client = ref.watch(apiClientProvider);
    return client.fetchVolumeInfo(id);
  },
  retry: (_, _) => null,
);

/// Issue-level credits for the reader's credits sheet. Null means no
/// ComicVine id (404) — the sheet falls back to ComicInfo in that case, same
/// as any other non-200 outcome.
final issueCreditsProvider = FutureProvider.autoDispose
    .family<List<Creator>?, String>(
  (ref, comicId) async {
    final client = ref.watch(apiClientProvider);
    return client.fetchIssueCredits(comicId);
  },
  // Fall back to ComicInfo immediately on any error rather than retrying —
  // riverpod's default auto-retry (up to 10x, exponential backoff) would
  // otherwise leave the sheet showing shimmer for seconds first.
  retry: (_, _) => null,
);
