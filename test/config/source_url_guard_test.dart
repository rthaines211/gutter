import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Covers and pages must come from `SourceUrls` so Komga sources get their
/// own layout. Gutter-server-only screens (hidden on Komga) are exempt.
void main() {
  const exempt = {
    'arc_common.dart', 'arc_detail_screen.dart', 'arcs_screen.dart',
    'creators_screen.dart', 'creator_detail_panel.dart', 'creator_detail_screen.dart',
    'review_screen.dart', 'remote_screen.dart', 'stats_dashboard.dart',
    'stats_history_list.dart',
  };
  final hardcoded = RegExp(r"""/comics/\$\{?[\w.]+\}?/(cover|pages/)|/library/\$\{?[\w.()]+\}?/cover""");

  test('store-visible widgets build no Gutter-only image URLs', () {
    final offenders = [
      for (final dir in ['lib/widgets', 'lib/screens'])
        for (final f in Directory(dir).listSync(recursive: true).whereType<File>())
          if (f.path.endsWith('.dart') &&
              !exempt.contains(f.uri.pathSegments.last) &&
              hardcoded.hasMatch(f.readAsStringSync()))
            f.path,
    ];
    expect(offenders, isEmpty);
  });
}
