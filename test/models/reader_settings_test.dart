import 'package:flutter_test/flutter_test.dart';
import 'package:comic_reader_app/models/reader_settings.dart';

void main() {
  group('ReaderSettings', () {
    test('zoomMode defaults off; bubbleZoom is derived from it', () {
      expect(const ReaderSettings().zoomMode, 'off');
      expect(const ReaderSettings().bubbleZoom, isFalse);
      expect(const ReaderSettings(zoomMode: 'bubbles').bubbleZoom, isTrue);
      expect(const ReaderSettings(zoomMode: 'panels').bubbleZoom, isFalse);
    });

    test('zoom_mode and panel_dim round-trip; bubble_zoom is written derived', () {
      final json = const ReaderSettings(zoomMode: 'panels', panelDim: true).toJson();
      expect(json['zoom_mode'], 'panels');
      expect(json['panel_dim'], isTrue);
      expect(json['bubble_zoom'], isFalse);
      expect(json.containsKey('panel_detection'), isFalse);
      final back = ReaderSettings.fromJson(json);
      expect(back.zoomMode, 'panels');
      expect(back.panelDim, isTrue);
      expect(const ReaderSettings().copyWith(zoomMode: 'bubbles').bubbleZoom, isTrue);
    });

    test('fromJson falls back to bubble_zoom, then the legacy panel_detection key', () {
      expect(ReaderSettings.fromJson({'bubble_zoom': true}).zoomMode, 'bubbles');
      expect(ReaderSettings.fromJson({'panel_detection': true}).zoomMode, 'bubbles');
      expect(ReaderSettings.fromJson({'bubble_zoom': false, 'panel_detection': true}).zoomMode, 'off');
      expect(ReaderSettings.fromJson({'zoom_mode': 'panels', 'bubble_zoom': true}).zoomMode, 'panels');
      expect(ReaderSettings.fromJson({'zoom_mode': 'sideways'}).zoomMode, 'off');
    });

    test('pageFit defaults to fitScreen', () {
      const settings = ReaderSettings();
      expect(settings.pageFit, 'fitScreen');
    });

    test('fromJson parses pageFit', () {
      final settings = ReaderSettings.fromJson({
        'page_fit': 'fitWidth',
      });
      expect(settings.pageFit, 'fitWidth');
    });

    test('fromJson migrates legacy contain to fitScreen', () {
      final settings = ReaderSettings.fromJson({
        'page_fit': 'contain',
      });
      expect(settings.pageFit, 'fitScreen');
    });

    test('fromJson defaults pageFit when missing', () {
      final settings = ReaderSettings.fromJson({});
      expect(settings.pageFit, 'fitScreen');
    });

    test('toJson includes pageFit', () {
      const settings = ReaderSettings(pageFit: 'fitHeight');
      final json = settings.toJson();
      expect(json['page_fit'], 'fitHeight');
    });

    test('copyWith updates pageFit', () {
      const settings = ReaderSettings();
      final updated = settings.copyWith(pageFit: 'fitHeight');
      expect(updated.pageFit, 'fitHeight');
      expect(updated.readingMode, 'page');
    });

    test('pageAnimation defaults to slide', () {
      const settings = ReaderSettings();
      expect(settings.pageAnimation, 'slide');
    });

    test('zoomLock defaults to false', () {
      const settings = ReaderSettings();
      expect(settings.zoomLock, false);
    });

    test('fromJson parses pageAnimation and zoomLock', () {
      final settings = ReaderSettings.fromJson({
        'page_animation': 'fade',
        'zoom_lock': true,
      });
      expect(settings.pageAnimation, 'fade');
      expect(settings.zoomLock, true);
    });

    test('toJson includes pageAnimation and zoomLock', () {
      const settings = ReaderSettings(pageAnimation: 'none', zoomLock: true);
      final json = settings.toJson();
      expect(json['page_animation'], 'none');
      expect(json['zoom_lock'], true);
    });

    test('copyWith updates pageAnimation and zoomLock', () {
      const settings = ReaderSettings();
      final updated = settings.copyWith(pageAnimation: 'fade', zoomLock: true);
      expect(updated.pageAnimation, 'fade');
      expect(updated.zoomLock, true);
      expect(updated.readingMode, 'page');
    });

    test('default tapZoneLayout is standard', () {
      expect(const ReaderSettings().tapZoneLayout, 'standard');
    });

    test('fromJson prefers tap_zone_layout', () {
      final s = ReaderSettings.fromJson({'tap_zone_layout': 'edge'});
      expect(s.tapZoneLayout, 'edge');
    });

    test('fromJson derives disabled from legacy tap_zones=false', () {
      final s = ReaderSettings.fromJson({'tap_zones': false});
      expect(s.tapZoneLayout, 'disabled');
    });

    test('fromJson derives standard from legacy tap_zones=true', () {
      final s = ReaderSettings.fromJson({'tap_zones': true});
      expect(s.tapZoneLayout, 'standard');
    });

    test('fromJson unknown layout falls back to standard', () {
      final s = ReaderSettings.fromJson({'tap_zone_layout': 'bogus'});
      expect(s.tapZoneLayout, 'standard');
    });

    test('toJson dual-writes layout and derived bool', () {
      expect(const ReaderSettings(tapZoneLayout: 'edge').toJson()['tap_zone_layout'], 'edge');
      expect(const ReaderSettings(tapZoneLayout: 'edge').toJson()['tap_zones'], true);
      expect(const ReaderSettings(tapZoneLayout: 'disabled').toJson()['tap_zones'], false);
    });

    test('fromJson snaps sleep_timer_min to the nearest step; 0 maps to 15', () {
      expect(ReaderSettings.fromJson({'sleep_timer_min': 0}).sleepTimerMin, 15);
      expect(ReaderSettings.fromJson({'sleep_timer_min': 60}).sleepTimerMin, 45);
    });

    test('fromJson defaults sleepWarningSec to 60; 0 also defaults to 60', () {
      expect(ReaderSettings.fromJson({}).sleepWarningSec, 60);
      expect(ReaderSettings.fromJson({'sleep_warning_sec': 0}).sleepWarningSec, 60);
      expect(ReaderSettings.fromJson({'sleep_warning_sec': 120}).sleepWarningSec, 120);
    });

    test('toJson includes sleep_warning_sec', () {
      const settings = ReaderSettings(sleepWarningSec: 30);
      expect(settings.toJson()['sleep_warning_sec'], 30);
    });

    test('copyWith updates sleepWarningSec', () {
      const settings = ReaderSettings();
      final updated = settings.copyWith(sleepWarningSec: 30);
      expect(updated.sleepWarningSec, 30);
      expect(updated.readingMode, 'page');
    });
  });
}
