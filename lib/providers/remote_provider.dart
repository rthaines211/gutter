import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/remote_session.dart';
import 'source_provider.dart';

/// Remote-control session against the active backend. Rebuilds when the
/// active source changes, mirroring apiClientProvider.
final remoteSessionProvider = Provider<RemoteSession>((ref) {
  final source = ref.watch(activeSourceProvider);
  final session = RemoteSession(
    baseUrl: source.baseUrl,
    authHeaders: source.authHeaders,
  );
  ref.onDispose(session.dispose);
  return session;
});

/// Opens a command stream for one reader session.
///
/// A factory, not a cached Stream: the backend decides "which iPad is
/// reading" by who holds an open `role=reader` SSE stream, so the stream's
/// lifetime must equal the reader's. A cached stream would be shared and
/// never cancelled, leaving the relay convinced a reader is connected long
/// after the reader closed. Call this exactly once per reader (in initState)
/// and hold the result — calling it in build() reconnects every frame.
/// Tests override it with `overrideWithValue(() => someStream)`.
final remoteCommandsProvider =
    Provider<Stream<Map<String, dynamic>> Function()>((ref) {
  final session = ref.watch(remoteSessionProvider);
  return () => session.events('reader');
});

/// The iPad's state, as seen by the phone. Null means no iPad is reading —
/// either none ever connected, or the hub sent `reader_gone` because the last
/// reader stream ended. Without that frame a phone already streaming kept
/// rendering a frozen page count from a closed reader.
final remoteSnapshotProvider = StreamProvider<RemoteSnapshot?>((ref) {
  return ref.watch(remoteSessionProvider).events('remote').map(
        (frame) => frame['type'] == 'reader_gone'
            ? null
            : RemoteSnapshot.fromJson(frame),
      );
});

/// Whether the phone's own stream to the relay is up. Distinct from
/// [remoteSnapshotProvider] being null: no connection means the snapshot on
/// screen may be stale, while a live connection with a null snapshot means
/// the iPad genuinely stopped reading.
final remoteConnectedProvider = StreamProvider<bool>((ref) {
  return ref.watch(remoteSessionProvider).connectionChanges;
});
