import 'dart:io';
import '../providers/providers.dart';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:path/path.dart' as p;
import 'zoom_wrapper.dart';
import '../services/page_prefetcher.dart';

class ScrollReader extends StatefulWidget {
  final int pageCount;
  final String Function(int page) pageUrlBuilder;
  final ScrollController? scrollController;
  final PagePrefetcher? prefetcher;
  final bool rtl;

  /// If set, pages are read from this local directory instead of network URLs.
  final String? localPagesPath;

  /// When non-null, an extra virtual page is appended at index pageCount.
  /// Used to render an end-of-issue card. Mirrors PageReader's endCardBuilder.
  final WidgetBuilder? endCardBuilder;

  /// Called when the page covering the top of the view changes.
  final ValueChanged<int>? onPageChanged;

  /// If > 0 and no external scrollController is supplied, the list opens
  /// with this page at the top.
  final int initialPage;

  /// Width / height of a page not loaded yet. Its placeholder takes that
  /// shape so pages above don't shift what's on screen as they load.
  final double pageAspect;

  const ScrollReader({
    super.key,
    required this.pageCount,
    required this.pageUrlBuilder,
    this.scrollController,
    this.prefetcher,
    this.rtl = false,
    this.localPagesPath,
    this.endCardBuilder,
    this.onPageChanged,
    this.initialPage = 0,
    this.pageAspect = 2 / 3,
  });

  @override
  State<ScrollReader> createState() => _ScrollReaderState();
}

class _ScrollReaderState extends State<ScrollReader> {
  int _lastPrefetchedPage = -1;
  int _lastReportedPage = -1;
  ScrollController? _internalController;

  /// Built pages' keys, so the page at the top is read from real layout
  /// (pages are fit-width, often taller than the screen) rather than guessed.
  final Map<int, GlobalKey> _keys = {};
  final GlobalKey _viewKey = GlobalKey();

  /// Local page files by name ('001' → 001.jpg), listed once per directory
  /// instead of on every page build.
  (String, Map<String, File>)? _localFiles;

  ScrollController get _effectiveController =>
      widget.scrollController ?? (_internalController ??= ScrollController());

  @override
  void initState() {
    super.initState();
    if (widget.scrollController == null && widget.initialPage > 0) {
      // Only built pages have a layout: jump near the page using the
      // placeholder height, then pin it to the top once it's built.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final pos = _effectiveController.position;
        final pageHeight = (context.size?.width ?? 0) / widget.pageAspect;
        if (pageHeight > 0) {
          _effectiveController.jumpTo(
            (widget.initialPage * pageHeight).clamp(0.0, pos.maxScrollExtent),
          );
        }
        _pinInitialPage(3);
      });
    }
  }

  bool _topCheckScheduled = false;

  void _scheduleTopCheck() {
    if (_topCheckScheduled) return;
    _topCheckScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _topCheckScheduled = false;
      if (!mounted) return;
      if (widget.prefetcher != null) _checkPrefetch(context);
      _checkPageChanged();
    });
  }

  void _pinInitialPage(int tries) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final ctx = _keys[widget.initialPage]?.currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(ctx);
      } else if (tries > 0) {
        _pinInitialPage(tries - 1);
      }
    });
  }

  /// The page covering the top of the view, from the built pages' layout.
  int? _pageAtTop() {
    final view = _viewKey.currentContext?.findRenderObject() as RenderBox?;
    if (view == null || !view.hasSize) return null;
    final top = view.localToGlobal(Offset.zero).dy + 1;
    for (final e in _keys.entries) {
      final box = e.value.currentContext?.findRenderObject() as RenderBox?;
      if (box == null || !box.attached || !box.hasSize) continue;
      final y = box.localToGlobal(Offset.zero).dy;
      if (y <= top && y + box.size.height > top) return e.key;
    }
    return null;
  }

  @override
  void dispose() {
    _internalController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        // The notification comes before the pages it scrolled to are laid
        // out, so read the page at the top once the frame is done.
        if (notification is ScrollUpdateNotification ||
            notification is ScrollEndNotification) {
          _scheduleTopCheck();
        }
        return false;
      },
      child: ListView.builder(
        key: _viewKey,
        controller: _effectiveController,
        itemCount: widget.endCardBuilder != null
            ? widget.pageCount + 1
            : widget.pageCount,
        itemBuilder: (context, index) {
          if (widget.endCardBuilder != null && index == widget.pageCount) {
            return widget.endCardBuilder!(context);
          }
          return ZoomWrapper(
            key: _keys.putIfAbsent(index, GlobalKey.new),
            child: widget.localPagesPath != null
                ? _buildLocalImage(index)
                : CachedNetworkImage(
                    imageUrl: widget.pageUrlBuilder(index),
                    httpHeaders: imageHeadersOf(context, widget.pageUrlBuilder(index)),
                    fit: BoxFit.fitWidth,
                    width: double.infinity,
                    placeholder: (_, _) => AspectRatio(
                      aspectRatio: widget.pageAspect,
                      child: const Center(child: CircularProgressIndicator()),
                    ),
                    errorWidget: (_, _, _) => const SizedBox(
                      height: 200,
                      child: Center(
                        child: Icon(
                          Icons.broken_image,
                          size: 64,
                          color: Colors.grey,
                        ),
                      ),
                    ),
                  ),
          );
        },
      ),
    );
  }

  Widget _buildLocalImage(int index) {
    final dirPath = widget.localPagesPath!;
    if (_localFiles?.$1 != dirPath) {
      Map<String, File> files;
      try {
        files = {
          for (final f in Directory(dirPath).listSync().whereType<File>())
            p.basenameWithoutExtension(f.path): f,
        };
      } catch (_) {
        files = {};
      }
      _localFiles = (dirPath, files);
    }
    final pageFile =
        _localFiles!.$2[(index + 1).toString().padLeft(3, '0')];
    if (pageFile == null) {
      return const SizedBox(
        height: 200,
        child: Center(
          child: Icon(Icons.broken_image, size: 64, color: Colors.grey),
        ),
      );
    }
    return Image.file(pageFile, fit: BoxFit.fitWidth, width: double.infinity);
  }

  void _checkPrefetch(BuildContext context) {
    final controller = _effectiveController;
    if (!controller.hasClients) return;

    final currentPage = _pageAtTop();
    if (currentPage == null) return;

    if (currentPage != _lastPrefetchedPage) {
      _lastPrefetchedPage = currentPage;
      widget.prefetcher?.onPageChanged(
        currentPage: currentPage,
        rtl: widget.rtl,
        context: context,
      );
    }
  }

  void _checkPageChanged() {
    if (widget.onPageChanged == null) return;
    final page = _pageAtTop();
    if (page == null || page >= widget.pageCount) return;
    if (page != _lastReportedPage) {
      _lastReportedPage = page;
      widget.onPageChanged!(page);
    }
  }
}
