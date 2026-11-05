import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../config/app_theme.dart';
import '../config/scheme.dart';
import '../models/series.dart';

/// End-of-issue "what's next" card — Direction A (Spotlight).
///
/// Drop-in replacement for the original [EndCard]: identical constructor,
/// inputs and callbacks, and the same widget keys
/// (`endcard.next`, `endcard.backToSeries`, `endcard.close`).
///
/// Visual language follows [AppTheme]: OLED ground, an ambient blurred-cover
/// wash, SF-Mono micro-labels, a green completion check and the theme accent
/// for the next-up emphasis. Lays out as a two-column landscape hero on wide
/// surfaces (iPad) and stacks on narrow ones (iPhone / portrait). When there
/// is no next issue it shows a centered "caught up" beat instead.
/// The end card paints a radial vignette down to PURE BLACK (see the
/// DecoratedBox below), so its text is not on a scheme surface and must stay
/// light in every theme. Scheme text tokens would be dark brown in Sepia —
/// invisible here. Do not "fix" these back to `context.scheme.*`.
const _onScrim = Color(0xFFFFFFFF);
const _onScrimSecondary = Color(0xB3EBEBF5);
const _onScrimTertiary = Color(0x6BEBEBF5);

class EndCard extends StatefulWidget {
  final String currentIssueTitle;
  final String currentSeriesName;
  final String currentCoverUrl;
  final int readCount;
  final int totalCount;
  final SeriesIssue? nextIssue;
  final VoidCallback onNext;
  final VoidCallback onBackToSeries;
  final VoidCallback onClose;

  /// Offline, when the next issue in order isn't downloaded: says so
  /// ("#15 isn't on this iPad"). [nextIssue] is then the next one that is.
  final String? offlineNote;

  const EndCard({
    super.key,
    required this.currentIssueTitle,
    required this.currentSeriesName,
    required this.currentCoverUrl,
    required this.readCount,
    required this.totalCount,
    required this.nextIssue,
    required this.onNext,
    required this.onBackToSeries,
    required this.onClose,
    this.offlineNote,
  });

  @override
  State<EndCard> createState() => _EndCardState();
}

class _EndCardState extends State<EndCard> with SingleTickerProviderStateMixin {
  // Wide enough to split into the two-column hero.
  static const double _wideBreakpoint = 720;

