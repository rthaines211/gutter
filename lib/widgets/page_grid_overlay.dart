import 'package:flutter/material.dart';
import '../providers/providers.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../services/local_pages.dart';
import '../config/app_theme.dart';
import '../config/scheme.dart';
import '../services/scrubber_geometry.dart';
import '../services/chapter_merge.dart';
import 'shimmer_box.dart';

/// Full-screen scrollable grid of every page in the current issue. Tapping a
/// thumbnail pops the route with that page index; the close button pops null.
class PageGridOverlay extends StatefulWidget {
  final int totalPages;
  final int currentPage;
  final String Function(int page) pageUrlBuilder;

  /// A downloaded comic's pages dir: thumbnails come from disk (offline too).
  final String? localPagesPath;
  final List<int> bookmarkPages;
  final List<ReaderChapter> chapters;
  final void Function(int page)? onAddChapter;
  final Color accent;

  const PageGridOverlay({
    super.key,
    required this.totalPages,
    required this.currentPage,
    required this.pageUrlBuilder,
    this.localPagesPath,
    this.bookmarkPages = const [],
    this.chapters = const [],
    this.onAddChapter,
    this.accent = AppTheme.accent,
  });

  @override
  State<PageGridOverlay> createState() => _PageGridOverlayState();
}

class _PageGridOverlayState extends State<PageGridOverlay> {
  Widget? _localThumb(BuildContext context, int page) {
    final dir = widget.localPagesPath;
    final file = dir == null ? null : localPageFile(dir, page);
    if (file == null) return null;
    return Image.file(file,
        fit: BoxFit.cover,
        cacheWidth: 300,
        errorBuilder: (_, _, _) => Container(color: context.scheme.s2));
  }

  final ScrollController _controller = ScrollController();
  bool _didInitialScroll = false;
  late final Set<int> _bookmarkSet = widget.bookmarkPages.toSet();

  static const double _spacing = 8;
  static const double _padding = 16;
  static const double _aspectRatio = 2 / 3; // comic page width / height

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final width = MediaQuery.of(context).size.width;
      _scrollToCurrent(width, pageGridColumns(width));
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _scrollToCurrent(double width, int columns) {
    if (_didInitialScroll || !_controller.hasClients) return;
    _didInitialScroll = true;
    final cellWidth =
        (width - 2 * _padding - (columns - 1) * _spacing) / columns;
    final cellHeight = cellWidth / _aspectRatio;
    final row = widget.currentPage ~/ columns;
    final target = row * (cellHeight + _spacing);
    _controller.jumpTo(target.clamp(0.0, _controller.position.maxScrollExtent));
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final columns = pageGridColumns(width);

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text('${widget.totalPages} pages'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: widget.chapters.isEmpty
          ? GridView.builder(
              controller: _controller,
              padding: const EdgeInsets.all(_padding),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: columns,
                mainAxisSpacing: _spacing,
                crossAxisSpacing: _spacing,
                childAspectRatio: _aspectRatio,
              ),
              itemCount: widget.totalPages,
              itemBuilder: (context, index) => _pageTile(index),
            )
          : _sectionedBody(columns),
    );
  }

  // Section boundaries: [start, endExclusive, title] per chapter, plus an
  // untitled leading section for pages before the first chapter.
  List<({int start, int end, String? title})> _sections() {
    final sorted = [...widget.chapters]
      ..sort((a, b) => a.pageNum.compareTo(b.pageNum));
    final out = <({int start, int end, String? title})>[];
    if (sorted.isEmpty || sorted.first.pageNum > 0) {
      final end = sorted.isEmpty ? widget.totalPages : sorted.first.pageNum;
      out.add((start: 0, end: end, title: null));
    }
    for (var i = 0; i < sorted.length; i++) {
      final start = sorted[i].pageNum;
      final end =
          i + 1 < sorted.length ? sorted[i + 1].pageNum : widget.totalPages;
      out.add((start: start, end: end, title: sorted[i].title));
    }
    return out;
  }

  Widget _sectionedBody(int columns) {
    final sections = _sections();
    final slivers = <Widget>[];
    for (final s in sections) {
      if (s.title != null) {
        slivers.add(SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(s.title!,
                style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.white)),
          ),
        ));
      }
      slivers.add(SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        sliver: SliverGrid(
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            mainAxisSpacing: _spacing,
            crossAxisSpacing: _spacing,
            childAspectRatio: _aspectRatio,
          ),
          delegate: SliverChildBuilderDelegate(
            (ctx, i) => _pageTile(s.start + i),
            childCount: s.end - s.start,
          ),
        ),
      ));
    }
    return CustomScrollView(controller: _controller, slivers: slivers);
  }

  Widget _pageTile(int index) {
    // When parked on the end card, currentPage == totalPages (one past the last
    // index), so no cell is highlighted — intentional.
    final isCurrent = index == widget.currentPage;
    final isBookmarked = _bookmarkSet.contains(index);
    return GestureDetector(
      onTap: () => Navigator.of(context).pop(index),
      onLongPress: widget.onAddChapter == null
          ? null
          : () => widget.onAddChapter!(index),
      child: Stack(
        children: [
          Positioned.fill(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: _localThumb(context, index) ?? CachedNetworkImage(httpHeaders: imageHeadersOf(context), 
                imageUrl: widget.pageUrlBuilder(index),
                fit: BoxFit.cover,
                placeholder: (_, _) => const ShimmerBox(
                    width: double.infinity, height: double.infinity, radius: 4),
                errorWidget: (_, _, _) => Container(color: context.scheme.s2),
              ),
            ),
          ),
          if (isCurrent)
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: widget.accent, width: 3),
                ),
              ),
            ),
          if (isBookmarked)
            Positioned(
              top: 4,
              right: 4,
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  color: widget.accent,
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Icon(Icons.bookmark, size: 12, color: Scheme.onAccent(widget.accent)),
              ),
            ),
          Positioned(
            bottom: 2,
            left: 4,
            child: Text('${index + 1}',
                style: context.monoCaption
                    .copyWith(fontSize: 9, color: Colors.white70)),
          ),
        ],
      ),
    );
  }
}
