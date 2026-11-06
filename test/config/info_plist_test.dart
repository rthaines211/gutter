import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('ATS allows plain-http self-hosted servers', () {
    final plist = File('ios/Runner/Info.plist').readAsStringSync();
    final ats = RegExp(r'<key>NSAppTransportSecurity</key>\s*<dict>(.*?)</dict>', dotAll: true)
        .firstMatch(plist)!
        .group(1)!;
    expect(ats, matches(RegExp(r'<key>NSAllowsArbitraryLoads</key>\s*<true/>')));
    // Any other ATS key makes iOS ignore NSAllowsArbitraryLoads.
    expect(RegExp(r'<key>').allMatches(ats), hasLength(1));
  });
}
