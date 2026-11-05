import 'dart:convert';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/scheme.dart';
import '../models/review_item.dart';
import '../config/layout_breakpoint.dart';
import '../providers/navigation_provider.dart';
import '../providers/providers.dart';
import '../providers/review_provider.dart';
import '../services/api_client.dart';
import '../widgets/review_search_sheet.dart';
import '../widgets/shimmer_box.dart';

String _errorText(Object e) {
  if (e is! ApiException) return "Couldn't reach the server";
  try {
    final j = jsonDecode(e.message);
    if (j is Map && j['error'] is String) return j['error'] as String;
  } catch (_) {}
  return e.message;
}

class ReviewScreen extends ConsumerWidget {
  const ReviewScreen({super.key});

  Future<void> _run(
    BuildContext context,
    Future<void> Function() action,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await action();
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(_errorText(e))));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = context.scheme;
    final q = ref.watch(reviewQueueProvider);
    final notifier = ref.read(reviewQueueProvider.notifier);
    // The shell keeps this screen mounted; refetch whenever its tab is selected.
    ref.listen(navigationProvider, (prev, next) {
      if (next == NavDestination.review &&
          prev != next &&
          !ref.read(reviewQueueProvider).isLoading) {
        notifier.reload().catchError((_) {});
      }
    });
    Widget refreshable(Widget child) => RefreshIndicator(
      onRefresh: () => notifier.reload().catchError((_) {}),
      child: LayoutBuilder(
        builder: (_, c) => SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: SizedBox(height: c.maxHeight, child: child),
        ),
      ),
    );
    return Scaffold(
      backgroundColor: s.bg,
      appBar: Navigator.canPop(context)
          ? AppBar(backgroundColor: s.bg, title: const Text('Review matches'))
          : null,
      body: SafeArea(
        child: q.when(
          loading: () => const Center(child: ShimmerBox(width: 200, height: 20)),
          error: (e, _) => Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_errorText(e), style: TextStyle(color: s.t2)),
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: () => _run(context, notifier.reload),
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
          data: (st) {
            final item = st.current;
            if (item == null) {
              return refreshable(Center(
                child: Text('All caught up', style: TextStyle(color: s.t2, fontSize: 20)),
              ));
            }
            return refreshable(_Deck(
              item: item,
              counter: '${st.cursor + 1} of ${st.items.length}',
              busy: st.busy,
              onRight: () {
                HapticFeedback.mediumImpact();
                _run(context, notifier.confirm);
              },
              onSearch: () async {
                final hit = await showReviewSearchSheet(
                  context,
                  initialQuery: item.name,
                );
                if (hit != null && context.mounted) {
                  await _run(context, () => notifier.pin(hit));
                }
              },
              onSkip: () {
                HapticFeedback.selectionClick();
                notifier.skip();
              },
              onDontMatch: () => _run(context, notifier.dontMatch),
            ));
          },
        ),
      ),
    );
  }
}

class _Deck extends ConsumerWidget {
  final ReviewItem item;
  final String counter;
  final bool busy;
  final VoidCallback onRight, onSearch, onSkip, onDontMatch;

  const _Deck({
    required this.item,
    required this.counter,
    required this.busy,
    required this.onRight,
    required this.onSearch,
    required this.onSkip,
    required this.onDontMatch,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = context.scheme;
    final base = ref.watch(apiClientProvider).baseUrl;
    final title = item.guessName.isNotEmpty ? item.guessName : item.name;
    final canRight = (item.hasGuess || item.isCollection) && !busy;
    return Padding(
      // Phone: clear the floating tab bar overlaying the bottom.
      padding: EdgeInsets.fromLTRB(
        20,
        20,
        20,
        LayoutBreakpoint.isTablet(context) ? 20 : 120,
      ),
      child: Column(
        children: [
          Text(counter, style: TextStyle(color: s.t3)),
          const SizedBox(height: 12),
          Expanded(
            child: Row(
              children: [
                Expanded(
                  child: _Cover(
                    caption: 'yours',
                    url: item.localCoverUrl.isEmpty ? '' : '$base${item.localCoverUrl}',
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: item.isCollection
                      ? const _Cover(caption: 'best guess', label: 'Collection')
                      : item.hasGuess
                      ? _Cover(caption: 'best guess', url: item.guessCoverUrl)
                      : const _Cover(caption: 'best guess', label: '?', dashed: true),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(color: s.tx, fontSize: 22, fontWeight: FontWeight.w600),
          ),
          if (item.guessName.isNotEmpty && item.guessName != item.name)
            Text(
              'folder: ${item.name}',
              textAlign: TextAlign.center,
              style: TextStyle(color: s.t3, fontSize: 13),
            ),
          if (item.hasGuess)
            Text(
              hitSubtitle(item.guessPublisher, item.guessYear, item.guessIssueCount),
              style: TextStyle(color: s.t2),
            ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: [
              FilledButton(
                onPressed: canRight ? onRight : null,
                child: const Text('✓ Right'),
              ),
              OutlinedButton(
                onPressed: busy ? null : onSearch,
                child: const Text('Search…'),
              ),
              OutlinedButton(onPressed: busy ? null : onSkip, child: const Text('Skip')),
              OutlinedButton(
                onPressed: busy ? null : onDontMatch,
                child: const Text("Don't match"),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Cover extends StatelessWidget {
  final String caption;
  final String? url;
  final String? label;
  final bool dashed;

  const _Cover({required this.caption, this.url, this.label, this.dashed = false});

  @override
  Widget build(BuildContext context) {
    final s = context.scheme;
    Widget box(Widget? child) => Container(
      decoration: BoxDecoration(
        color: s.s1,
        borderRadius: BorderRadius.circular(8),
        border: dashed ? Border.all(color: s.hairStrong) : null,
      ),
      alignment: Alignment.center,
      child: child,
    );
    final Widget body = (url != null && url!.isNotEmpty)
        ? ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: CachedNetworkImage(httpHeaders: imageHeadersOf(context), 
              imageUrl: url!,
              fit: BoxFit.contain,
              placeholder: (_, _) => const ShimmerBox(height: double.infinity),
              errorWidget: (_, _, _) => box(null),
            ),
          )
        : box(label == null
              ? null
              : Text(label!, style: TextStyle(color: s.t2, fontSize: 28)));
    return Column(
      children: [
        Expanded(child: SizedBox(width: double.infinity, child: body)),
        const SizedBox(height: 6),
        Text(caption, style: TextStyle(color: s.t3)),
      ],
    );
  }
}
