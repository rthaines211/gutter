import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

/// Marks an issue's cover on screen so [readerRoute] can fly it into the
/// reader. Wrap the cover image (inside its clip) with the comic id and the
/// URL it shows, so the flight reuses the cached image.
class CoverAnchor extends StatefulWidget {
  final String comicId;
  final String imageUrl;

  /// Corner radius of the cover where it sits; the flight squares it off.
  final double radius;
  final Widget child;

  const CoverAnchor({
    super.key,
    required this.comicId,
    required this.imageUrl,
    this.radius = 4,
    required this.child,
  });

  // ponytail: a flat list, scanned on open; fine for a screen's worth of tiles.
  static final _anchors = <_CoverAnchorState>[];

  /// The visible anchor for [comicId]: mounted on the current route, in the
  /// shown tab (IndexedStack turns tickers off in hidden ones) and on screen.
  static _CoverAnchorState? _find(String comicId, Size screen) {
    for (final a in _anchors.reversed) {
      if (a.widget.comicId != comicId || !a.mounted) continue;
      if (ModalRoute.of(a.context)?.isCurrent == false) continue;
      if (!TickerMode.valuesOf(a.context).enabled) continue;
      final rect = a.rect;
      if (rect == null || !rect.overlaps(Offset.zero & screen)) continue;
      return a;
    }
    return null;
  }

  @override
  State<CoverAnchor> createState() => _CoverAnchorState();
}

class _CoverAnchorState extends State<CoverAnchor> {
  Rect? get rect {
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize || !box.attached) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  @override
  void initState() {
    super.initState();
    CoverAnchor._anchors.add(this);
  }

