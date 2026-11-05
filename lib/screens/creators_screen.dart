// lib/screens/creators_screen.dart
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../config/app_theme.dart';
import '../config/creator_roles.dart';
import '../config/layout_breakpoint.dart';
import '../config/scheme.dart';
import '../models/creator_profile.dart';
import '../providers/accent_provider.dart';
import '../providers/creator_provider.dart';
import '../providers/mirror_provider.dart';
import '../providers/providers.dart';
import '../services/creator_view.dart';
import '../services/mirror/mirror_database.dart';
import '../widgets/creator_detail_panel.dart';
import '../widgets/shimmer_box.dart';

enum _RoleFilter { all, writers, artists }

enum _SortMode { mostSeries, aToZ }

bool _sameCreator(CreatorSummary a, CreatorSummary b) => a.id != 0 && b.id != 0
    ? a.id == b.id
    : a.name.toLowerCase() == b.name.toLowerCase();

bool _matchesRole(CreatorSummary c, _RoleFilter f) {
  switch (f) {
    case _RoleFilter.all:
      return true;
    case _RoleFilter.writers:
      return c.roles.any((r) => roleGroup(r) == CreatorRoleGroup.writer);
    case _RoleFilter.artists:
      return c.roles.any((r) => roleGroup(r) == CreatorRoleGroup.art);
  }
}

String _titleCase(String s) =>
    s.isEmpty ? s : s[0].toUpperCase() + s.substring(1).toLowerCase();

/// Grid contents: everyone but [spotlight], narrowed by [query] and
/// [roleFilter], ordered by [sort].
List<CreatorSummary> _visibleGrid(
  List<CreatorSummary> creators,
  CreatorSummary? spotlight,
  String query,
  _RoleFilter roleFilter,
  _SortMode sort,
  List<MirrorSeries> mirror,
) {
  final q = query.trim().toLowerCase();
  final list = creators.where((c) {
    if (spotlight != null && _sameCreator(c, spotlight)) return false;
    if (q.isNotEmpty && !c.name.toLowerCase().contains(q)) return false;
    return _matchesRole(c, roleFilter);
  }).toList();

  list.sort((a, b) {
    if (sort == _SortMode.aToZ) {
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    }
    final byCount = b.seriesIds.length.compareTo(a.seriesIds.length);
    if (byCount != 0) return byCount;
    return a.name.toLowerCase().compareTo(b.name.toLowerCase());
  });
  return list;
}

class CreatorsScreen extends ConsumerStatefulWidget {
  const CreatorsScreen({super.key});

  @override
  ConsumerState<CreatorsScreen> createState() => _CreatorsScreenState();
}

class _CreatorsScreenState extends ConsumerState<CreatorsScreen> {
  final _filterCtrl = TextEditingController();
  _RoleFilter _roleFilter = _RoleFilter.all;
  _SortMode _sort = _SortMode.mostSeries;
  ({int id, String name})? _selected;

  @override
  void dispose() {
    _filterCtrl.dispose();
    super.dispose();
  }

  void _openOrSelect(BuildContext context, CreatorSummary c, bool isTablet) {
    if (isTablet) {
      setState(() => _selected = (id: c.id, name: c.name));
    } else {
      openCreator(context, ref, id: c.id, name: c.name);
    }
  }

