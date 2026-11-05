import 'package:flutter/material.dart';
import '../config/app_theme.dart';

/// Small amber dot used as an always-visible offline indicator on nav surfaces.
class OfflineDot extends StatelessWidget {
  const OfflineDot({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 8,
      height: 8,
      decoration: const BoxDecoration(
        color: AppTheme.amber,
        shape: BoxShape.circle,
      ),
    );
  }
}
