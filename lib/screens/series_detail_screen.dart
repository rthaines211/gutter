// lib/screens/series_detail_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../config/app_theme.dart';
import '../config/scheme.dart';
import '../providers/accent_provider.dart';
import '../widgets/series_detail_panel.dart';

class SeriesDetailScreen extends ConsumerWidget {
  final String seriesId;

  /// Opened over a reader (Issue details): opening an issue replaces that
  /// reader instead of stacking a second one on it.
  final bool fromReader;

  /// Pop result telling the reader underneath it is being replaced.
  static const replacedResult = 'replaced';

  const SeriesDetailScreen(
      {super.key, required this.seriesId, this.fromReader = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accent = ref.watch(accentProvider).value ?? AppTheme.accent;
    return Scaffold(
      backgroundColor: context.scheme.bg,
      body: SeriesDetailPanel(
          seriesId: seriesId, accent: accent, fromReader: fromReader),
    );
  }
}

/// The series panel sliding in from the right over the reader (iPad), with
/// the page dimmed behind. Tap the page or the panel's close to dismiss.
/// Opening an issue pops with [SeriesDetailScreen.replacedResult], exactly
/// like the full page, so the reader's return path is unchanged.
/// ponytail: the page dims but doesn't slide left as in the mockup; shift
/// it if the covered strip turns out to matter.
Route<String> seriesSidePanelRoute(String seriesId) => PageRouteBuilder<String>(
      settings: const RouteSettings(name: '/series-panel'),
      opaque: false,
      barrierDismissible: true,
      barrierLabel: 'Close series',
      barrierColor: Colors.black45,
      transitionDuration: const Duration(milliseconds: 260),
      reverseTransitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (context, _, _) => _SeriesSidePanel(seriesId: seriesId),
      transitionsBuilder: (context, animation, _, child) => SlideTransition(
        position: Tween(begin: const Offset(1, 0), end: Offset.zero).animate(
            CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
        child: child,
      ),
    );

class _SeriesSidePanel extends ConsumerWidget {
  final String seriesId;
  const _SeriesSidePanel({required this.seriesId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accent = ref.watch(accentProvider).value ?? AppTheme.accent;
    final size = MediaQuery.sizeOf(context);
    // Same widths as the Library split view, but never narrower than the
    // panel's header row needs (iPad Split View, small windows).
    final base = size.width * (size.width > size.height ? 0.40 : 0.46);
    final width = base < 400 ? 400.0 : base;
    final fitted = width > size.width - 24 ? size.width - 24 : width;
    return Align(
      alignment: Alignment.centerRight,
      child: SafeArea(
        left: false,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppTheme.r18),
            child: SizedBox(
              width: fitted,
              child: Scaffold(
                backgroundColor: context.scheme.bg,
                body: SeriesDetailPanel(
                  seriesId: seriesId,
                  accent: accent,
                  fromReader: true,
                  onClose: () => Navigator.of(context).maybePop(),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