  @override
  Widget build(BuildContext context) {
    final accent = ref.watch(accentProvider).value ?? AppTheme.accent;
    final creatorsAsync = ref.watch(creatorsProvider);
    final mirror =
        ref.watch(mirrorLibraryProvider).value ?? const <MirrorSeries>[];
    final isTablet = LayoutBreakpoint.isTablet(context);

    return Scaffold(
      backgroundColor: context.scheme.bg,
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          color: accent,
          backgroundColor: context.scheme.s2,
          onRefresh: () async {
            HapticFeedback.mediumImpact();
            ref.invalidate(creatorsProvider);
            await ref.read(creatorsProvider.future);
          },
          child: creatorsAsync.when(
            loading: () => _buildLoading(context),
            error: (_, _) => _buildOffline(context),
            data: (creators) =>
                _buildBody(context, creators, mirror, accent, isTablet),
          ),
        ),
      ),
    );
  }

  Widget _buildLoading(BuildContext context) {
    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                ShimmerBox(width: 160, height: 30),
                SizedBox(height: 16),
                ShimmerBox(width: double.infinity, height: 40),
                SizedBox(height: 20),
                ShimmerBox(width: double.infinity, height: 150),
                SizedBox(height: 20),
                ShimmerBox(width: double.infinity, height: 120),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildOffline(BuildContext context) {
    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Center(
            child: Text(
              'Creators need the server.',
              style: TextStyle(color: context.scheme.t2),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBody(
    BuildContext context,
    List<CreatorSummary> creators,
    List<MirrorSeries> mirror,
    Color accent,
    bool isTablet,
  ) {
    final spotlight = pickSpotlight(creators, mirror);
    final grid = _visibleGrid(
        creators, spotlight, _filterCtrl.text, _roleFilter, _sort, mirror);
    final columns = isTablet ? 4 : 2;

    final content = _buildScroll(context, spotlight, grid, mirror, accent,
        isTablet, columns);

    if (isTablet && _selected != null) {
      final panelFraction =
          MediaQuery.orientationOf(context) == Orientation.portrait
              ? 0.46
              : 0.40;
      return LayoutBuilder(builder: (context, box) {
        final panelWidth = box.maxWidth * panelFraction;
        final gridWidth = box.maxWidth - panelWidth;
        return Row(
          children: [
            SizedBox(width: gridWidth, child: content),
            Container(
              width: panelWidth,
              decoration: BoxDecoration(
                border:
                    Border(left: BorderSide(color: context.scheme.ink, width: 1)),
              ),
              child: CreatorDetailPanel(
                key: ValueKey(_selected),
                creatorId: _selected!.id,
                name: _selected!.name,
                onClose: () => setState(() => _selected = null),
                accent: accent,
              ),
            ),
          ],
        );
      });
    }
    return content;
  }

  Widget _buildScroll(
    BuildContext context,
    CreatorSummary? spotlight,
    List<CreatorSummary> grid,
    List<MirrorSeries> mirror,
    Color accent,
    bool isTablet,
    int columns,
  ) {
    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Creators',
                    style: AppTheme.titleMedium.copyWith(fontSize: 28)),
                const SizedBox(height: 14),
                TextField(
                  controller: _filterCtrl,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    hintText: 'Filter creators',
                    prefixIcon: const Icon(Icons.search, size: 18),
                    isDense: true,
                    filled: true,
                    fillColor: context.scheme.s1,
                    contentPadding:
                        const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppTheme.r12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _Chip(
                        label: 'All',
                        selected: _roleFilter == _RoleFilter.all,
                        accent: accent,
                        onTap: () => setState(() => _roleFilter = _RoleFilter.all),
                      ),
                      const SizedBox(width: 6),
                      _Chip(
                        label: 'Writers',
                        selected: _roleFilter == _RoleFilter.writers,
                        accent: accent,
                        onTap: () =>
                            setState(() => _roleFilter = _RoleFilter.writers),
                      ),
                      const SizedBox(width: 6),
                      _Chip(
                        label: 'Artists',
                        selected: _roleFilter == _RoleFilter.artists,
                        accent: accent,
                        onTap: () =>
                            setState(() => _roleFilter = _RoleFilter.artists),
                      ),
                      const SizedBox(width: 14),
                      _Chip(
                        label:
                            _sort == _SortMode.mostSeries ? 'Most series' : 'A–Z',
                        selected: false,
                        accent: accent,
                        onTap: () => setState(() => _sort =
                            _sort == _SortMode.mostSeries
                                ? _SortMode.aToZ
                                : _SortMode.mostSeries),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                if (spotlight != null)
                  _Spotlight(
                    creator: spotlight,
                    mirror: mirror,
                    accent: accent,
                    isReading:
                        ownedByCreator(mirror, id: spotlight.id, name: spotlight.name)
                            .any(isInProgress),
                    onOpen: () => _openOrSelect(context, spotlight, isTablet),
                  ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
          sliver: SliverGrid(
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: columns,
              childAspectRatio: 0.72,
              crossAxisSpacing: 14,
              mainAxisSpacing: 14,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, i) => _CreatorCard(
                creator: grid[i],
                mirror: mirror,
                onTap: () => _openOrSelect(context, grid[i], isTablet),
              ),
              childCount: grid.length,
            ),
          ),
        ),
      ],
    );
  }
}

class _Spotlight extends ConsumerWidget {
  final CreatorSummary creator;
  final List<MirrorSeries> mirror;
  final Color accent;
  final bool isReading;
  final VoidCallback onOpen;

