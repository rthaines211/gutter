import 'package:flutter/material.dart';
import '../config/scheme.dart';

/// The App Store's privacy-policy URL; PRIVACY.md holds the same text.
const privacyPolicyUrl =
    'https://github.com/rthaines211/gutter/blob/main/PRIVACY.md';

const privacyPolicyText =
    'Gutter collects no data. It talks only to the servers you add, keeps '
    'its settings, reading progress and downloads on your device, and has no '
    'analytics, ads or tracking. Nothing is sent to the developer.\n\n'
    'Questions or problems: open an issue at '
    'https://github.com/rthaines211/gutter/issues';

/// The policy shown in-app (More → Privacy), as App Review requires.
class PrivacySheet extends StatelessWidget {
  const PrivacySheet({super.key});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Privacy', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            const SelectableText(privacyPolicyText),
            const SizedBox(height: 16),
            SelectableText(privacyPolicyUrl, style: context.monoCaption),
          ],
        ),
      ),
    );
  }
}
