import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/app_theme.dart';
import '../config/comic_style.dart';
import '../config/layout_breakpoint.dart';
import '../config/scheme.dart';
import '../models/arc.dart';
import '../providers/accent_provider.dart';
import '../providers/arc_provider.dart';
import '../services/arc_shelves.dart';
import '../widgets/glass_button.dart';
import '../widgets/panel_frame.dart';
import 'arc_common.dart';
import 'arc_detail_screen.dart';

void _openDetail(BuildContext context, Arc arc) {
  HapticFeedback.selectionClick();
  Navigator.push(
    context,
    MaterialPageRoute(
      settings: const RouteSettings(name: '/arc'),
      builder: (_) => ArcDetailScreen(arc: arc),
    ),
  );
}

/// Opens the first unread issue of [arc] (the first issue if all are read).
Future<void> _startReading(BuildContext context, WidgetRef ref, Arc arc) async {
  final issues = await ref.read(arcIssuesProvider(arc.id).future);
  if (issues.isEmpty || !context.mounted) return;
  final i = arcCurrentIndex(issues);
  openArcIssue(context, arc, issues, i < 0 ? 0 : i);
}

class ArcsScreen extends ConsumerStatefulWidget {
  const ArcsScreen({super.key});

  @override
  ConsumerState<ArcsScreen> createState() => _ArcsScreenState();
}

class _ArcsScreenState extends ConsumerState<ArcsScreen> {
  bool _searching = false;
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final arcsAsync = ref.watch(arcsProvider);
    return Scaffold(
      backgroundColor: context.scheme.bg,
      appBar: Navigator.canPop(context)
          ? AppBar(backgroundColor: context.scheme.bg)
          : null,
      body: SafeArea(
        bottom: false,
        child: arcsAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(
            child: Text(
              'Failed to load arcs: $e',
              style: TextStyle(color: context.scheme.t2),
            ),
          ),
          data: (arcs) {
            if (arcs.isEmpty) return const _EmptyState();
            return ListView(
              padding: const EdgeInsets.only(bottom: 120),
              children: [
                _header(arcs.length),
                if (_searching)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                    child: TextField(
                      autofocus: true,
                      decoration: const InputDecoration(
                        hintText: 'Search arcs',
                        prefixIcon: Icon(Icons.search_rounded),
                      ),
                      onChanged: (v) => setState(() => _query = v),
                    ),
                  ),
                if (_query.trim().isNotEmpty)
                  _SearchGrid(arcs: arcs, query: _query.trim())
                else
                  ..._shelves(arcs),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _header(int count) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Expanded, not Flexible + Spacer: those split the free space and
          // left the search button mid-row on iPad.
          Expanded(
            child: Row(
              children: [
                const Flexible(
                  child: Text(
                    'Story Arcs',
                    style: AppTheme.titleLarge,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 12),
                Text('$count', style: context.monoLabel),
              ],
            ),
          ),
          GlassButton(
            label: _searching ? 'Close search' : 'Search',
            onTap: () => setState(() {
              _searching = !_searching;
              if (!_searching) _query = '';
            }),
            child: Icon(
              _searching ? Icons.close_rounded : Icons.search_rounded,
              size: 20,
              color: context.scheme.tx,
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _shelves(List<Arc> arcs) {
    final s = buildArcShelves(arcs);
    return [
      if (s.featured.isNotEmpty) ...[
        const _ShelfTitle('Biggest in your library'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: LayoutBreakpoint.isTablet(context)
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final (i, arc) in s.featured.indexed) ...[
                      if (i > 0) const SizedBox(width: 16),
                      Expanded(child: _FeaturedCard(arc: arc)),
                    ],
                    if (s.featured.length == 1) const Spacer(),
                  ],
                )
              : Column(
                  children: [
                    for (final (i, arc) in s.featured.indexed) ...[
                      if (i > 0) const SizedBox(height: 16),
                      _FeaturedCard(arc: arc),
                    ],
                  ],
                ),
        ),
        const SizedBox(height: 24),
      ],
      if (s.inProgress.isNotEmpty)
        _CoverShelf(title: 'In progress', arcs: s.inProgress),
      for (final shelf in s.shelves)
        _CoverShelf(title: shelf.title, arcs: shelf.arcs),
    ];
  }
}

class _ShelfTitle extends ConsumerWidget {
  final String title;
  const _ShelfTitle(this.title);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final comic = ComicTokens.watch(ref, context, AppTheme.accent);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
      child: Text(title, style: AppTheme.displayTextStyle(comic, fontSize: 22)),
    );
  }
}

/// Thin read/owned progress bar.
class _ArcProgress extends StatelessWidget {
  final Arc arc;
  final Color accent;
  const _ArcProgress({required this.arc, required this.accent});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppTheme.pill),
      child: LinearProgressIndicator(
        value: arc.present == 0 ? 0 : arc.read / arc.present,
        minHeight: 3,
        backgroundColor: context.scheme.s2,
        color: accent,
      ),
    );
  }
}

