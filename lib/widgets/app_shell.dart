import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../config/app_theme.dart';
import '../config/flavor.dart';
import '../config/layout_breakpoint.dart';
import '../config/scheme.dart';
import '../providers/navigation_provider.dart';
import '../providers/connectivity_provider.dart';
import '../providers/accent_provider.dart';
import '../providers/review_provider.dart';
import '../providers/scan_provider.dart';
import '../providers/scan_state.dart';
import '../screens/arcs_screen.dart';
import '../screens/creators_screen.dart';
import '../screens/downloads_screen.dart';
import '../screens/library_screen.dart';
import '../screens/more_screen.dart';
import '../screens/queues_screen.dart';
import '../screens/read_screen.dart';
import '../screens/review_screen.dart';
import '../screens/settings_screen.dart';
import '../screens/stats_screen.dart';
import '../services/chapter_writer.dart';
import 'chapter_review_sheet.dart';
import 'floating_tab_bar.dart';
import 'icon_rail.dart';
import 'scan_indicator.dart';

class AppShell extends ConsumerWidget {
  const AppShell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen<ScanState>(scanProvider, (prev, next) {
      if (prev?.phase == next.phase) return;
      final messenger = ScaffoldMessenger.of(context);
      if (next.phase == ScanPhase.done) {
        if (next.candidates.isEmpty) {
          messenger.showSnackBar(
            const SnackBar(content: Text('No chapters detected')),
          );
          ref.read(scanProvider.notifier).clear();
          return;
        }
        messenger.showSnackBar(SnackBar(
          content: Text(
              '${next.title ?? 'Scan'}: ${next.candidates.length} chapters found'),
          action: SnackBarAction(
            label: 'Review',
            onPressed: () async {
              final accepted = await showChapterReviewSheet(
                context,
                candidates: next.candidates,
              );
              if (accepted != null && accepted.isNotEmpty) {
                await ref
                    .read(chapterWriterProvider)
                    .addChapters(next.comicId!, accepted);
              }
              ref.read(scanProvider.notifier).clear();
            },
          ),
          duration: const Duration(seconds: 8),
        ));
      } else if (next.phase == ScanPhase.failed) {
        final controller = messenger.showSnackBar(SnackBar(
          content: Text(next.error ?? 'Scan failed'),
          action: SnackBarAction(
            label: 'Retry',
            onPressed: () => ref.read(scanProvider.notifier).start(
                  comicId: next.comicId!,
                  title: next.title ?? 'comic',
                ),
          ),
        ));
        // Reset to idle once the banner closes, unless a Retry already moved us on.
        controller.closed.then((_) {
          if (ref.read(scanProvider).phase == ScanPhase.failed) {
            ref.read(scanProvider.notifier).clear();
          }
        });
      }
    });

    // Online-only tabs hide while offline; don't leave one showing.
    ref.listen<bool>(connectivityProvider, (_, online) {
      if (!online &&
          onlineOnlyDestinations.contains(ref.read(navigationProvider))) {
        ref.read(navigationProvider.notifier).go(NavDestination.read);
      }
    });

    final isTablet = LayoutBreakpoint.isTablet(context);

    if (isTablet) {
      return _buildTablet(context, ref);
    }
    return _buildPhone(context, ref);
  }

  Widget _buildPhone(BuildContext context, WidgetRef ref) {
    final accent = ref.watch(accentProvider).value ?? AppTheme.accent;
    // Watch the destination, then derive the index from the notifier's getter.
    // Reading tabIndex off the notifier alone subscribes to nothing, so taps
    // changed the state but never rebuilt the shell — the tab bar and the
    // IndexedStack stayed frozen. _buildTablet already watches, which is why
    // this only ever broke the phone.
    ref.watch(navigationProvider);
    final tabIndex = ref.read(navigationProvider.notifier).tabIndex;
    final isOffline = !ref.watch(connectivityProvider);

    // Store: the hidden tabs' slots stay empty. IndexedStack builds every
    // child, so a hidden screen would still mount and hit its endpoints.
    final screens = [
      const ReadScreen(),
      const LibraryScreen(),
      isStore ? const SizedBox.shrink() : const CreatorsScreen(),
      isStore ? const SizedBox.shrink() : const ReviewScreen(),
      const MoreScreen(),
    ];

    return Scaffold(
      backgroundColor: context.scheme.bg,
      body: Stack(
        children: [
          IndexedStack(
            index: tabIndex,
            children: screens,
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 88),
              child: const ScanIndicator(),
            ),
          ),
          FloatingTabBar(
            currentIndex: tabIndex,
            accent: accent,
            offline: isOffline,
            reviewCount: isStore ? 0 : ref.watch(reviewCountProvider),
            onTap: (i) => ref.read(navigationProvider.notifier).setTabIndex(i),
          ),
        ],
      ),
    );
  }

  Widget _buildTablet(BuildContext context, WidgetRef ref) {
    final nav = ref.watch(navigationProvider);
    final accent = ref.watch(accentProvider).value ?? AppTheme.accent;

    return Scaffold(
      backgroundColor: context.scheme.bg,
      body: Row(
        children: [
          IconRail(accent: accent),
          Container(width: 0.5, color: context.scheme.hair),
          Expanded(
            child: Column(
              children: [
                // IndexedStack, not a switch: rebuilding the destination on
                // every rail tap threw away its scroll position and re-ran its
                // providers, so switching felt like a cold start. The phone
                // path has always kept its screens alive this way.
                Expanded(
                  child: IndexedStack(
                    index: nav.index,
                    children: [
                      for (final d in NavDestination.values)
                        isStore && storeHiddenDestinations.contains(d)
                            ? const SizedBox.shrink()
                            : tabletScreens[d.index],
                    ],
                  ),
                ),
                const ScanIndicator(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// One entry per [NavDestination], in enum order — the [IndexedStack] above
  /// indexes straight into this, so the order must not drift from the enum.
  @visibleForTesting
  static const List<Widget> tabletScreens = [
    ReadScreen(),
    LibraryScreen(),
    DownloadsScreen(),
    QueuesScreen(),
    ArcsScreen(),
    StatsScreen(),
    SettingsScreen(),
    ReviewScreen(),
    CreatorsScreen(),
  ];
}
