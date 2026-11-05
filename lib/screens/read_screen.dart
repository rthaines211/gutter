import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../config/app_theme.dart';
import '../config/comic_style.dart';
import '../config/layout_breakpoint.dart';
import '../config/scheme.dart';
import '../config/string_utils.dart';
import '../models/reading_progress.dart';
import '../providers/connectivity_provider.dart';
import '../providers/download_provider.dart';
import '../providers/mirror_provider.dart';
import '../providers/read_tab_provider.dart';
import '../providers/providers.dart';
import '../providers/scan_status_provider.dart';
import '../widgets/just_added_card.dart';
import '../widgets/recommendation_card.dart';
import '../widgets/resume_hero_card.dart';
import '../widgets/scan_banner.dart';
import '../widgets/shimmer_box.dart';
import '../widgets/streak_chip.dart';
import '../widgets/this_week_card.dart';
import '../widgets/up_next_card.dart';
import 'reader_screen.dart';
import 'series_detail_screen.dart';
import '../widgets/cover_flight_route.dart';

class ReadScreen extends ConsumerWidget {
  const ReadScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dataAsync = ref.watch(readTabProvider);
    final serverUrl = ref.watch(serverConfigProvider).serverUrl;
    final tablet = LayoutBreakpoint.isTablet(context);

