import '../services/sleep_timer.dart' show snapStartingMin;
import '../config/flavor.dart';

class ReaderSettings {
  final String readingMode;
  final String readingDirection;
  final String theme;
  final String tapZoneLayout;
  /// 'off' | 'panels' | 'bubbles'.
  final String zoomMode;
  /// Panels mode: darken the page around the current panel.
  final bool panelDim;
  bool get bubbleZoom => zoomMode == 'bubbles';
  final int sleepTimerMin;
  final int sleepWarningSec;
  final bool keepScreenOn;
  final String pageFit;
  final bool volumeKeys;
  final String pageAnimation;
  final bool zoomLock;

  const ReaderSettings({
    this.readingMode = 'page',
    this.readingDirection = 'ltr',
    this.theme = 'black',
    this.tapZoneLayout = 'standard',
    this.zoomMode = 'off',
    this.panelDim = false,
    this.sleepTimerMin = 15,
    this.sleepWarningSec = 60,
    this.keepScreenOn = true,
    this.pageFit = 'fitScreen',
    this.volumeKeys = false,
    this.pageAnimation = 'slide',
    this.zoomLock = false,
  });

  factory ReaderSettings.fromJson(Map<String, dynamic> json) {
    var pageFit = json['page_fit'] as String? ?? 'fitScreen';
    if (pageFit == 'contain') pageFit = 'fitScreen';
    const allowed = {'standard', 'disabled', 'edge', 'thumb'};
    final rawLayout = json['tap_zone_layout'] as String?;
    final tapZoneLayout = (rawLayout != null && allowed.contains(rawLayout))
        ? rawLayout
        : ((json['tap_zones'] as bool? ?? true) ? 'standard' : 'disabled');
    const modes = {'off', 'panels', 'bubbles'};
    final rawMode = json['zoom_mode'] as String?;
    final zoomMode = rawMode != null && modes.contains(rawMode)
        ? rawMode
        : ((json['bubble_zoom'] as bool? ?? json['panel_detection'] as bool? ?? false) ? 'bubbles' : 'off');
    return ReaderSettings(
      readingMode: json['reading_mode'] as String? ?? 'page',
      readingDirection: json['reading_direction'] as String? ?? 'ltr',
      theme: json['theme'] as String? ?? 'black',
      tapZoneLayout: tapZoneLayout,
      zoomMode: zoomMode,
      panelDim: json['panel_dim'] as bool? ?? false,
      sleepTimerMin: snapStartingMin(json['sleep_timer_min'] as int? ?? 0),
      sleepWarningSec: (json['sleep_warning_sec'] as int? ?? 0) == 0
          ? 60
          : json['sleep_warning_sec'] as int,
      keepScreenOn: json['keep_screen_on'] as bool? ?? true,
      pageFit: pageFit,
      // Off in the store app (App Review 2.5.9: hijacking the volume buttons
      // must be opt-in); personal keeps on for a server that never saved it.
      volumeKeys: json['volume_keys'] as bool? ?? !isStore,
      pageAnimation: json['page_animation'] as String? ?? 'slide',
      zoomLock: json['zoom_lock'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'reading_mode': readingMode,
      'reading_direction': readingDirection,
      'theme': theme,
      'tap_zone_layout': tapZoneLayout,
      'tap_zones': tapZoneLayout != 'disabled',
      'zoom_mode': zoomMode,
      'panel_dim': panelDim,
      'bubble_zoom': bubbleZoom,
      'sleep_timer_min': sleepTimerMin,
      'sleep_warning_sec': sleepWarningSec,
      'keep_screen_on': keepScreenOn,
      'page_fit': pageFit,
      'volume_keys': volumeKeys,
      'page_animation': pageAnimation,
      'zoom_lock': zoomLock,
    };
  }

  ReaderSettings copyWith({
    String? readingMode,
    String? readingDirection,
    String? theme,
    String? tapZoneLayout,
    String? zoomMode,
    bool? panelDim,
    int? sleepTimerMin,
    int? sleepWarningSec,
    bool? keepScreenOn,
    String? pageFit,
    bool? volumeKeys,
    String? pageAnimation,
    bool? zoomLock,
  }) {
    return ReaderSettings(
      readingMode: readingMode ?? this.readingMode,
      readingDirection: readingDirection ?? this.readingDirection,
      theme: theme ?? this.theme,
      tapZoneLayout: tapZoneLayout ?? this.tapZoneLayout,
      zoomMode: zoomMode ?? this.zoomMode,
      panelDim: panelDim ?? this.panelDim,
      sleepTimerMin: sleepTimerMin ?? this.sleepTimerMin,
      sleepWarningSec: sleepWarningSec ?? this.sleepWarningSec,
      keepScreenOn: keepScreenOn ?? this.keepScreenOn,
      pageFit: pageFit ?? this.pageFit,
      volumeKeys: volumeKeys ?? this.volumeKeys,
      pageAnimation: pageAnimation ?? this.pageAnimation,
      zoomLock: zoomLock ?? this.zoomLock,
    );
  }
}
