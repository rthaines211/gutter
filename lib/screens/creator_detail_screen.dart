// lib/screens/creator_detail_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../config/app_theme.dart';
import '../config/scheme.dart';
import '../providers/accent_provider.dart';
import '../widgets/creator_detail_panel.dart';

class CreatorDetailScreen extends ConsumerWidget {
  final int creatorId;
  final String name;

  const CreatorDetailScreen({super.key, required this.creatorId, required this.name});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accent = ref.watch(accentProvider).value ?? AppTheme.accent;
    return Scaffold(
      backgroundColor: context.scheme.bg,
      appBar: AppBar(backgroundColor: context.scheme.bg),
      body: CreatorDetailPanel(creatorId: creatorId, name: name, accent: accent),
    );
  }
}