  const _Spotlight({
    required this.creator,
    required this.mirror,
    required this.accent,
    required this.isReading,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final serverUrl = ref.watch(serverConfigProvider).serverUrl;
    final coversDir = ref.watch(coversDirProvider);
    final owned = ownedByCreator(mirror, id: creator.id, name: creator.name);
    final issuesReadCount = issuesRead(owned);
    final next = nextByCreator(creator, mirror);
    String? nextSeriesName;
    if (next != null) {
      for (final m in mirror) {
        if (m.series.id == next.seriesId) {
          nextSeriesName = m.series.name;
          break;
        }
      }
    }
    final rolesLine = creator.roles.map(_titleCase).join(' · ');
    final statsLine = [
      if (rolesLine.isNotEmpty) rolesLine,
      '${owned.length} series',
      '$issuesReadCount issues read',
    ].join(' · ');

    return GestureDetector(
      onTap: onOpen,
      behavior: HitTestBehavior.opaque,
      child: Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: context.scheme.s1,
        border: Border.all(color: context.scheme.hair),
        borderRadius: BorderRadius.circular(AppTheme.r16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _CoverFan(
            covers: [
              for (final m in owned.take(4))
                _Cover(
                  localPath: coversDir == null
                      ? null
                      : p.join(coversDir, '${m.series.id}.jpg'),
                  networkUrl: m.series.coverUrl.isEmpty
                      ? ''
                      : '$serverUrl${m.series.coverUrl}',
                ),
            ],
          ),
          const SizedBox(width: 24),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isReading ? "YOU'RE READING" : 'MOST READ',
                  style: context.sectionHeader,
                ),
                const SizedBox(height: 6),
                Text(creator.name,
                    style: AppTheme.titleMedium.copyWith(fontSize: 26)),
                const SizedBox(height: 4),
                Text(statsLine,
                    style: TextStyle(color: context.scheme.t2, fontSize: 13)),
                if (nextSeriesName != null) ...[
                  const SizedBox(height: 8),
                  Text('Next by them: $nextSeriesName',
                      style: TextStyle(color: context.scheme.t2, fontSize: 13)),
                ],
                const SizedBox(height: 12),
                FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: accent),
                  onPressed: onOpen,
                  child: Text('Open ${creator.name}'),
                ),
              ],
            ),
          ),
        ],
      ),
      ),
    );
  }
}

class _CreatorCard extends ConsumerWidget {
  final CreatorSummary creator;
  final List<MirrorSeries> mirror;
  final VoidCallback onTap;

  const _CreatorCard({
    required this.creator,
    required this.mirror,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final serverUrl = ref.watch(serverConfigProvider).serverUrl;
    final coversDir = ref.watch(coversDirProvider);
    final owned = ownedByCreator(mirror, id: creator.id, name: creator.name);
    final duo = owned.take(2).toList();

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: context.scheme.s1,
          border: Border.all(color: context.scheme.hair),
          borderRadius: BorderRadius.circular(AppTheme.r12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: duo.isEmpty
                  ? Container(
                      decoration: BoxDecoration(
                        color: context.scheme.s2,
                        borderRadius: BorderRadius.circular(AppTheme.r4),
                      ),
                    )
                  : Row(
                      children: [
                        for (var i = 0; i < duo.length; i++) ...[
                          if (i > 0) const SizedBox(width: 4),
                          Expanded(
                            child: _Cover(
                              localPath: coversDir == null
                                  ? null
                                  : p.join(
                                      coversDir, '${duo[i].series.id}.jpg'),
                              networkUrl: duo[i].series.coverUrl.isEmpty
                                  ? ''
                                  : '$serverUrl${duo[i].series.coverUrl}',
                            ),
                          ),
                        ],
                      ],
                    ),
            ),
            const SizedBox(height: 8),
            Text(
              creator.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: context.scheme.tx),
            ),
            Text('${owned.length} series', style: context.monoCaption),
          ],
        ),
      ),
    );
  }
}

/// Up to 4 covers, each overlapping the previous one — the hero's "fan".
class _CoverFan extends StatelessWidget {
  final List<Widget> covers;
  const _CoverFan({required this.covers});

  static const _w = 72.0;
  static const _h = 108.0;
  static const _overlap = 30.0;

  @override
  Widget build(BuildContext context) {
    if (covers.isEmpty) return const SizedBox(width: _w, height: _h);
    return SizedBox(
      width: _w + _overlap * (covers.length - 1),
      height: _h,
      child: Stack(
        children: [
          for (var i = 0; i < covers.length; i++)
            Positioned(
              left: i * _overlap,
              child: SizedBox(width: _w, height: _h, child: covers[i]),
            ),
        ],
      ),
    );
  }
}

/// A cover image: local file first (via [coversDirProvider]), network
/// fallback — same precedence as `SeriesGridTile._coverImage`.
class _Cover extends StatelessWidget {
  final String? localPath;
  final String networkUrl;
  const _Cover({this.localPath, required this.networkUrl});

  @override
  Widget build(BuildContext context) {
    final placeholder = Container(color: context.scheme.s2);
    final Widget network = networkUrl.isEmpty
        ? placeholder
        : CachedNetworkImage(httpHeaders: imageHeadersOf(context), 
            imageUrl: networkUrl,
            fit: BoxFit.cover,
            placeholder: (_, _) => placeholder,
            errorWidget: (_, _, _) => placeholder,
          );
    final Widget body = localPath == null
        ? network
        : Image.file(
            File(localPath!),
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => network,
          );
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppTheme.r4),
      child: body,
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final bool selected;
  final Color accent;
  final VoidCallback onTap;

  const _Chip({
    required this.label,
    required this.selected,
    required this.accent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final ink = selected ? Scheme.onAccent(accent) : context.scheme.t2;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? accent : context.scheme.s1,
          border: Border.all(color: selected ? accent : context.scheme.hairStrong),
          borderRadius: BorderRadius.circular(AppTheme.pill),
        ),
        child: Text(label,
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: ink)),
      ),
    );
  }
}
