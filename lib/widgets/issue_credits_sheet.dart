import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/app_theme.dart';
import '../config/creator_roles.dart';
import '../config/scheme.dart';
import '../models/comic_info.dart';
import '../models/creator.dart';
import '../providers/creator_provider.dart';
import '../services/mirror/library_view.dart' show creditsFromComicInfo;
import 'shimmer_box.dart';

/// Reader "..." menu entry: lists an issue's credits. Prefers server-sourced
/// ComicVine credits ([issueCreditsProvider]); falls back to the raw
/// ComicInfo writer/penciller fields ([creditsFromComicInfo]) while loading
/// is still in flight, on any load failure, or when the server has none.
///
/// Content only — the host (the reader's `_showCredits`) supplies the glass
/// sheet and `SafeArea`, same split as `ReaderAaPanel`.
///
/// A tap on a row with a tracked role (see [roleGroup]) pops this sheet via
/// its own `Navigator`, then calls [onOpen] — the reader owns leaving the
/// reader (hiding chrome, saving progress, pausing the session) and actually
/// pushing the creator page, the same way it does for "Issue details".
class IssueCreditsSheet extends ConsumerWidget {
  final String comicId;
  final ComicInfo? info;
  final String title;
  final void Function(int id, String name) onOpen;

  const IssueCreditsSheet({
    super.key,
    required this.comicId,
    required this.info,
    required this.title,
    required this.onOpen,
  });

  String get _heading {
    final series = info?.series;
    final number = info?.number;
    if (series != null &&
        series.isNotEmpty &&
        number != null &&
        number.isNotEmpty) {
      return '$series #$number';
    }
    return title;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final creditsAsync = ref.watch(issueCreditsProvider(comicId));
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 6, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_heading,
                style: AppTheme.titleMedium.copyWith(fontSize: 20)),
            const SizedBox(height: 10),
            Text('Credits', style: context.sectionHeader),
            const SizedBox(height: 8),
            creditsAsync.when(
              loading: () => _shimmerRows(),
              error: (_, _) => _rows(context, creditsFromComicInfo(info)),
              data: (list) => _rows(
                context,
                (list == null || list.isEmpty)
                    ? creditsFromComicInfo(info)
                    : list,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _shimmerRows() {
    return const Column(
      children: [
        Padding(
            padding: EdgeInsets.symmetric(vertical: 6),
            child: ShimmerBox(height: 16)),
        Padding(
            padding: EdgeInsets.symmetric(vertical: 6),
            child: ShimmerBox(height: 16)),
        Padding(
            padding: EdgeInsets.symmetric(vertical: 6),
            child: ShimmerBox(height: 16)),
      ],
    );
  }

  Widget _rows(BuildContext context, List<Creator> credits) {
    if (credits.isEmpty) {
      return Text('No credits for this issue.',
          style: TextStyle(color: context.scheme.t3, fontSize: 14));
    }
    return Column(
      children: [
        for (var i = 0; i < credits.length; i++) ...[
          if (i > 0) Divider(height: 1, color: context.scheme.hair),
          _row(context, credits[i]),
        ],
      ],
    );
  }

  Widget _row(BuildContext context, Creator c) {
    final roles = c.role.split(',').map((r) => r.trim()).where((r) => r.isNotEmpty);
    final tappable = roles.any((r) => roleGroup(r) != null);
    final roleLabel = roles
        .map((r) => r[0].toUpperCase() + r.substring(1))
        .join(' · ');
    final nameColor = tappable ? AppTheme.accent : context.scheme.t2;
    return InkWell(
      onTap: tappable
          ? () {
              HapticFeedback.selectionClick();
              Navigator.of(context).pop();
              onOpen(c.id, c.name);
            }
          : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            SizedBox(
              width: 90,
              child: Text(
                roleLabel,
                style: TextStyle(fontSize: 13, color: context.scheme.t3),
              ),
            ),
            Expanded(
              child: Text(
                c.name,
                textAlign: TextAlign.right,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: nameColor,
                ),
              ),
            ),
            if (tappable) ...[
              const SizedBox(width: 4),
              Icon(Icons.chevron_right, size: 16, color: AppTheme.accent),
            ],
          ],
        ),
      ),
    );
  }
}
