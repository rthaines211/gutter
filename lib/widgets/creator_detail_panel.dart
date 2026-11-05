// lib/widgets/creator_detail_panel.dart
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/app_theme.dart';
import '../config/creator_roles.dart';
import '../config/scheme.dart';
import '../models/creator_profile.dart';
import '../models/series.dart';
import '../providers/creator_provider.dart';
import '../providers/mirror_provider.dart';
import '../providers/providers.dart';
import '../screens/creator_detail_screen.dart';
import '../screens/series_detail_screen.dart';
import '../services/creator_view.dart';
import '../services/mirror/mirror_database.dart';
import 'shimmer_box.dart';
import 'volume_info_sheet.dart';

const _groupLabels = {
  CreatorRoleGroup.writer: 'Writer',
  CreatorRoleGroup.art: 'Art',
  CreatorRoleGroup.covers: 'Covers',
};

const _groupOrder = [
  CreatorRoleGroup.writer,
  CreatorRoleGroup.art,
  CreatorRoleGroup.covers,
];

/// Luminosity-weighted greyscale matrix for the "not owned" cover treatment.
const _greyscaleMatrix = <double>[
  0.2126, 0.7152, 0.0722, 0, 0,
  0.2126, 0.7152, 0.0722, 0, 0,
  0.2126, 0.7152, 0.0722, 0, 0,
  0, 0, 0, 1, 0,
];

/// Opens a creator page. With a known ComicVine id (>0) this pushes straight
/// to [CreatorDetailScreen]. With id 0 (no id yet — see [CreatorKey]) it
/// looks the name up first: one match pushes that id, several show a picker
/// sheet, and none (or a failed lookup) pushes with id 0, which renders an
/// owned-only profile built from the local library.
Future<void> openCreator(
  BuildContext context,
  WidgetRef ref, {
  required int id,
  required String name,
}) async {
  if (id > 0) {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CreatorDetailScreen(creatorId: id, name: name),
      ),
    );
    return;
  }

  List<PersonMatch> matches = const [];
  try {
    matches = await ref.read(apiClientProvider).lookupCreator(name);
  } catch (_) {
    // A lookup failure counts as zero matches — same owned-only fallback.
    matches = const [];
  }
  if (!context.mounted) return;

  if (matches.length == 1) {
    final m = matches.first;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CreatorDetailScreen(creatorId: m.id, name: m.name),
      ),
    );
    return;
  }

  if (matches.isEmpty) {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CreatorDetailScreen(creatorId: 0, name: name),
      ),
    );
    return;
  }

  final chosen = await showModalBottomSheet<PersonMatch>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (_) => _PersonMatchSheet(matches: matches),
  );
  if (chosen != null && context.mounted) {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            CreatorDetailScreen(creatorId: chosen.id, name: chosen.name),
      ),
    );
  }
}