  late final AnimationController _controller;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 340),
    );
    final curve = CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic);
    _fade = curve;
    _slide = Tween<Offset>(
      begin: const Offset(0, 0.03),
      end: Offset.zero,
    ).animate(curve);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_controller.isAnimating || _controller.value > 0) return;
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      _controller.value = 1;
    } else {
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Color get _accent => Theme.of(context).colorScheme.primary;
  bool get _hasNext => widget.nextIssue != null;

  double get _progress =>
      widget.totalCount > 0 ? (widget.readCount / widget.totalCount).clamp(0.0, 1.0) : 0.0;

  // ── Type helpers ──────────────────────────────────────────────────────────
  TextStyle _mono({double size = 11, Color? color, double spacing = 1.2, FontWeight weight = FontWeight.w600}) {
    return TextStyle(
      fontFamily: '.SF Mono',
      fontFamilyFallback: const ['JetBrains Mono', 'monospace'],
      fontSize: size,
      height: 1.3,
      letterSpacing: spacing,
      fontWeight: weight,
      color: color ?? _onScrimTertiary,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: context.scheme.bg,
      child: Stack(
        children: [
          _backdrop(),
          // Close affordance — mirrors the reader chrome.
          Positioned(
            top: 0,
            right: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: _closeButton(),
              ),
            ),
          ),
          SafeArea(
            child: FadeTransition(
              opacity: _fade,
              child: SlideTransition(
                position: _slide,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final wide = constraints.maxWidth >= _wideBreakpoint;
                    final twoColumn = wide && _hasNext;
                    return Center(
                      child: SingleChildScrollView(
                        padding: EdgeInsets.symmetric(
                          horizontal: wide ? 64 : 28,
                          vertical: 48,
                        ),
                        child: twoColumn ? _twoColumnHero() : _stacked(wide),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
          // Footer secondary action (two-column only; stacked keeps it inline).
          if (_hasNext)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: SafeArea(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    if (constraints.maxWidth < _wideBreakpoint) {
                      return const SizedBox.shrink();
                    }
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 24),
                      child: Center(child: _backToSeriesButton(primary: false)),
                    );
                  },
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ── Backdrop: the just-finished cover, blurred into the OLED void ──────────
  Widget _backdrop() {
    return Positioned.fill(
      child: ClipRect(
        child: Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(color: context.scheme.bg),
            if (widget.currentCoverUrl.isNotEmpty)
              Opacity(
                opacity: 0.42,
                child: ImageFiltered(
                  imageFilter: ui.ImageFilter.blur(sigmaX: 60, sigmaY: 60),
                  child: Transform.scale(
                    scale: 1.3,
                    child: CachedNetworkImage(
                      imageUrl: widget.currentCoverUrl,
                      fit: BoxFit.cover,
                      placeholder: (_, _) => const SizedBox.shrink(),
                      errorWidget: (_, _, _) => const SizedBox.shrink(),
                    ),
                  ),
                ),
              ),
            // Radial vignette down to pure black so content stays legible.
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(0, -0.45),
                  radius: 1.1,
                  colors: [
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.5),
                    Colors.black,
                  ],
                  stops: const [0.0, 0.58, 1.0],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Layouts ────────────────────────────────────────────────────────────────
  Widget _twoColumnHero() {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 920),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Align(
                alignment: Alignment.centerRight,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 360),
                  child: _finishedBlock(),
                ),
              ),
            ),
            Container(
              width: 1,
              margin: const EdgeInsets.symmetric(horizontal: 56, vertical: 8),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    context.scheme.hairStrong,
                    context.scheme.hairStrong,
                    Colors.transparent,
                  ],
                  stops: const [0.0, 0.25, 0.75, 1.0],
                ),
              ),
            ),
            Expanded(
              child: Align(
                alignment: Alignment.centerLeft,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 380),
                  child: _upNextBlock(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _stacked(bool wide) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 520),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _finishedBlock(),
          const SizedBox(height: 28),
          _horizontalRule(),
          const SizedBox(height: 28),
          if (_hasNext) ...[
            _upNextBlock(),
            const SizedBox(height: 16),
            _backToSeriesButton(primary: false),
          ] else
            _caughtUpBlock(),
        ],
      ),
    );
  }

  Widget _horizontalRule() => Container(
        height: 1,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Colors.transparent,
              context.scheme.hairStrong,
              Colors.transparent,
            ],
          ),
        ),
      );

  // ── Blocks ──────────────────────────────────────────────────────────────────
  Widget _finishedBlock() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _completeBadge(),
        const SizedBox(height: 22),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _cover(widget.currentCoverUrl, width: 84, height: 126),
            const SizedBox(width: 18),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.currentIssueTitle,
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.6,
                        height: 1.07,
                        color: _onScrim,
                      ),
                    ),
                    const SizedBox(height: 7),
                    Text(
                      widget.currentSeriesName,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: _onScrimSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 22),
        _progressMeter(),
      ],
    );
  }

  Widget _upNextBlock() {
    final next = widget.nextIssue!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('UP NEXT', style: _mono(size: 12, color: _accent, spacing: 2, weight: FontWeight.w700)),
        if (widget.offlineNote != null) ...[
          const SizedBox(height: 8),
          Text('${widget.offlineNote} · next on this iPad:',
              style: TextStyle(fontSize: 13, color: _onScrimSecondary)),
        ],
        const SizedBox(height: 18),
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            _cover(next.coverUrl, width: 112, height: 168, isNew: true),
            const SizedBox(width: 18),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    next.name,
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.5,
                      height: 1.1,
                      color: _onScrim,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    widget.currentSeriesName,
                    style: TextStyle(fontSize: 13, color: _onScrimTertiary),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        _nextButton(),
      ],
    );
  }

  Widget _caughtUpBlock() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 84,
          height: 84,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: _accent.withValues(alpha: 0.12),
            border: Border.all(color: _accent.withValues(alpha: 0.4)),
            boxShadow: [
              BoxShadow(color: _accent.withValues(alpha: 0.25), blurRadius: 40),
            ],
          ),
          child: Icon(
              widget.offlineNote != null
                  ? Icons.cloud_off_rounded
                  : Icons.auto_awesome,
              size: 34,
              color: _accent),
        ),
        const SizedBox(height: 16),
        Text(
          widget.offlineNote ?? "You're all caught up",
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.5,
            color: _onScrim,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          widget.offlineNote != null
              ? 'DOWNLOAD IT WHEN YOU\'RE BACK ONLINE'
              : 'ALL ${widget.totalCount} ISSUES READ · ${widget.currentSeriesName.toUpperCase()}',
          textAlign: TextAlign.center,
          style: _mono(size: 11, color: _onScrimSecondary, spacing: 1.2),
        ),
        const SizedBox(height: 22),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 300),
          child: _backToSeriesButton(primary: true),
        ),
      ],
    );
  }

  // ── Pieces ────────────────────────────────────────────────────────────────
  Widget _completeBadge() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 22,
          height: 22,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppTheme.green.withValues(alpha: 0.16),
            border: Border.all(color: AppTheme.green.withValues(alpha: 0.5)),
          ),
          child: const Icon(Icons.check_rounded, size: 13, color: AppTheme.green),
        ),
        const SizedBox(width: 10),
        Text('ISSUE COMPLETE', style: _mono(size: 12, color: _onScrimSecondary, spacing: 1.6)),
      ],
    );
  }

  Widget _progressMeter() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('SERIES PROGRESS', style: _mono(size: 11)),
            Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: '${widget.readCount}',
                    style: _mono(size: 12, color: _onScrim, spacing: 0.4, weight: FontWeight.w700),
                  ),
                  TextSpan(
                    text: ' / ${widget.totalCount}',
                    style: _mono(size: 12, color: _onScrimSecondary, spacing: 0.4),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 9),
        ClipRRect(
          borderRadius: BorderRadius.circular(AppTheme.pill),
          child: LinearProgressIndicator(
            value: _progress,
            minHeight: 5,
            backgroundColor: context.scheme.hair,
            valueColor: AlwaysStoppedAnimation<Color>(_accent),
          ),
        ),
        const SizedBox(height: 9),
        Text('${(_progress * 100).round()}% OF SERIES READ', style: _mono(size: 10.5)),
      ],
    );
  }

  Widget _cover(String url, {required double width, required double height, bool isNew = false}) {
    final image = Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: context.scheme.hair, width: 0.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.55),
            blurRadius: 24,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: url.isEmpty
          ? ColoredBox(color: context.scheme.s3)
          : CachedNetworkImage(
              imageUrl: url,
              fit: BoxFit.cover,
              placeholder: (_, _) => ColoredBox(color: context.scheme.s2),
              errorWidget: (_, _, _) => ColoredBox(color: context.scheme.s3),
            ),
    );

    if (!isNew) return image;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        image,
        Positioned(
          top: -4,
          right: -4,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            decoration: BoxDecoration(
              color: _accent,
              borderRadius: BorderRadius.circular(AppTheme.pill),
              boxShadow: [BoxShadow(color: _accent.withValues(alpha: 0.5), blurRadius: 10)],
            ),
            child: Text('NEW', style: _mono(size: 9, color: Scheme.onAccent(_accent), spacing: 0.6, weight: FontWeight.w700)),
          ),
        ),
      ],
    );
  }

  // ── Buttons (keys preserved for tests) ──────────────────────────────────────
  Widget _nextButton() {
    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        key: const Key('endcard.next'),
        onPressed: widget.onNext,
        icon: const Icon(Icons.play_arrow_rounded, size: 20),
        label: const Text('Next issue'),
        style: FilledButton.styleFrom(
          backgroundColor: _accent,
          foregroundColor: Scheme.onAccent(_accent),
          minimumSize: const Size(0, 54),
          padding: const EdgeInsets.symmetric(horizontal: 26),
          shape: const StadiumBorder(),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, letterSpacing: -0.2),
        ),
      ),
    );
  }

  Widget _backToSeriesButton({required bool primary}) {
    final label = const Text('Back to series');
    final icon = const Icon(Icons.menu_book_rounded, size: 18);
    if (primary) {
      return SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          key: const Key('endcard.backToSeries'),
          onPressed: widget.onBackToSeries,
          icon: icon,
          label: label,
          style: FilledButton.styleFrom(
            backgroundColor: _accent,
            foregroundColor: Scheme.onAccent(_accent),
            minimumSize: const Size(0, 54),
            padding: const EdgeInsets.symmetric(horizontal: 26),
            shape: const StadiumBorder(),
            textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, letterSpacing: -0.2),
          ),
        ),
      );
    }
    return OutlinedButton.icon(
      key: const Key('endcard.backToSeries'),
      onPressed: widget.onBackToSeries,
      icon: icon,
      label: label,
      style: OutlinedButton.styleFrom(
        foregroundColor: _onScrim,
        backgroundColor: context.scheme.borderFaint,
        side: BorderSide(color: context.scheme.hairStrong, width: 0.5),
        minimumSize: const Size(0, 46),
        padding: const EdgeInsets.symmetric(horizontal: 20),
        shape: const StadiumBorder(),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, letterSpacing: -0.2),
      ),
    );
  }

  Widget _closeButton() {
    return TextButton.icon(
      key: const Key('endcard.close'),
      onPressed: widget.onClose,
      icon: Icon(Icons.close_rounded, size: 14, color: _onScrimSecondary),
      label: const Text('Close'),
      style: TextButton.styleFrom(
        foregroundColor: _onScrimSecondary,
        backgroundColor: const Color(0x99141418),
        padding: const EdgeInsets.fromLTRB(10, 8, 13, 8),
        shape: StadiumBorder(side: BorderSide(color: context.scheme.hair, width: 0.5)),
        textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
      ),
    );
  }
}
