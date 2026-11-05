import 'package:flutter/material.dart';
import '../providers/providers.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../config/app_theme.dart';
import '../config/layout_breakpoint.dart';
import '../config/scheme.dart';
import '../services/local_pages.dart';
import '../services/scrubber_geometry.dart';
import 'liquid_glass.dart';
import 'page_jump_pill.dart';
import 'shimmer_box.dart';

class FilmstripScrubber extends StatefulWidget {
  final int currentPage;
  final int totalPages;
  final String Function(int page) pageUrlBuilder;

  /// A downloaded comic's pages dir: thumbnails come from disk (offline too).
  final String? localPagesPath;
  final ValueChanged<int> onPageSelected;
  final List<int> bookmarkPages;
  final List<int> chapterPages;
  final Color accent;
  final VoidCallback? onOpenGrid;

  const FilmstripScrubber({
    super.key,
    required this.currentPage,
    required this.totalPages,
    required this.pageUrlBuilder,
    this.localPagesPath,
    required this.onPageSelected,
    this.bookmarkPages = const [],
    this.chapterPages = const [],
    this.accent = AppTheme.accent,
    this.onOpenGrid,
  });

  @override
  State<FilmstripScrubber> createState() => _FilmstripScrubberState();
}

class _FilmstripScrubberState extends State<FilmstripScrubber> {
  Widget? _localThumb(BuildContext context, int page) {
    final dir = widget.localPagesPath;
    final file = dir == null ? null : localPageFile(dir, page);
    if (file == null) return null;
    return Image.file(file,
        fit: BoxFit.cover,
        cacheWidth: (68 * MediaQuery.devicePixelRatioOf(context)).round(),
        errorBuilder: (_, _, _) => Container(color: context.scheme.s2));
  }

  bool _isDragging = false;
  double _dragValue = 0;
  int _lastHapticPage = -1;

  // Thumbnail strip: every page, lazily built. Each slot has a fixed extent
  // (the current page's slot is wider so its enlarged thumb fits), so the
  // centring offset is arithmetic, not a measurement.
  static const double _slot = 54, _currentSlot = 74;
  final ScrollController _strip = ScrollController();
  bool _userScrolling = false;

  double get _maxValue => widget.totalPages > 1 ? (widget.totalPages - 1).toDouble() : 1;
  int get _activePage => _isDragging ? _dragValue.round() : widget.currentPage;

