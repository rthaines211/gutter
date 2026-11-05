// lib/widgets/creator_search_rows.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/scheme.dart';
import '../models/creator_profile.dart';
import '../providers/creator_provider.dart';
import 'creator_detail_panel.dart' show openCreator;

/// At most 5 creators whose name contains [query] (case-insensitive),
/// ordered by series count desc then name. Sits above the series grid in
/// library search. Renders nothing when [query] is blank, there are no
/// matches, or [creatorsProvider] is loading/erroring (offline) — no error
/// text, just no section.
class CreatorSearchRows extends ConsumerWidget {
  final String query;
  const CreatorSearchRows({super.key, required this.query});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return const SizedBox.shrink();

    final matches = ref.watch(creatorsProvider).when(
          data: (creators) => _matches(creators, q),
          loading: () => const <CreatorSummary>[],
          error: (_, _) => const <CreatorSummary>[],
        );
    if (matches.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
          child: Text('CREATORS', style: context.sectionHeader),
        ),
        for (final c in matches) _CreatorRow(creator: c),
      ],
    );
  }
}

List<CreatorSummary> _matches(List<CreatorSummary> creators, String q) {
  final filtered = creators.where((c) => c.name.toLowerCase().contains(q)).toList()
    ..sort((a, b) {
      final bySeries = b.seriesIds.length.compareTo(a.seriesIds.length);
      return bySeries != 0 ? bySeries : a.name.compareTo(b.name);
    });
  return filtered.take(5).toList();
}

String _titleCase(String s) =>
    s.isEmpty ? s : s[0].toUpperCase() + s.substring(1).toLowerCase();

String _initials(String name) {
  final parts =
      name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
  if (parts.isEmpty) return '?';
  if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
  return (parts.first.substring(0, 1) + parts.last.substring(0, 1)).toUpperCase();
}

class _CreatorRow extends ConsumerWidget {
  final CreatorSummary creator;
  const _CreatorRow({required this.creator});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final roles = creator.roles.map(_titleCase).join(' · ');
    final seriesLabel = '${creator.seriesIds.length} series';
    final subtitle = roles.isEmpty ? seriesLabel : '$roles · $seriesLabel';

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        HapticFeedback.selectionClick();
        openCreator(context, ref, id: creator.id, name: creator.name);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: context.scheme.hair)),
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: context.scheme.s2,
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  _initials(creator.name),
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: context.scheme.t2,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    creator.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: context.scheme.tx,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11, color: context.scheme.t3),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, size: 18, color: context.scheme.t4),
          ],
        ),
      ),
    );
  }
}
