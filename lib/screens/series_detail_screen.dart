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
