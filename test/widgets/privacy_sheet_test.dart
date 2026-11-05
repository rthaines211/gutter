import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:comic_reader_app/widgets/privacy_sheet.dart';

void main() {
  testWidgets('privacy sheet shows the policy and where it lives',
      (t) async {
    await t.pumpWidget(const MaterialApp(home: Scaffold(body: PrivacySheet())));
    expect(find.textContaining('collects no data'), findsOneWidget);
    expect(find.textContaining(privacyPolicyUrl), findsOneWidget);
  });

  test('PRIVACY.md carries the same policy text', () {
    // App Store Connect links to PRIVACY.md; the in-app sheet must not drift.
    expect(File('PRIVACY.md').readAsStringSync(), contains(privacyPolicyText));
  });
}
