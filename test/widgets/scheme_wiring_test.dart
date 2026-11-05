import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:comic_reader_app/config/app_theme.dart';
import 'package:comic_reader_app/config/scheme.dart';

void main() {
  testWidgets('context.scheme resolves the scheme from ThemeData', (t) async {
    late Scheme seen;
    await t.pumpWidget(MaterialApp(
      theme: AppTheme.themeData(Scheme.sepiaPaper),
      home: Builder(builder: (context) {
        seen = context.scheme;
        return const SizedBox.shrink();
      }),
    ));
    expect(seen.bg, Scheme.sepiaPaper.bg);
    expect(seen.dark, isFalse);
  });

  testWidgets('scaffold background follows the scheme', (t) async {
    await t.pumpWidget(MaterialApp(
      theme: AppTheme.themeData(Scheme.oledBlack),
      home: const Scaffold(),
    ));
    final scaffold = t.widget<Material>(find.byType(Material).first);
    expect(scaffold.color, Scheme.oledBlack.bg);
  });

  testWidgets('context.scheme falls back to OLED with no extension', (t) async {
    late Scheme seen;
    await t.pumpWidget(MaterialApp(
      theme: ThemeData.dark(),
      home: Builder(builder: (context) {
        seen = context.scheme;
        return const SizedBox.shrink();
      }),
    ));
    expect(seen.bg, Scheme.oledBlack.bg);
  });
}
