// lib/widgets/volume_info_sheet.dart
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../config/app_theme.dart';
import '../config/scheme.dart';
import '../models/creator_profile.dart';
import '../providers/creator_provider.dart';
import 'shimmer_box.dart';

/// Read-only info sheet for a bibliography volume not in the local library:
/// cover, name, year/publisher, issue count, description. No actions — the
/// volume isn't owned, so there's nothing to do with it from here.
class VolumeInfoSheet extends ConsumerWidget {
  final int volumeId;

  const VolumeInfoSheet({super.key, required this.volumeId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final infoAsync = ref.watch(volumeInfoProvider(volumeId));
    return Container(
      decoration: BoxDecoration(
        color: context.scheme.s1,
        borderRadius:
            const BorderRadius.vertical(top: Radius.circular(AppTheme.r16)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 10, 18, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: context.scheme.t4,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              infoAsync.when(
                loading: () => const _LoadingBody(),
                error: (_, _) => _ErrorBody(),
                data: (info) => _InfoBody(info: info),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LoadingBody extends StatelessWidget {
  const _LoadingBody();

  @override
  Widget build(BuildContext context) {
    return const Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ShimmerBox(width: 96, height: 146, radius: AppTheme.r8),
        SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ShimmerBox(width: double.infinity, height: 20),
              SizedBox(height: 8),
              ShimmerBox(width: 140, height: 14),
            ],
          ),
        ),
      ],
    );
  }
}

class _ErrorBody extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Text(
        'Details unavailable offline.',
        style: TextStyle(color: context.scheme.t2),
      ),
    );
  }
}

class _InfoBody extends StatelessWidget {
  final VolumeInfo info;
  const _InfoBody({required this.info});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(AppTheme.r8),
              child: info.coverUrl.isEmpty
                  ? Container(width: 96, height: 146, color: context.scheme.s2)
                  : CachedNetworkImage(
                      imageUrl: info.coverUrl,
                      width: 96,
                      height: 146,
                      fit: BoxFit.cover,
                      memCacheWidth: 200,
                      placeholder: (_, _) =>
                          Container(width: 96, height: 146, color: context.scheme.s2),
                      errorWidget: (_, _, _) =>
                          Container(width: 96, height: 146, color: context.scheme.s2),
                    ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(info.name, style: AppTheme.titleMedium.copyWith(fontSize: 20)),
                  const SizedBox(height: 6),
                  Text('${info.startYear} · ${info.publisher}',
                      style: context.monoCaption),
                  const SizedBox(height: 2),
                  Text('${info.totalIssues} issues', style: context.monoCaption),
                ],
              ),
            ),
          ],
        ),
        if (info.description.isNotEmpty) ...[
          const SizedBox(height: 14),
          Text(
            info.description,
            style: TextStyle(color: context.scheme.t2, fontSize: 13, height: 1.45),
          ),
        ],
      ],
    );
  }
}
