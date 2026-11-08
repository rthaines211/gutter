import 'dart:ui';

import 'package:comic_reader_app/config/layout_breakpoint.dart';
import 'package:comic_reader_app/config/platform.dart';
import 'package:comic_reader_app/services/panel_detector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(() => isAndroid = false);

  group('deviceNoun', () {
    testWidgets('iOS: iPad / iPhone', (t) async {
      expect(['iPad', 'iPhone'], contains(LayoutBreakpoint.deviceNoun));
    });

    testWidgets('Android: tablet / phone, never an Apple name', (t) async {
      isAndroid = true;
      expect(['tablet', 'phone'], contains(LayoutBreakpoint.deviceNoun));
    });
  });

  test('Android: no on-device panel model, Pro copy names Google Play', () {
    isAndroid = true;
    expect(onDevicePanels, isFalse);
    expect(storeName, 'Google Play');
    isAndroid = false;
    expect(onDevicePanels, isTrue);
    expect(storeName, 'the App Store');
  });

  testWidgets('Android: detectPanels returns null without calling the channel',
      (t) async {
    isAndroid = true;
    var called = false;
    t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('app.comic_reader/panels'), (_) async {
      called = true;
      return null;
    });
    addTearDown(() => t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('app.comic_reader/panels'), null));
    final img = await t.runAsync(() => createTestImage(width: 64, height: 64));
    expect(await detectPanels(img!), isNull);
    expect(called, isFalse);
  });

  group('splitPanelFraction', () {
    Future<double> fraction(WidgetTester t, Size size,
        {List<DisplayFeature> features = const []}) async {
      late double f;
      await t.pumpWidget(MediaQuery(
        data: MediaQueryData(size: size, displayFeatures: features),
        child: Builder(builder: (context) {
          f = LayoutBreakpoint.splitPanelFraction(context);
          return const SizedBox();
        }),
      ));
      return f;
    }

    testWidgets('46% portrait, 40% landscape', (t) async {
      expect(await fraction(t, const Size(800, 1000)), 0.46);
      expect(await fraction(t, const Size(1000, 800)), 0.40);
    });

    testWidgets('a vertical hinge puts the panel right of it', (t) async {
      final f = await fraction(t, const Size(1000, 800), features: const [
        DisplayFeature(
          bounds: Rect.fromLTWH(490, 0, 20, 800),
          type: DisplayFeatureType.hinge,
          state: DisplayFeatureState.unknown,
        ),
      ]);
      expect(f, closeTo(0.49, 1e-9));
    });

    testWidgets('a flat fold changes nothing', (t) async {
      final f = await fraction(t, const Size(1000, 800), features: const [
        DisplayFeature(
          bounds: Rect.fromLTWH(500, 0, 0, 800),
          type: DisplayFeatureType.fold,
          state: DisplayFeatureState.postureFlat,
        ),
      ]);
      expect(f, 0.40);
    });
  });
}