class _PersonMatchSheet extends StatelessWidget {
  final List<PersonMatch> matches;
  const _PersonMatchSheet({required this.matches});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: context.scheme.s1,
        borderRadius:
            const BorderRadius.vertical(top: Radius.circular(AppTheme.r16)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: context.scheme.t4,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 8),
            for (final m in matches)
              ListTile(
                title: Text(m.name, style: TextStyle(color: context.scheme.tx)),
                subtitle: Text(
                  '${m.volumes} ${m.volumes == 1 ? 'volume' : 'volumes'}',
                  style: context.monoCaption,
                ),
                onTap: () => Navigator.pop(context, m),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

class CreatorDetailPanel extends ConsumerStatefulWidget {
  final int creatorId;
  final String name;
  final VoidCallback? onClose;
  final Color accent;

  const CreatorDetailPanel({
    super.key,
    required this.creatorId,
    required this.name,
    this.onClose,
    required this.accent,
  });

  @override
  ConsumerState<CreatorDetailPanel> createState() => _CreatorDetailPanelState();
}

class _CreatorDetailPanelState extends ConsumerState<CreatorDetailPanel> {
  CreatorRoleGroup? _selectedGroup;

  @override
  void didUpdateWidget(CreatorDetailPanel old) {
    super.didUpdateWidget(old);
    if (old.creatorId != widget.creatorId || old.name != widget.name) {
      _selectedGroup = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final key = (id: widget.creatorId, name: widget.name);
    final profileAsync = ref.watch(creatorProfileProvider(key));
    final mirror = ref.watch(mirrorLibraryProvider).value ?? const <MirrorSeries>[];
    final serverUrl = ref.watch(serverConfigProvider).serverUrl;

    return ColoredBox(
      color: context.scheme.bg,
      child: profileAsync.when(
        loading: () => _buildLoading(context),
        error: (e, _) => _buildError(context, e),
        data: (result) {
          if (result == null) return _buildEmpty(context);
          return _buildContent(result.profile, result.offline, mirror, serverUrl);
        },
      ),
    );
  }

  Widget _buildLoading(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            ShimmerBox(width: 60, height: 10),
            SizedBox(height: 10),
            ShimmerBox(width: double.infinity, height: 28),
            SizedBox(height: 14),
            ShimmerBox(width: double.infinity, height: 60),
          ],
        ),
      ),
    );
  }

  Widget _buildError(BuildContext context, Object error) {
    return Center(
      child: Text('Failed to load: $error', style: TextStyle(color: context.scheme.t2)),
    );
  }

  Widget _buildEmpty(BuildContext context) {
    return Center(
      child: Text(
        'No works found for ${widget.name}',
        style: TextStyle(color: context.scheme.t2),
      ),
    );
  }

  Widget _buildContent(
    CreatorProfile profile,
    bool offline,
    List<MirrorSeries> mirror,
    String serverUrl,
  ) {
    final owned = ownedByCreator(mirror, id: widget.creatorId, name: widget.name);
    final issuesReadCount = issuesRead(owned);
    final bibliography = profile.bibliography;
    final showOfflineNote = offline || bibliography == null;

    Map<CreatorRoleGroup, int>? chipCounts;
    CreatorRoleGroup? effectiveGroup;
    final List<_Entry> entries;

    if (bibliography != null) {
      chipCounts = _countsByGroup(bibliography);
      effectiveGroup = _selectedGroup ?? defaultGroup(bibliography);
      final filtered = bibliography
          .where((v) => v.roles.any((r) => roleGroup(r) == effectiveGroup))
          .toList();
      entries = _groupByYear(filtered.map(_volumeRow).toList());
    } else {
      entries = _groupByYear(owned.map((m) => _ownedRow(m, serverUrl)).toList());
    }

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: _Header(
            name: widget.name,
            roles: profile.roles,
            volumesOwned: profile.volumesOwned,
            volumesTotal: profile.volumesTotal,
            issuesRead: issuesReadCount,
            onClose: widget.onClose,
            offlineNote: showOfflineNote,
            accent: widget.accent,
            chipCounts: chipCounts,
            selectedGroup: effectiveGroup,
            onSelectGroup: (g) => setState(() => _selectedGroup = g),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, i) => entries[i].build(context),
              childCount: entries.length,
            ),
          ),
        ),
      ],
    );
  }

  Map<CreatorRoleGroup, int> _countsByGroup(List<BibliographyVolume> bib) {
    final counts = <CreatorRoleGroup, int>{};
    for (final v in bib) {
      final groups = <CreatorRoleGroup>{};
      for (final r in v.roles) {
        final g = roleGroup(r);
        if (g != null) groups.add(g);
      }
      for (final g in groups) {
        counts[g] = (counts[g] ?? 0) + 1;
      }
    }
    return counts;
  }

  _YearRow _volumeRow(BibliographyVolume v) {
    final isNone = v.owned == OwnedState.none;
    return _YearRow(
      year: v.startYear,
      row: _Row(
        coverUrl: v.coverUrl,
        title: v.name,
        subtitle: _volumeSubtitle(v),
        badge: _badgeFor(v.owned),
        barFraction:
            v.owned == OwnedState.partial && v.totalIssues > 0
                ? v.ownedIssues / v.totalIssues
                : null,
        desaturate: isNone,
        onTap: () => _openVolume(v),
      ),
    );
  }

  _YearRow _ownedRow(MirrorSeries m, String serverUrl) {
    final s = m.series;
    return _YearRow(
      year: s.startYear ?? s.year ?? 0,
      row: _Row(
        coverUrl: s.coverUrl.isNotEmpty ? '$serverUrl${s.coverUrl}' : '',
        title: s.name,
        subtitle: _ownedRowSubtitle(s),
        badge: _Badge.owned,
        barFraction: null,
        desaturate: false,
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => SeriesDetailScreen(seriesId: s.id)),
        ),
      ),
    );
  }

  void _openVolume(BibliographyVolume v) {
    HapticFeedback.selectionClick();
    // A "none" row has no series by definition, but an owned/partial row
    // could in principle arrive with no seriesId too (stale/inconsistent
    // server data) — fall back to the read-only sheet rather than crash.
    if (v.owned == OwnedState.none || v.seriesId == null) {
      showModalBottomSheet(
        context: context,
        backgroundColor: Colors.transparent,
        builder: (_) => VolumeInfoSheet(volumeId: v.volumeId),
      );
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => SeriesDetailScreen(seriesId: v.seriesId!)),
    );
  }
}