  /// Horizontal inset of the bar; matches the top bar's (`_barInset` in
  /// reader_screen.dart).
  double get _barInset => LayoutBreakpoint.isTablet(context) ? 20 : 12;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _centre(animate: false));
  }

  @override
  void didUpdateWidget(FilmstripScrubber old) {
    super.didUpdateWidget(old);
    if (old.currentPage != widget.currentPage) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _centre());
    }
  }

  @override
  void dispose() {
    _strip.dispose();
    super.dispose();
  }

  /// Scrolls the strip so the active page sits in the middle. Never while the
  /// user's finger (or its fling) is moving the strip.
  void _centre({bool animate = true}) {
    if (!mounted || !_strip.hasClients || _userScrolling) return;
    final pos = _strip.position;
    final target = (_activePage * _slot + _currentSlot / 2 - pos.viewportDimension / 2)
        .clamp(pos.minScrollExtent, pos.maxScrollExtent);
    if (animate) {
      _strip.animateTo(target, duration: const Duration(milliseconds: 250), curve: Curves.easeOutCubic);
    } else {
      _strip.jumpTo(target);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(_barInset, 0, _barInset, 8),
        child: LiquidGlass(
          radius: 24,
          padding: const EdgeInsets.fromLTRB(0, 8, 0, 2),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildThumbnailStrip(),
              const SizedBox(height: 4),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: _buildSliderTrack(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildThumbnailStrip() {
    final active = _activePage;
    return SizedBox(
      height: 96,
      child: NotificationListener<ScrollNotification>(
        onNotification: (n) {
          if (n is ScrollStartNotification && n.dragDetails != null) {
            _userScrolling = true;
          } else if (n is ScrollEndNotification) {
            _userScrolling = false;
          }
          return false;
        },
        child: ListView.builder(
          controller: _strip,
          scrollDirection: Axis.horizontal,
          itemCount: widget.totalPages,
          itemExtentBuilder: (i, _) => i == active ? _currentSlot : _slot,
          itemBuilder: (context, page) => _buildThumb(page, page == active),
        ),
      ),
    );
  }

  Widget _buildThumb(int page, bool isCurrent) {
    final isChapterStart = widget.chapterPages.contains(page);
    return Center(
      child: GestureDetector(
        key: ValueKey('filmstrip.thumb.$page'),
        onTap: () => widget.onPageSelected(page),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: isCurrent ? 68.0 : 48.0,
          height: isCurrent ? 96.0 : 68.0,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: isCurrent ? widget.accent : context.scheme.hairStrong,
              width: isCurrent ? 2 : 0.5,
            ),
            boxShadow: isCurrent ? [BoxShadow(color: widget.accent.withValues(alpha: 0.3), blurRadius: 8)] : null,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: Stack(
              children: [
                Positioned.fill(
                  child: _localThumb(context, page) ?? CachedNetworkImage(httpHeaders: imageHeadersOf(context), 
                    imageUrl: widget.pageUrlBuilder(page),
                    fit: BoxFit.cover,
                    // Decode at thumb size: full pages would evict the
                    // reader's own pages from the image cache on a fling.
                    memCacheWidth:
                        (68 * MediaQuery.devicePixelRatioOf(context)).round(),
                    placeholder: (_, _) => const ShimmerBox(width: double.infinity, height: double.infinity, radius: 3),
                    errorWidget: (_, _, _) => Container(color: context.scheme.s2),
                  ),
                ),
                if (isChapterStart)
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: Container(height: 3, color: AppTheme.amber),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSliderTrack() {
    final displayValue = widget.totalPages > 1 ? widget.currentPage.toDouble() : 0.0;

    return Row(
      children: [
        PageJumpPill(
          currentPage: _activePage,
          totalPages: widget.totalPages,
          onJump: widget.onPageSelected,
          accent: widget.accent,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: SliderTheme(
            data: SliderThemeData(
              trackHeight: 4,
              activeTrackColor: widget.accent,
              inactiveTrackColor: context.scheme.hairStrong,
              thumbColor: widget.accent,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 9),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 18),
              overlayColor: widget.accent.withValues(alpha: 0.15),
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                return Stack(
                  children: [
                    // Chapter ticks: thin full-height amber lines (matches
                    // the amber chapter-start stripe on the thumbnails),
                    // painted behind bookmark ticks so bookmarks stay
                    // prominent.
                    for (final page in widget.chapterPages)
                      Positioned(
                        left: bookmarkTickOffset(
                              page: page,
                              totalPages: widget.totalPages,
                              trackWidth: constraints.maxWidth,
                            ) -
                            1,
                        top: 0,
                        bottom: 0,
                        child: IgnorePointer(
                          child: Container(width: 2, color: AppTheme.amber),
                        ),
                      ),
                    // Bookmark ticks, painted behind the thumb.
                    for (final page in widget.bookmarkPages)
                      Positioned(
                        left: bookmarkTickOffset(
                              page: page,
                              totalPages: widget.totalPages,
                              trackWidth: constraints.maxWidth,
                            ) -
                            1.5, // - half the 3px tick width to center it on the page position
                        top: 0,
                        bottom: 0,
                        child: Center(
                          child: IgnorePointer(
                            child: Container(
                              width: 3,
                              height: 14,
                              decoration: BoxDecoration(
                                color: widget.accent,
                                borderRadius: BorderRadius.circular(1.5),
                              ),
                            ),
                          ),
                        ),
                      ),
                    Slider(
                      value: _isDragging ? _dragValue : displayValue,
                      min: 0,
                      max: _maxValue,
                      onChangeStart: (value) {
                        setState(() { _isDragging = true; _dragValue = value; _lastHapticPage = value.round(); });
                      },
                      onChanged: (value) {
                        final newPage = value.round();
                        setState(() => _dragValue = value);
                        if (newPage != _lastHapticPage) {
                          HapticFeedback.selectionClick();
                          _lastHapticPage = newPage;
                          WidgetsBinding.instance.addPostFrameCallback((_) => _centre(animate: false));
                        }
                      },
                      onChangeEnd: (value) {
                        final page = value.round();
                        setState(() => _isDragging = false);
                        widget.onPageSelected(page);
                      },
                    ),
                  ],
                );
              },
            ),
          ),
        ),
        if (widget.onOpenGrid != null) ...[
          GestureDetector(
            key: const Key('filmstripScrubber.gridButton'),
            onTap: widget.onOpenGrid,
            behavior: HitTestBehavior.opaque,
            // 44pt touch target around the 18pt glyph.
            child: SizedBox.square(
              dimension: 44,
              child: Icon(Icons.grid_view, size: 18, color: context.scheme.t2),
            ),
          ),
        ],
      ],
    );
  }
}
