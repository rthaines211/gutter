import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final manifest = File('android/app/src/main/AndroidManifest.xml').readAsStringSync();

  test('release can reach plain-http self-hosted servers', () {
    // debug/profile manifests add INTERNET; release only has main's.
    expect(manifest, contains('android.permission.INTERNET'));
    expect(manifest, contains('android:networkSecurityConfig="@xml/network_security_config"'));
    final config = File('android/app/src/main/res/xml/network_security_config.xml').readAsStringSync();
    expect(config, matches(RegExp(r'<base-config[^>]*cleartextTrafficPermitted="true"')));
  });

  test('downloads stay out of Auto Backup', () {
    for (final f in ['backup_rules.xml', 'data_extraction_rules.xml']) {
      expect(File('android/app/src/main/res/xml/$f').readAsStringSync(),
          contains('path="app_flutter/downloads/"'), reason: f);
    }
  });

  test('store identity and predictive back', () {
    expect(manifest, contains('android:label="Gutter"'));
    expect(manifest, contains('android:enableOnBackInvokedCallback="true"'));
    expect(File('android/app/build.gradle.kts').readAsStringSync(),
        contains('applicationId = "com.ryanhaines.gutter"'));
  });
}
