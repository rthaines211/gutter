import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/providers.dart';
import '../providers/remote_provider.dart';
import '../services/remote_session.dart';
import '../widgets/shimmer_box.dart';

/// Phone-side remote for the iPad reader. Renders the iPad's live state and
/// sends commands back through the backend relay.
class RemoteScreen extends ConsumerWidget {
  const RemoteScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapshot = ref.watch(remoteSnapshotProvider).value;
    // A dropped stream and a closed reader are different failures. Null
    // snapshot means nothing to control; not connected means what is on
    // screen may be stale. Showing only the former hid the latter entirely.
    final connected = ref.watch(remoteConnectedProvider).value ?? false;
    return Scaffold(
      appBar: AppBar(title: const Text('Remote')),
      body: Column(
        children: [
          if (!connected) const _ReconnectingBanner(),
          Expanded(
            child: snapshot == null
                ? const Center(child: Text('No iPad reading'))
                : _RemoteBody(snapshot: snapshot),
          ),
        ],
      ),
    );
  }
}

class _ReconnectingBanner extends StatelessWidget {
  const _ReconnectingBanner();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      color: scheme.errorContainer,
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: scheme.onErrorContainer,
            ),
          ),
          const SizedBox(width: 10),
          Text(
            'Reconnecting…',
            style: TextStyle(color: scheme.onErrorContainer),
          ),
        ],
      ),
    );
  }
}

class _RemoteBody extends ConsumerStatefulWidget {
  final RemoteSnapshot snapshot;
  const _RemoteBody({required this.snapshot});

  @override
  ConsumerState<_RemoteBody> createState() => _RemoteBodyState();
}

class _RemoteBodyState extends ConsumerState<_RemoteBody> {
  // In-progress scrub value; null means "follow the live snapshot". The
  // slider can't just read snapshot.page during a drag because the
  // snapshot only updates after a goto command round-trips the relay.
  double? _dragPage;

  // Debounced page the thumbnail and counter show. Separate from _dragPage so
  // a fast scrub across 20 pages fetches where the thumb rests, not every
  // division it passed through.
  int? _previewPage;
  Timer? _previewDebounce;

  static const _previewDelay = Duration(milliseconds: 150);

  // Pages are served full-res; decoding them at phone width instead keeps a
  // page turn off the jank budget. Matches SeriesGridTile's approach.
  // ponytail: fixed width, not MediaQuery-derived. Every phone this runs on
  // is within a factor of two of it; read the real width if that changes.
  static const int _decodeWidth = 720;

  /// The page the phone is displaying: a scrub preview if one is pending,
  /// otherwise whatever the iPad last reported.
  int get _shownPage => _previewPage ?? widget.snapshot.page;

  @override
  void didUpdateWidget(_RemoteBody old) {
    super.didUpdateWidget(old);
    // The iPad caught up with the scrub, so stop previewing and follow it
    // again. Comparing rather than clearing unconditionally avoids a flash
    // back to the old page while the goto is still in flight.
    if (_previewPage != null && widget.snapshot.page == _previewPage) {
      _previewPage = null;
    }
  }

  @override
  void dispose() {
    _previewDebounce?.cancel();
    super.dispose();
  }

  /// [firm] picks the heavier haptic for bookmarks, matching the reader.
  Future<void> _send(String type, {int? page, bool firm = false}) async {
    firm ? HapticFeedback.mediumImpact() : HapticFeedback.selectionClick();
    final ok =
        await ref.read(remoteSessionProvider).sendCommand(type, page: page);
    if (!ok && mounted) {
      // A 409 (no reader connected) or a dead network must not look like
      // success — the button press is otherwise completely silent. The iPad
      // will never reach the previewed page either, so stop showing it.
      setState(() => _previewPage = null);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No iPad reading')),
      );
    }
  }

  void _previewAfterDelay(int page) {
    _previewDebounce?.cancel();
    _previewDebounce = Timer(_previewDelay, () {
      if (mounted) setState(() => _previewPage = page);
    });
  }

  Widget _pageImage(bool atEnd) {
    if (atEnd) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.check_circle_outline_rounded, size: 40),
            SizedBox(height: 8),
            Text('End of issue'),
          ],
        ),
      );
    }
    final url = ref
        .watch(apiClientProvider)
        .pageUrl(widget.snapshot.comicId, _shownPage);
    return CachedNetworkImage(httpHeaders: imageHeadersOf(context), 
      imageUrl: url,
      fit: BoxFit.contain,
      memCacheWidth: _decodeWidth,
      // No crossfade: a page turn should register immediately, and a fade
      // reads as lag on a control surface.
      fadeInDuration: Duration.zero,
      placeholder: (_, _) => const ShimmerBox(height: double.infinity),
      errorWidget: (_, _, _) => const Center(
        child: Icon(Icons.broken_image_outlined, size: 32),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = widget.snapshot;
    // v1 drives page mode only: ScrollReader cannot be positioned externally.
    final scrollMode = snapshot.readingMode == 'scroll';
    final total = snapshot.totalPages;
    // The reader's end card sits at page == pageCount, one past the last real
    // page: there is no image to fetch and the counter must not read N+1 / N.
    final atEnd = total > 0 && _shownPage >= total;
    final counter = atEnd ? total : _shownPage + 1;

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(snapshot.series, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Text('$counter / $total',
              style: Theme.of(context).textTheme.headlineMedium),
          if (scrollMode) ...[
            const SizedBox(height: 16),
            const Text(
              'Scroll mode — remote page turns are unavailable. '
              'Switch the iPad to page mode.',
            ),
          ],
          const SizedBox(height: 16),
          Expanded(child: _pageImage(atEnd)),
          const SizedBox(height: 24),
          if (!scrollMode) ...[
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 96,
                    child: FilledButton.tonal(
                      onPressed: () => _send('prev'),
                      child: const Icon(Icons.chevron_left, size: 40),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: SizedBox(
                    height: 96,
                    child: FilledButton(
                      onPressed: () => _send('next'),
                      child: const Icon(Icons.chevron_right, size: 40),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (total > 1)
              Slider(
                value: (_dragPage ?? snapshot.page.toDouble())
                    .clamp(0, (total - 1).toDouble()),
                min: 0,
                max: (total - 1).toDouble(),
                divisions: total - 1,
                label: '${(_dragPage ?? snapshot.page.toDouble()).round() + 1}',
                // Visual-only: no network call or haptic per pixel of drag.
                // The command fires once, on release, in onChangeEnd. The
                // thumbnail previews on a debounce so a fast scrub fetches
                // only where the thumb settles.
                onChanged: (v) {
                  setState(() => _dragPage = v);
                  _previewAfterDelay(v.round());
                },
                onChangeEnd: (v) {
                  _previewDebounce?.cancel();
                  _send('goto', page: v.round());
                  setState(() {
                    _dragPage = null;
                    _previewPage = v.round();
                  });
                },
              ),
          ],
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              TextButton.icon(
                onPressed: () => _send('bookmark', firm: true),
                icon: Icon(snapshot.bookmarked
                    ? Icons.bookmark_rounded
                    : Icons.bookmark_border_rounded),
                label: const Text('Bookmark'),
              ),
              TextButton.icon(
                onPressed:
                    snapshot.hasNextIssue ? () => _send('nextIssue') : null,
                icon: const Icon(Icons.skip_next_rounded),
                label: const Text('Next issue'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