class _CoverShelf extends StatelessWidget {
  final String title;
  final List<Arc> arcs;
  const _CoverShelf({required this.title, required this.arcs});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _ShelfTitle(title),
          SizedBox(
            height: _CoverCard.height,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              itemCount: arcs.length,
              separatorBuilder: (_, _) => const SizedBox(width: 14),
              itemBuilder: (_, i) => _CoverCard(arc: arcs[i]),
            ),
          ),
        ],
      ),
    );
  }
}

class _CoverCard extends ConsumerWidget {
  static const double coverW = 128;
  static const double coverH = 192;
  static const double height = coverH + 66;

  final Arc arc;
  const _CoverCard({required this.arc});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accent = ref.watch(accentProvider).value ?? AppTheme.accent;
    final name = arcDisplayName(arc.name);
    return GestureDetector(
      onTap: () => _openDetail(context, arc),
      child: SizedBox(
        width: coverW,
        height: height,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ArcCover(url: arc.coverUrl, width: coverW, height: coverH),
            const SizedBox(height: 6),
            _ArcProgress(arc: arc, accent: accent),
            const SizedBox(height: 6),
            Text(
              name.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: context.scheme.tx,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            Text(
              arcCountLabel(arc),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.monoLabel.copyWith(fontSize: 10),
            ),
          ],
        ),
      ),
    );
  }
}

class _FeaturedCard extends ConsumerWidget {
  final Arc arc;
  const _FeaturedCard({required this.arc});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accent = ref.watch(accentProvider).value ?? AppTheme.accent;
    final comic = ComicTokens.watch(ref, context, accent);
    final name = arcDisplayName(arc.name);
    return GestureDetector(
      onTap: () => _openDetail(context, arc),
      child: PanelFrame(
        accent: accent,
        // PanelFrame has no fill; without one its hard offset shadow shows
        // through the card body.
        child: ColoredBox(
          color: context.scheme.s1,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Column(
                  children: [
                    ArcCover(url: arc.coverUrl, width: 140, height: 210),
                    const SizedBox(height: 6),
                    SizedBox(
                      width: 140,
                      child: _ArcProgress(arc: arc, accent: accent),
                    ),
                  ],
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (name.kicker.isNotEmpty)
                        Text(
                          name.kicker,
                          style: AppTheme.monoLabel.copyWith(
                            fontSize: 10,
                            color: accent,
                          ),
                        ),
                      Text(
                        name.title,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: AppTheme.displayTextStyle(
                          comic,
                          fontSize: 32,
                        ).copyWith(color: context.scheme.tx),
                      ),
                      const SizedBox(height: 6),
                      Text(arcCountLabel(arc), style: context.monoLabel),
                      const SizedBox(height: 16),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _PillButton(
                            label: 'Start reading',
                            icon: Icons.play_arrow_rounded,
                            background: accent,
                            foreground: Scheme.onAccent(accent),
                            onTap: () => _startReading(context, ref, arc),
                          ),
                          _PillButton(
                            label: 'Reading order',
                            icon: Icons.format_list_numbered_rounded,
                            background: context.scheme.s2,
                            foreground: context.scheme.tx,
                            onTap: () => _openDetail(context, arc),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PillButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color background;
  final Color foreground;
  final VoidCallback onTap;
  const _PillButton({
    required this.label,
    required this.icon,
    required this.background,
    required this.foreground,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(AppTheme.pill),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: foreground),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: foreground,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SearchGrid extends StatelessWidget {
  final List<Arc> arcs;
  final String query;
  const _SearchGrid({required this.arcs, required this.query});

  @override
  Widget build(BuildContext context) {
    final q = query.toLowerCase();
    final matches = arcs
        .where((a) => a.name.toLowerCase().contains(q))
        .toList();
    if (matches.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(top: 80),
        child: Center(
          child: Text(
            'No arcs match',
            style: TextStyle(color: context.scheme.t2, fontSize: 15),
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Wrap(
        spacing: 14,
        runSpacing: 16,
        children: [for (final a in matches) _CoverCard(arc: a)],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.account_tree_rounded, size: 56, color: context.scheme.t3),
          const SizedBox(height: 12),
          Text(
            'No arcs synced yet',
            style: TextStyle(color: context.scheme.t2, fontSize: 15),
          ),
        ],
      ),
    );
  }
}
