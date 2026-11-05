import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/scheme.dart';
import '../models/review_item.dart';
import '../providers/providers.dart';
import 'shimmer_box.dart';

/// Pick a ComicVine/GCD volume. Pops with the chosen hit (null if dismissed).
Future<VolumeHit?> showReviewSearchSheet(
  BuildContext context, {
  required String initialQuery,
}) => showModalBottomSheet<VolumeHit>(
  context: context,
  isScrollControlled: true,
  backgroundColor: context.scheme.bgRaised,
  builder: (_) => _SearchSheet(initialQuery: initialQuery),
);

String hitSubtitle(String publisher, String year, int issues) => [
  if (publisher.isNotEmpty) publisher,
  if (year.isNotEmpty) year,
  '$issues issues',
].join(' · ');

class _SearchSheet extends ConsumerStatefulWidget {
  final String initialQuery;
  const _SearchSheet({required this.initialQuery});

  @override
  ConsumerState<_SearchSheet> createState() => _SearchSheetState();
}

class _SearchSheetState extends ConsumerState<_SearchSheet> {
  late final _ctrl = TextEditingController(text: widget.initialQuery);
  Timer? _debounce;
  List<VolumeHit>? _hits; // null = loading
  int _seq = 0;

  @override
  void initState() {
    super.initState();
    _search();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final seq = ++_seq;
    setState(() => _hits = null);
    List<VolumeHit> hits;
    try {
      hits = await ref.read(apiClientProvider).searchReviewVolumes(_ctrl.text);
    } catch (_) {
      hits = const [];
    }
    if (mounted && seq == _seq) setState(() => _hits = hits);
  }

  @override
  Widget build(BuildContext context) {
    final s = context.scheme;
    final hits = _hits;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.75,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: TextField(
                controller: _ctrl,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'Search volumes',
                  prefixIcon: Icon(Icons.search_rounded),
                ),
                onChanged: (_) {
                  _debounce?.cancel();
                  _debounce = Timer(const Duration(milliseconds: 300), _search);
                },
              ),
            ),
            Expanded(
              child: hits == null
                  ? const Center(child: ShimmerBox(width: 200, height: 20))
                  : hits.isEmpty
                  ? Center(
                      child: Text(
                        'No volumes found',
                        style: TextStyle(color: s.t2),
                      ),
                    )
                  : ListView.builder(
                      itemCount: hits.length,
                      itemBuilder: (_, i) => _HitRow(hit: hits[i]),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HitRow extends StatelessWidget {
  final VolumeHit hit;
  const _HitRow({required this.hit});

  @override
  Widget build(BuildContext context) {
    final s = context.scheme;
    return ListTile(
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: SizedBox(
          width: 44,
          height: 66,
          child: hit.coverUrl.isEmpty
              ? ColoredBox(color: s.s2)
              : CachedNetworkImage(
                  imageUrl: hit.coverUrl,
                  fit: BoxFit.cover,
                  placeholder: (_, _) => const ShimmerBox(),
                  errorWidget: (_, _, _) => ColoredBox(color: s.s2),
                ),
        ),
      ),
      title: Text(hit.name, style: TextStyle(color: s.tx)),
      subtitle: Text(
        hitSubtitle(hit.publisher, hit.year, hit.issueCount),
        style: TextStyle(color: s.t2),
      ),
      trailing: hit.source == 'gcd'
          ? Chip(label: const Text('GCD'), visualDensity: VisualDensity.compact)
          : null,
      onTap: () => Navigator.pop(context, hit),
    );
  }
}
