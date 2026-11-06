import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/app_theme.dart';
import '../config/scheme.dart';
import '../models/arc.dart';
import '../models/series.dart';
import '../providers/providers.dart';
import '../services/arc_shelves.dart';
import 'reader_screen.dart';
import '../widgets/cover_flight_route.dart';

/// Opens [issues] at [index] in the reader, with the whole arc as the
/// issue list so next/previous follows the arc's reading order.
void openArcIssue(
  BuildContext context,
  Arc arc,
  List<SeriesIssue> issues,
  int index,
) {
  if (!context.mounted) return;
  HapticFeedback.selectionClick();
  final issue = issues[index];
  Navigator.push(
    context,
    readerRoute(
      context,
      comicId: issue.id,
      builder: (_) => ReaderScreen(
        comicId: issue.id,
        comicPath: issue.name,
        initialPage: arcIssueStartPage(issue),
        seriesIssues: issues,
        currentIssueIndex: index,
        seriesName: arc.name,
      ),
    ),
  );
}

/// Cover image from a server cover URL, either absolute or server-relative
/// (relative URLs resolve against the server URL as `SeriesGridTile` does).
/// An empty URL shows the placeholder without touching the network.
class ArcCover extends ConsumerWidget {
  final String url;
  final double width;
  final double height;
  final double radius;
  final IconData placeholderIcon;

  /// When set, the cover is a [CoverAnchor] the reader flies in from.
  final String? comicId;
  const ArcCover({
    super.key,
    this.comicId,
    required this.url,
    required this.width,
    required this.height,
    this.radius = AppTheme.r4,
    this.placeholderIcon = Icons.account_tree_rounded,
  });

  Widget _image(BuildContext context, String resolved, Widget placeholder) {
    final image = CachedNetworkImage(
      imageUrl: resolved,
      httpHeaders: imageHeadersOf(context, resolved),
      width: width,
      height: height,
      fit: BoxFit.cover,
      placeholder: (_, _) => placeholder,
      errorWidget: (_, _, _) => placeholder,
    );
    final id = comicId;
    if (id == null) return image;
    return CoverAnchor(comicId: id, imageUrl: resolved, radius: radius, child: image);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final resolved = url.startsWith('http')
        ? url
        : '${ref.watch(serverConfigProvider).serverUrl}$url';
    final placeholder = Container(
      width: width,
      height: height,
      color: context.scheme.s1,
      child: Icon(placeholderIcon, color: context.scheme.t3),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: url.isEmpty ? placeholder : _image(context, resolved, placeholder),
    );
  }
}