String _volumeSubtitle(BibliographyVolume v) {
  final tail = v.owned == OwnedState.none
      ? '${v.personIssues} ${v.personIssues == 1 ? 'issue' : 'issues'} by them'
      : '${v.ownedIssues} of ${v.totalIssues}';
  final parts = [
    if (v.publisher.isNotEmpty) v.publisher,
    '${v.startYear}',
    tail,
  ];
  return parts.join(' · ');
}

String _ownedRowSubtitle(Series s) {
  final year = s.startYear ?? s.year;
  final parts = [
    if ((s.publisher ?? '').isNotEmpty) s.publisher!,
    if (year != null) '$year',
    '${s.issueCount} ${s.issueCount == 1 ? 'issue' : 'issues'}',
  ];
  return parts.join(' · ');
}

enum _Badge { owned, partial, none }

_Badge _badgeFor(OwnedState s) {
  switch (s) {
    case OwnedState.owned:
      return _Badge.owned;
    case OwnedState.partial:
      return _Badge.partial;
    case OwnedState.none:
      return _Badge.none;
  }
}

/// Row data, independent of whether it came from a [BibliographyVolume] or
/// a locally-owned [MirrorSeries] — the row widget doesn't care which.
class _Row {
  final String coverUrl;
  final String title;
  final String subtitle;
  final _Badge badge;
  final double? barFraction;
  final bool desaturate;
  final VoidCallback onTap;

  const _Row({
    required this.coverUrl,
    required this.title,
    required this.subtitle,
    required this.badge,
    required this.barFraction,
    required this.desaturate,
    required this.onTap,
  });
}

class _YearRow {
  final int year;
  final _Row row;
  const _YearRow({required this.year, required this.row});
}

/// Either entry builds into a widget for the flattened sliver list.
abstract class _Entry {
  Widget build(BuildContext context);
}

class _YearHeaderEntry extends _Entry {
  final int year;
  _YearHeaderEntry(this.year);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 14, bottom: 6),
        child: Text('$year', style: context.sectionHeader),
      );
}

class _RowEntry extends _Entry {
  final _Row row;
  _RowEntry(this.row);

  @override
  Widget build(BuildContext context) => _VolumeRowWidget(row: row);
}

/// Groups [rows] by year (descending), preserving each row's relative order
/// within its year, without relying on [List.sort]'s stability.
List<_Entry> _groupByYear(List<_YearRow> rows) {
  final years = <int>{};
  for (final r in rows) {
    years.add(r.year);
  }
  final sortedYears = years.toList()..sort((a, b) => b.compareTo(a));
  final out = <_Entry>[];
  for (final y in sortedYears) {
    out.add(_YearHeaderEntry(y));
    for (final r in rows) {
      if (r.year == y) out.add(_RowEntry(r.row));
    }
  }
  return out;
}

class _VolumeRowWidget extends StatelessWidget {
  final _Row row;
  const _VolumeRowWidget({required this.row});

  @override
  Widget build(BuildContext context) {
    final placeholder = Container(width: 40, height: 60, color: context.scheme.s2);
    final Widget cover = row.coverUrl.isEmpty
        ? placeholder
        : ClipRRect(
            borderRadius: BorderRadius.circular(AppTheme.r4),
            child: CachedNetworkImage(
              imageUrl: row.coverUrl,
              width: 40,
              height: 60,
              fit: BoxFit.cover,
              memCacheWidth: 200,
              placeholder: (_, _) => placeholder,
              errorWidget: (_, _, _) => placeholder,
            ),
          );
    final coverWidget = row.desaturate
        ? Opacity(
            opacity: 0.45,
            child: ColorFiltered(
              colorFilter: const ColorFilter.matrix(_greyscaleMatrix),
              child: cover,
            ),
          )
        : cover;

    return GestureDetector(
      onTap: row.onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: context.scheme.hair)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            coverWidget,
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    row.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: context.scheme.tx,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(row.subtitle, style: context.monoCaption.copyWith(fontSize: 11)),
                  if (row.barFraction != null) ...[
                    const SizedBox(height: 5),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(AppTheme.pill),
                      child: SizedBox(
                        width: 110,
                        height: 3,
                        child: LinearProgressIndicator(
                          value: row.barFraction!.clamp(0.0, 1.0),
                          backgroundColor: context.scheme.s3,
                          color: AppTheme.amber,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 10),
            _BadgeWidget(badge: row.badge),
          ],
        ),
      ),
    );
  }
}