  @override
  void dispose() {
    CoverAnchor._anchors.remove(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Passed from the cover flight to the reader underneath it. The reader calls
/// [ready] once its first page can be shown; [shown] completes when the
/// flight has cross-faded from the cover to that page.
class CoverReveal {
  final _ready = Completer<void>();
  final _shown = Completer<void>();

  /// Safe to call during build, and more than once.
  void ready() {
    if (!_ready.isCompleted) _ready.complete();
  }

  Future<void> get shown => _shown.future;

  static CoverReveal? of(BuildContext context) =>
      context.getInheritedWidgetOfExactType<_RevealScope>()?.reveal;
}

class _RevealScope extends InheritedWidget {
  final CoverReveal reveal;
  const _RevealScope({required this.reveal, required super.child});

  @override
  bool updateShouldNotify(_RevealScope old) => false;
}

const _flight = 380; // cover flies to the page rect as the ground goes black
const _crossfade = 160; // cover hands over to the reader's first page
const _back = 420; // closing: the cover flies home as the reader fades off it
const _backFade = 0.35; // share of the close spent fading the reader out
// ponytail: if the reader never reports, show it anyway rather than hold the cover.
const _holdLimit = Duration(seconds: 4);

/// The route into the reader. When the issue's cover is on screen
/// ([CoverAnchor]) it flies to where the page will sit as the ground goes
/// black, and holds there while the reader loads underneath; once the reader's
/// first page is ready ([CoverReveal]) the cover cross-fades to it. Closing
/// runs it back. With no anchor, or Reduce Motion on, the reader cross-fades.
Route<T> readerRoute<T>(
  BuildContext context, {
  required String comicId,
  required WidgetBuilder builder,
}) {
  final media = MediaQuery.of(context);
  final reduce = media.disableAnimations;
  final anchor = reduce ? null : CoverAnchor._find(comicId, media.size);
  final from = anchor?.rect;
  const settings = RouteSettings(name: '/reader');

  if (anchor == null || from == null) {
    return PageRouteBuilder<T>(
      settings: settings,
      transitionDuration: const Duration(milliseconds: 300),
      reverseTransitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (context, _, _) => builder(context),
      transitionsBuilder: (_, animation, _, child) => FadeTransition(
        opacity: CurvedAnimation(parent: animation, curve: Curves.easeInOut),
        child: child,
      ),
    );
  }

  final reveal = CoverReveal();
  final image = CachedNetworkImageProvider(anchor.widget.imageUrl);
  return PageRouteBuilder<T>(
    settings: settings,
    transitionDuration: const Duration(milliseconds: _flight),
    reverseTransitionDuration: const Duration(milliseconds: _back),
    pageBuilder: (context, _, _) =>
        _RevealScope(reveal: reveal, child: builder(context)),
    transitionsBuilder: (context, animation, _, child) => _CoverFlight(
      comicId: comicId,
      animation: animation,
      reveal: reveal,
      from: from,
      image: image,
      radius: anchor.widget.radius,
      child: child,
    ),
  );
}

class _CoverFlight extends StatefulWidget {
  final String comicId;
  final Animation<double> animation;
  final CoverReveal reveal;
  final Rect from;
  final ImageProvider image;
  final double radius;
  final Widget child;

  const _CoverFlight({
    required this.comicId,
    required this.animation,
    required this.reveal,
    required this.from,
    required this.image,
    required this.radius,
    required this.child,
  });

  @override
  State<_CoverFlight> createState() => _CoverFlightState();
}

class _CoverFlightState extends State<_CoverFlight>
    with SingleTickerProviderStateMixin {
  late final _fade = AnimationController(
      vsync: this, duration: const Duration(milliseconds: _crossfade));
  late final _fly = CurvedAnimation(
    parent: widget.animation,
    curve: const Cubic(0.2, 0, 0, 1),
    // Leaves the page briskly and settles into the tile.
    reverseCurve: const Cubic(0.2, 0, 0, 1).flipped,
  );

  /// Where the cover flies home to, looked up when closing starts: reading
  /// reorders shelves and rotation moves tiles, so the open rect is stale.
  /// Null with no tile on screen: the cover fades out where it is instead.
  Rect? _home;
  bool _closing = false;

  void _onStatus(AnimationStatus s) {
    if (s != AnimationStatus.reverse || _closing) return;
    _closing = true;
    // After this frame the route below is current and on stage again.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _home = CoverAnchor._find(widget.comicId, MediaQuery.sizeOf(context))?.rect;
    });
  }

  late final Timer _hold;

  @override
  void initState() {
    super.initState();
    widget.animation.addStatusListener(_onStatus);
    _hold = Timer(_holdLimit, widget.reveal.ready);
    Future.wait([widget.reveal._ready.future, _landed()]).then((_) {
      _hold.cancel();
      if (!mounted) return;
      _fade.forward().whenComplete(() {
        if (!widget.reveal._shown.isCompleted) widget.reveal._shown.complete();
      });
    });
  }

  /// Completes when the flight has landed (it may already have).
  Future<void> _landed() {
    final a = widget.animation;
    if (a.isCompleted) return Future.value();
    final done = Completer<void>();
    void listener(AnimationStatus s) {
      if (s != AnimationStatus.completed) return;
      a.removeStatusListener(listener);
      done.complete();
    }
    a.addStatusListener(listener);
    return done.future;
  }

  @override
  void dispose() {
    widget.animation.removeStatusListener(_onStatus);
    _hold.cancel();
    _fly.dispose();
    _fade.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    final from = widget.from;
    // Where the page lands: the cover's aspect, contained in the screen
    // (the reader renders BoxFit.contain before any fit-mode zoom).
    final to = Alignment.center.inscribe(
      applyBoxFit(BoxFit.contain, from.size, screen).destination,
      Offset.zero & screen,
    );
    return AnimatedBuilder(
      animation: Listenable.merge([widget.animation, _fade]),
      // Same three children every frame, so the reader is never remounted.
      child: widget.child,
      builder: (context, child) {
        final t = _fly.value;
        final home = _closing ? _home : from;
        final r = home == null ? to : Rect.lerp(home, to, t)!;
        // Closing fades the reader out first, then the cover flies home.
        final out = const Interval(1 - _backFade, 1)
            .transform(widget.animation.value);
        final readerOpacity = _fade.value < out ? _fade.value : out;
        final settled = widget.animation.isCompleted && _fade.isCompleted;
        return Stack(
          children: [
            Positioned.fill(
              child: ColoredBox(
                  color: Colors.black.withValues(alpha: widget.animation.value)),
            ),
            Positioned.fromRect(
              rect: r,
              child: Visibility(
                visible: !settled,
                child: Opacity(
                  opacity: home == null ? widget.animation.value : 1,
                  child: ClipRRect(
                  borderRadius: BorderRadius.circular(widget.radius * (1 - t)),
                  child: Image(
                    image: widget.image,
                    fit: BoxFit.cover,
                    gaplessPlayback: true,
                    errorBuilder: (_, _, _) => const SizedBox.shrink(),
                  ),
                ),
                ),
              ),
            ),
            Positioned.fill(
              child: Opacity(opacity: readerOpacity, child: child),
            ),
          ],
        );
      },
    );
  }
}
