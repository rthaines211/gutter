import 'package:flutter/material.dart';
import '../config/app_theme.dart';
import '../config/scheme.dart';

class RecapScreen extends StatelessWidget {
  final String seriesId;

  const RecapScreen({super.key, required this.seriesId});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.scheme.bg,
      appBar: AppBar(
        title: const Text('Previously On'),
        backgroundColor: Colors.transparent,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.auto_stories_outlined,
                  size: 64, color: context.scheme.t3),
              const SizedBox(height: 16),
              const Text('Recap coming soon',
                  style: AppTheme.titleMedium),
              const SizedBox(height: 8),
              Text('Series: $seriesId',
                  style: TextStyle(color: context.scheme.t3)),
            ],
          ),
        ),
      ),
    );
  }
}