class _BadgeWidget extends StatelessWidget {
  final _Badge badge;
  const _BadgeWidget({required this.badge});

  @override
  Widget build(BuildContext context) {
    switch (badge) {
      case _Badge.owned:
        return _pill(context, 'Owned', AppTheme.green.withValues(alpha: 0.15),
            AppTheme.green, null);
      case _Badge.partial:
        return _pill(context, 'Partial', AppTheme.amber.withValues(alpha: 0.15),
            AppTheme.amber, null);
      case _Badge.none:
        return _pill(context, 'Not owned', Colors.transparent, context.scheme.t4,
            context.scheme.hairStrong);
    }
  }

  Widget _pill(BuildContext context, String label, Color bg, Color fg, Color? border) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppTheme.r4 + 2),
        border: border != null ? Border.all(color: border) : null,
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: fg),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final String name;
  final List<String> roles;
  final int volumesOwned;
  final int volumesTotal;
  final int issuesRead;
  final VoidCallback? onClose;
  final bool offlineNote;
  final Color accent;
  final Map<CreatorRoleGroup, int>? chipCounts;
  final CreatorRoleGroup? selectedGroup;
  final ValueChanged<CreatorRoleGroup> onSelectGroup;

  const _Header({
    required this.name,
    required this.roles,
    required this.volumesOwned,
    required this.volumesTotal,
    required this.issuesRead,
    required this.onClose,
    required this.offlineNote,
    required this.accent,
    required this.chipCounts,
    required this.selectedGroup,
    required this.onSelectGroup,
  });

  @override
  Widget build(BuildContext context) {
    final rolesLine = roles.map(_titleCase).join(' · ');
    final counts = chipCounts;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Creator', style: context.sectionHeader),
              if (onClose != null)
                GestureDetector(
                  onTap: onClose,
                  child: Icon(Icons.close, size: 18, color: context.scheme.t3),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(name, style: AppTheme.titleMedium.copyWith(fontSize: 28)),
          if (rolesLine.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(rolesLine, style: TextStyle(color: context.scheme.t2, fontSize: 13)),
          ],
          const SizedBox(height: 14),
          Row(
            children: [
              _Stat(value: '$volumesOwned', label: 'volumes owned'),
              const SizedBox(width: 8),
              _Stat(value: '$volumesTotal', label: 'volumes total'),
              const SizedBox(width: 8),
              _Stat(value: '$issuesRead', label: 'issues read'),
            ],
          ),
          if (offlineNote) ...[
            const SizedBox(height: 10),
            Text('Full bibliography needs the server.', style: context.monoCaption),
          ],
          if (counts != null) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final g in _groupOrder)
                  if ((counts[g] ?? 0) > 0)
                    _ChipWidget(
                      label: _groupLabels[g]!,
                      count: counts[g]!,
                      selected: g == selectedGroup,
                      accent: accent,
                      onTap: () => onSelectGroup(g),
                    ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

String _titleCase(String s) =>
    s.isEmpty ? s : s[0].toUpperCase() + s.substring(1).toLowerCase();

class _Stat extends StatelessWidget {
  final String value;
  final String label;
  const _Stat({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        decoration: BoxDecoration(
          color: context.scheme.s1,
          border: Border.all(color: context.scheme.hair),
          borderRadius: BorderRadius.circular(AppTheme.r12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(value, style: TextStyle(
                color: context.scheme.tx, fontSize: 18, fontWeight: FontWeight.w800)),
            Text(label, style: TextStyle(color: context.scheme.t3, fontSize: 10)),
          ],
        ),
      ),
    );
  }
}

class _ChipWidget extends StatelessWidget {
  final String label;
  final int count;
  final bool selected;
  final Color accent;
  final VoidCallback onTap;

  const _ChipWidget({
    required this.label,
    required this.count,
    required this.selected,
    required this.accent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final ink = selected ? Scheme.onAccent(accent) : context.scheme.t2;
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? accent : context.scheme.s1,
          border: Border.all(color: selected ? accent : context.scheme.hairStrong),
          borderRadius: BorderRadius.circular(AppTheme.pill),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label, style: TextStyle(
                fontSize: 12, color: ink, fontWeight: FontWeight.w600)),
            Text(' $count', style: TextStyle(
                fontSize: 12, color: ink.withValues(alpha: 0.7))),
          ],
        ),
      ),
    );
  }
}
