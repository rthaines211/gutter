import 'dart:io';
import '../providers/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:path/path.dart' as p;
import 'zoom_wrapper.dart';
import '../services/page_prefetcher.dart';
import '../services/zoom_math.dart';

class PageReader extends StatefulWidget {
  final PageController controller;
  final int pageCount;
  final String Function(int page) pageUrlBuilder;
  final bool rtl;
  final ValueChanged<int> onPageChanged;
  final PagePrefetcher? prefetcher;
  final void Function(int page, int width, int height)? onImageLoaded;

  /// The image provider used for each page, reported once per page. Bubble zoom
  /// resolves it again (an image-cache hit) to cut balloons out of the page.
  final void Function(int page, ImageProvider provider)? onPageProvider;
  final TransformationController? transformationController;
  final bool isZoomed;
  final ValueChanged<bool>? onZoomChanged;

  /// Set of page indices whose transforms are ready (no flash on display).
  final Set<int> readyPages;

  /// Page turn animation mode: 'slide' (default), 'fade', or 'none'.
  final String pageAnimation;

  /// When non-null, an extra virtual page is appended at index pageCount.
  /// Used to render an end-of-issue card. The builder is responsible for
  /// the page's full content — no transforms, no prefetch, no image lifecycle.
  final WidgetBuilder? endCardBuilder;

  /// Called when the InteractiveViewer transform ends (for zoom lock wiring).
  final ValueChanged<Matrix4>? onTransformEnd;

  /// If set, pages are read from this local directory instead of network URLs.
  final String? localPagesPath;

  /// Fires when a page receives an overscroll gesture (drag past edge).
  /// Reader maps this to PanSequenceController advance/retreat.
  final ValueChanged<EdgeDirection>? onOverscroll;

  /// Passed to each page's [ZoomWrapper.allowPan].
  final bool Function()? allowPan;

  /// Computes the display rect for the page at [index] given the current
  /// viewport. Returns null if the page's image dimensions aren't loaded yet.
  /// Used by ZoomWrapper for overscroll detection (no-ops when null).
  final Rect? Function(int index, Size viewport)? displayRectForPage;

  /// Transform the reader will apply to [index] once it becomes current.
  /// Used to draw the incoming fade overlay at its real framing instead of
  /// borrowing the outgoing page's zoom. Null → identity.
  final Matrix4? Function(int index, Size viewport)? landingTransformFor;

  const PageReader({
    super.key,
    required this.controller,
    required this.pageCount,
    required this.pageUrlBuilder,
    required this.rtl,
    required this.onPageChanged,
    this.prefetcher,
    this.onImageLoaded,
    this.onPageProvider,
    this.transformationController,
    this.isZoomed = false,
    this.onZoomChanged,
    this.readyPages = const {},
    this.pageAnimation = 'slide',
    this.endCardBuilder,
    this.onTransformEnd,
    this.localPagesPath,
    this.onOverscroll,
    this.allowPan,
    this.displayRectForPage,
    this.landingTransformFor,
  });

  @override
  State<PageReader> createState() => PageReaderState();
}