    return Scaffold(
      backgroundColor: context.scheme.bg,
      body: SafeArea(
        bottom: false,
        child: dataAsync.when(
          loading: () => _buildShimmer(tablet),
          error: (err, _) => Center(
            child: Text('Failed to load: $err',
                style: TextStyle(color: context.scheme.t2)),
          ),
          data: (data) => _buildContent(context, ref, data, serverUrl, tablet),
        ),
      ),
    );
  }

  Widget _buildContent(
    BuildContext context,
    WidgetRef ref,
    ReadTabData data,
    String serverUrl,
    bool tablet,
  ) {
    final comic = ComicTokens.watch(ref, context, AppTheme.accent);
    final offline = !ref.watch(connectivityProvider);
    final scan = ref.watch(scanStatusProvider);
    final firstScan =
        ref.watch(isCustomSourceProvider) && FirstScanProgress.shows(scan);
    if (offline) {
      // Offline, the shelves hold only what can open: comics on the device,
      // and series with at least one.
      final on = ref.watch(onDeviceProvider);
      data = ReadTabData(
        continueReading: data.continueReading
            .where((p) => on.comicIds.contains(p.comicId))
            .toList(),
        recentSeries: data.recentSeries
            .where((s) => on.perSeries.containsKey(s.id))
            .toList(),
        stats: data.stats,
      );
    }
    return RefreshIndicator(
      color: AppTheme.accent,
      backgroundColor: context.scheme.s2,
      onRefresh: () async {
        HapticFeedback.mediumImpact();
        final engine = ref.read(syncEngineProvider);
        if (engine != null) {
          try {
            await engine.sync();
          } catch (_) {}
        }
        return ref.refresh(readTabProvider.future);
      },
      child: ListView(
        padding: const EdgeInsets.only(bottom: 120),
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _dateLabel(),
                        style: AppTheme.monoLabel.copyWith(
                          fontSize: 11,
                          color: AppTheme.accent,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text('Read', style: AppTheme.displayTextStyle(comic)),
                    ],
                  ),
                ),
                if (data.stats != null)
                  StreakChip(
                    days: data.stats!.streak.current,
                    comic: comic,
                    ),
              ],
            ),
          ),

          // Hero card
          if (data.heroProgress != null)
            ResumeHeroCard(
              progress: data.heroProgress!,
              serverUrl: serverUrl,
              onTap: () => _openReader(context, ref, data.heroProgress!),
            ),

          // This week activity card
          if (data.stats != null)
            ThisWeekCard(
              pagesPerDay: data.stats!.pagesPerDay,
              comic: comic,
              accent: AppTheme.accent,
            ),

          // AI recommendation card (top of shelves)
          if (!offline) const RecommendationCard(), // needs the server

          // Up Next shelf
          if (data.upNext.isNotEmpty)
            _buildShelf(
              comic: comic,
              title: 'Up next',
              trailing: '${data.upNext.length} IN QUEUE',
              height: 230,
              children: data.upNext.map((p) => UpNextCard(
                progress: p,
                serverUrl: serverUrl,
                onTap: () => _openReader(context, ref, p),
              )).toList(),
            ),

          // Just Added shelf
          if (data.justAdded.isNotEmpty)
            _buildShelf(
              comic: comic,
              title: 'Just added',
              height: 220,
              children: data.justAdded.map((s) => JustAddedCard(
                series: s,
                serverUrl: serverUrl,
                onTap: () {
                  Navigator.push(context, MaterialPageRoute(
                    settings: const RouteSettings(name: '/series-detail'),
                    builder: (_) => SeriesDetailScreen(seriesId: s.id),
                  ));
                },
              )).toList(),
            ),

          // Empty state: during the server's first scan, its progress (the
          // Library tab, always mounted in the IndexedStack, starts the watch).
          if (data.heroProgress == null &&
              data.justAdded.isEmpty &&
              firstScan)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
              child: FirstScanProgress(scan: scan),
            )
          else if (data.heroProgress == null && data.justAdded.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
              child: Center(
                child: Text(
                  'No comics in progress.\nStart reading from the Library tab.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: context.scheme.t3, fontSize: 15, height: 1.5),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildShelf({
    required ComicTokens comic,
    required String title,
    required double height,
    required List<Widget> children,
    String? trailing,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Text(title,
                      style: AppTheme.displayTextStyle(comic, fontSize: 22)),
                ),
                if (trailing != null)
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: Builder(
                      builder: (context) => Text(trailing,
                          style: context.monoCaption.copyWith(fontSize: 11)),
                    ),
                  ),
              ],
            ),
          ),
          SizedBox(
            height: height,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: children.length,
              separatorBuilder: (context, index) => const SizedBox(width: 12),
              itemBuilder: (context, i) => children[i],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildShimmer(bool tablet) {
    return ListView(
      padding: const EdgeInsets.only(bottom: 120),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              ShimmerBox(width: 120, height: 12),
              SizedBox(height: 8),
              ShimmerBox(width: 100, height: 34),
            ],
          ),
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 0, 16, 24),
          child: ShimmerBox(height: 380, radius: AppTheme.r28),
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 0, 16, 24),
          child: ShimmerBox(height: 72, radius: AppTheme.r18),
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(20, 8, 20, 12),
          child: ShimmerBox(width: 80, height: 18),
        ),
        SizedBox(
          height: 190,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: 4,
            separatorBuilder: (context, index) => const SizedBox(width: 12),
            itemBuilder: (context, index) => const ShimmerBox(
              width: 150,
              height: 190,
              radius: AppTheme.r18,
            ),
          ),
        ),
      ],
    );
  }

  void _openReader(BuildContext context, WidgetRef ref, ReadingProgress progress) {
    final path = comicIdToPath(progress.comicId);
    Navigator.push(context, readerRoute(
      context,
      comicId: progress.comicId,
      builder: (_) => ReaderScreen(
        comicId: progress.comicId,
        comicPath: path,
        // A finished book reopens at the start, as arcs do; its saved page
        // is pageCount, one past the last image.
        initialPage: progress.currentPage >= progress.totalPages
            ? 0
            : progress.currentPage,
      ),
    )).then((_) => ref.invalidate(readTabProvider));
  }

  String _dateLabel() {
    const days = [
      'MONDAY', 'TUESDAY', 'WEDNESDAY', 'THURSDAY',
      'FRIDAY', 'SATURDAY', 'SUNDAY'
    ];
    const months = [
      'JANUARY', 'FEBRUARY', 'MARCH', 'APRIL',
      'MAY', 'JUNE', 'JULY', 'AUGUST',
      'SEPTEMBER', 'OCTOBER', 'NOVEMBER', 'DECEMBER'
    ];
    final now = DateTime.now();
    return '${days[now.weekday - 1]}, ${months[now.month - 1]} ${now.day}';
  }
}
