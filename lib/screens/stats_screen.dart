import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../config/app_theme.dart';
import '../config/scheme.dart';
import '../providers/stats_provider.dart';
import '../widgets/stats_dashboard.dart';
import '../widgets/stats_history_list.dart';
import '../providers/accent_provider.dart';

class StatsScreen extends ConsumerWidget {
  const StatsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accent = ref.watch(accentProvider).value ?? AppTheme.accent;
    final summaryAsync = ref.watch(statsSummaryProvider);

    return Scaffold(
      backgroundColor: context.scheme.bg,
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          color: accent,
          backgroundColor: context.scheme.s2,
          onRefresh: () async {
            HapticFeedback.mediumImpact();
            ref.invalidate(statsSummaryProvider);
            ref.read(statsHistoryProvider.notifier).refresh();
            await ref.read(statsSummaryProvider.future);
          },
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(
              parent: BouncingScrollPhysics(),
            ),
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Stats', style: AppTheme.titleLarge),
                      const SizedBox(height: 2),
                      Text('Your reading activity', style: context.monoLabel),
                    ],
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: summaryAsync.when(
                  loading: () => SizedBox(
                    height: 200,
                    child: Center(child: CircularProgressIndicator(color: accent)),
                  ),
                  error: (err, _) => Padding(
                    padding: const EdgeInsets.all(20),
                    child: Text('Failed to load stats: $err',
                        style: TextStyle(color: context.scheme.t2)),
                  ),
                  data: (summary) => StatsDashboard(summary: summary, accent: accent),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
                  child: Text('Reading History', style: AppTheme.titleMedium),
                ),
              ),
              const StatsHistoryList(),
              const SliverToBoxAdapter(child: SizedBox(height: 120)),
            ],
          ),
        ),
      ),
    );
  }
}