class PageReaderState extends State<PageReader>
    with SingleTickerProviderStateMixin {
  AnimationController? _fadeController;
  int _fadingFromPage = 0;
  int _fadingToPage = 0;
  Matrix4 _fadeFromTransform = Matrix4.identity();
  bool _isFading = false;
  bool get isFading => _isFading;

  final Map<int, ({ImageStream stream, ImageStreamListener listener})>
  _imageListeners = {};
  Map<String, List<File>>? _localFileCache;

  @override
  void initState() {
    super.initState();
    _initFadeController();
  }

  @override
  void didUpdateWidget(PageReader oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.pageAnimation != widget.pageAnimation) {
      _disposeFadeController();
      _initFadeController();
    }
    if (oldWidget.localPagesPath != widget.localPagesPath) {
      _localFileCache = null;
    }
  }

  @override
  void dispose() {
    _disposeFadeController();
    for (final entry in _imageListeners.values) {
      entry.stream.removeListener(entry.listener);
    }
    _imageListeners.clear();
    super.dispose();
  }

  void _initFadeController() {
    if (widget.pageAnimation == 'fade') {
      _fadeController = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 300),
      );
    }
  }

  void _disposeFadeController() {
    _fadeController?.dispose();
    _fadeController = null;
  }

  /// Trigger a crossfade to [page]. Called by the parent via a GlobalKey.
  void fadeToPage(int page) {
    if (_fadeController == null) return;
    final currentPage =
        widget.controller.page?.round() ?? widget.controller.initialPage;
    setState(() {
      _fadingFromPage = currentPage;
      _fadingToPage = page;
      _fadeFromTransform =
          widget.transformationController?.value.clone() ?? Matrix4.identity();
      _isFading = true;
    });
    _fadeController!.forward(from: 0).then((_) {
      widget.controller.jumpToPage(page);
      widget.onPageChanged(page);
      widget.prefetcher?.onPageChanged(
        currentPage: page,
        rtl: widget.rtl,
        context: context,
      );
      if (mounted) {
        setState(() {
          _isFading = false;
        });
      }
    });
  }

  ScrollPhysics _physics() {
    if (widget.isZoomed || widget.pageAnimation == 'none') {
      return const NeverScrollableScrollPhysics();
    }
    return const PageScrollPhysics();
  }

  Widget _buildLocalPage(int index) {
    final prefix = (index + 1).toString().padLeft(3, '0');

    // Cache the directory listing to avoid sync I/O on every build
    _localFileCache ??= {};
    final dirPath = widget.localPagesPath!;
    final files = _localFileCache!.putIfAbsent(dirPath, () {
      final dir = Directory(dirPath);
      try {
        return dir.listSync().whereType<File>().toList();
      } catch (_) {
        return [];
      }
    });

    final pageFile = files
        .where((f) => p.basenameWithoutExtension(f.path) == prefix)
        .firstOrNull;

    if (pageFile == null) {
      return const Center(
        child: Icon(Icons.broken_image, size: 64, color: Colors.grey),
      );
    }

    final imageProvider = FileImage(pageFile);

    // Resolve dimensions — manage listener lifecycle
    if (widget.onImageLoaded != null && !_imageListeners.containsKey(index)) {
      widget.onPageProvider?.call(index, imageProvider);
      final listener = ImageStreamListener((info, _) {
        SchedulerBinding.instance.addPostFrameCallback((_) {
          widget.onImageLoaded!(index, info.image.width, info.image.height);
        });
      });
      final stream = imageProvider.resolve(const ImageConfiguration());
      _imageListeners[index] = (stream: stream, listener: listener);
      stream.addListener(listener);
    }

    final ready = widget.readyPages.contains(index);
    return Opacity(
      opacity: ready ? 1.0 : 0.0,
      child: Image(
        image: imageProvider,
        fit: BoxFit.contain,
        width: double.infinity,
        height: double.infinity,
      ),
    );
  }

  /// The page image alone (network or local), filtered, no zoom wrapper.
  Widget _buildPageImage(int index) {
    return widget.localPagesPath != null
        ? _buildLocalPage(index)
        : CachedNetworkImage(httpHeaders: imageHeadersOf(context), 
            imageUrl: widget.pageUrlBuilder(index),
            fit: BoxFit.contain,
            width: double.infinity,
            height: double.infinity,
            imageBuilder: (context, imageProvider) {
              if (widget.onImageLoaded != null &&
                  !_imageListeners.containsKey(index)) {
                widget.onPageProvider?.call(index, imageProvider);
                final listener = ImageStreamListener((info, _) {
                  SchedulerBinding.instance.addPostFrameCallback((_) {
                    widget.onImageLoaded!(
                      index,
                      info.image.width,
                      info.image.height,
                    );
                  });
                });
                final stream = imageProvider.resolve(
                  const ImageConfiguration(),
                );
                _imageListeners[index] = (stream: stream, listener: listener);
                stream.addListener(listener);
              }
              // Hide image until transform is ready to prevent flash
              final ready = widget.readyPages.contains(index);
              return Opacity(
                opacity: ready ? 1.0 : 0.0,
                child: Image(
                  image: imageProvider,
                  fit: BoxFit.contain,
                  width: double.infinity,
                  height: double.infinity,
                ),
              );
            },
            placeholder: (context, url) =>
                const Center(child: CircularProgressIndicator()),
            errorWidget: (context, url, error) => const Center(
              child: Icon(Icons.broken_image, size: 64, color: Colors.grey),
            ),
          );
  }

  Widget _buildPage(int index) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final viewport = Size(constraints.maxWidth, constraints.maxHeight);
        final displayRect = widget.displayRectForPage?.call(index, viewport);
        return ZoomWrapper(
          externalController: widget.transformationController,
          onZoomChanged: widget.onZoomChanged,
          onTransformEnd: widget.onTransformEnd,
          displayRect: displayRect,
          viewportSize: viewport,
          onOverscroll: widget.onOverscroll,
          allowPan: widget.allowPan,
          child: _buildPageImage(index),
        );
      },
    );
  }

  /// A non-interactive copy of [index] for the fade, drawn at a fixed
  /// transform the same way InteractiveViewer would (origin top-left).
  Widget _buildFadeOverlay(
    int index,
    Key key,
    Matrix4 Function(Size viewport) transform,
  ) {
    return IgnorePointer(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final viewport = Size(constraints.maxWidth, constraints.maxHeight);
          return Transform(
            key: key,
            transform: transform(viewport),
            child: _buildPageImage(index),
          );
        },
      ),
    );
  }

  Widget _buildPageView() {
    final hasEndCard = widget.endCardBuilder != null;
    final effectiveCount = hasEndCard ? widget.pageCount + 1 : widget.pageCount;
    return PageView.builder(
      controller: widget.controller,
      reverse: widget.rtl,
      physics: _physics(),
      onPageChanged: (index) {
        if (_isFading) return; // avoid double-fire during fade
        widget.onPageChanged(index);
        // Skip prefetch for the virtual end-card index.
        if (hasEndCard && index == widget.pageCount) return;
        widget.prefetcher?.onPageChanged(
          currentPage: index,
          rtl: widget.rtl,
          context: context,
        );
      },
      itemCount: effectiveCount,
      itemBuilder: (context, index) {
        if (hasEndCard && index == widget.pageCount) {
          return widget.endCardBuilder!(context);
        }
        return _buildPage(index);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.pageAnimation == 'none') {
      return GestureDetector(
        onHorizontalDragEnd: (details) {
          final velocity = details.primaryVelocity ?? 0;
          if (velocity.abs() < 200) return;
          final current =
              widget.controller.page?.round() ?? widget.controller.initialPage;
          // Positive velocity = swipe right (go to previous in LTR, next in RTL)
          final goBack = widget.rtl ? velocity < 0 : velocity > 0;
          if (goBack && current > 0) {
            final target = current - 1;
            widget.controller.jumpToPage(target);
            widget.onPageChanged(target);
            widget.prefetcher?.onPageChanged(
              currentPage: target,
              rtl: widget.rtl,
              context: context,
            );
          } else if (!goBack &&
              current <
                  (widget.endCardBuilder != null
                      ? widget.pageCount
                      : widget.pageCount - 1)) {
            final target = current + 1;
            widget.controller.jumpToPage(target);
            widget.onPageChanged(target);
            // Skip prefetch for the end-card index.
            if (widget.endCardBuilder == null || target != widget.pageCount) {
              widget.prefetcher?.onPageChanged(
                currentPage: target,
                rtl: widget.rtl,
                context: context,
              );
            }
          }
        },
        child: _buildPageView(),
      );
    }

    // The PageView is always child 0 of this Stack. Toggling between a bare
    // PageView and a Stack-wrapped one gave it a new element, which recreated
    // its scroll position at initialPage after every fade — the controller
    // snapped back, the provider→controller sync saw a mismatch and started
    // another fade, forever. A stable tree shape keeps one position alive.
    final fading =
        widget.pageAnimation == 'fade' && _isFading && _fadeController != null;
    return Stack(
      children: [
        _buildPageView(),
        if (fading) ...[
          // Coverage assumption: the overlay pages letterbox on the same
          // background as the PageView, so the underlayer is invisible for
          // loaded pages. A mid-fade swipe can move the underlying PageView,
          // but the _isFading guard in onPageChanged keeps state correct and
          // jumpToPage restores it.
          _buildFadeOverlay(
            _fadingFromPage,
            const Key('reader.fadeFrom'),
            (_) => _fadeFromTransform,
          ),
          FadeTransition(
            opacity: _fadeController!,
            child: _buildFadeOverlay(
              _fadingToPage,
              const Key('reader.fadeTo'),
              (vp) =>
                  widget.landingTransformFor?.call(_fadingToPage, vp) ??
                  Matrix4.identity(),
            ),
          ),
        ],
      ],
    );
  }
}
