import 'package:clock/clock.dart';
import '../providers/pro_provider.dart';
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/reader_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/providers.dart';
import '../models/reader_settings.dart';
import '../models/series.dart';
import '../widgets/cover_flight_route.dart';
import '../widgets/end_card_page.dart';
import '../widgets/jump_back_chip.dart';
import '../services/review_prompt.dart';
import '../services/api_client.dart';
import '../widgets/page_reader.dart';
import '../widgets/scroll_reader.dart';
import '../widgets/tap_zone_overlay.dart';
import '../widgets/tap_zone_onboarding.dart';
import '../widgets/reader_toolbar.dart';
import '../providers/rail_side_provider.dart';
import '../services/page_prefetcher.dart';
import '../services/spread_detector.dart';
import '../services/display_rect_calculator.dart';
import '../services/page_transform_calculator.dart';
import '../services/zoom_math.dart';
import '../services/pan_sequence_controller.dart';
import '../widgets/volume_key_listener.dart';
import '../config/app_theme.dart';
import '../config/flavor.dart';
import '../widgets/ambient_progress_rail.dart';
import '../widgets/floating_page_pill.dart';
import '../widgets/filmstrip_scrubber.dart';
import '../widgets/page_grid_overlay.dart';
import '../widgets/sleep_warning_overlay.dart';
import '../widgets/claude_panel.dart';
import '../widgets/bedtime_card.dart';
import '../providers/cache_providers.dart';
import '../providers/connectivity_provider.dart';
import '../providers/download_provider.dart';
import '../services/download_manager.dart';
import '../providers/mirror_provider.dart';
import '../providers/source_provider.dart';
import '../providers/accent_provider.dart';
import '../providers/zone_peek_provider.dart';
import 'series_detail_screen.dart';
import 'recap_screen.dart';
import '../widgets/reader_aa_panel.dart';
import '../widgets/flag_reason_card.dart';
import '../widgets/reader_more_menu.dart';
import '../services/label_client.dart';
import '../services/label_editor.dart';
import 'label_screen.dart';
import '../config/scheme.dart';
import '../models/comic_info.dart';
import '../widgets/liquid_glass.dart';
import '../config/layout_breakpoint.dart';
import '../services/sleep_timer.dart';
import '../services/sleep_shortcut.dart';
import '../services/bedtime_reminder.dart';
import '../services/reading_session_tracker.dart';
import '../services/reader_screen_controller.dart';
import '../services/chapter_merge.dart';
import '../widgets/chapter_list_sheet.dart';
import '../providers/scan_provider.dart';
import '../providers/remote_provider.dart';
import '../services/remote_session.dart';
import '../widgets/remote_control_listener.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../models/page_bubbles.dart';
import '../services/bubble_art.dart';
import '../services/bubble_mask.dart';
import '../services/bubble_repository.dart';
import '../services/bubble_scroll.dart';
import '../services/panel_steps.dart';
import '../widgets/bubble_pop_overlay.dart';
import '../widgets/panel_dim_overlay.dart';
import '../widgets/creator_detail_panel.dart' show openCreator;
import '../widgets/issue_credits_sheet.dart';
import '../config/string_utils.dart';


/// The series a comic belongs to, from its folder: the id is the folder's
/// slug, as the server makes it. Null for a comic at the library root.
({String id, String name})? seriesFromComicPath(String path) {
  final parts = path.split('/');
  if (parts.length < 2) return null;
  final name = parts[parts.length - 2];
  final id = name
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  return id.isEmpty ? null : (id: id, name: name);
}

class ReaderScreen extends ConsumerStatefulWidget {
  final String comicId;
  final String comicPath;
  final int initialPage;
  final List<SeriesIssue>? seriesIssues;
  final int? currentIssueIndex;
  final String? seriesId;
  final String? seriesName;

  const ReaderScreen({
    super.key,
    required this.comicId,
    required this.comicPath,
    this.initialPage = 0,
    this.seriesIssues,
    this.currentIssueIndex,
    this.seriesId,
    this.seriesName,
  });

  @override
  ConsumerState<ReaderScreen> createState() => ReaderScreenState();
}

class ReaderScreenState extends ConsumerState<ReaderScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  Color get accent => ref.watch(accentProvider).value ?? AppTheme.accent;

  bool _showToolbar = false;
  // Rightward travel of a drag that began on the left-edge exit strip.
  double _edgeDrag = 0;
  bool _showOnboarding = false;
  // Brief zone map on open (zonePeekProvider); taps pass through it.
  bool _peekZones = false;
  bool _onboardingChecked = false;
  late PageController _pageController;
  PagePrefetcher? _prefetcher;
  late AnimationController _overlayAnim;

  final PanSequenceController _panController = PanSequenceController();
  BubbleRepository? _bubbleRepo;
  bool _serverBubbles = false;
  final Map<int, PageBubbles> _bubbles = {};
  final Map<int, Map<int, BubbleMask>> _bubbleMasks = {};

  /// Where each page has detailed art, for placing pop-outs off it. Built with
  /// the masks, from the same decoded page.
  final Map<int, ArtMap> _bubbleArt = {};
  static const _swapHintKey = 'bubble_swap_hint_shown';
  bool _swapHintQueued = false;

  /// The balloon steps the pan controller holds for each page, fixed when its
  /// steps were set: cut-outs arriving mid-page don't shift what a step shows.
  final Map<int, List<List<Bubble>>> _bubbleSteps = {};
  final Map<int, ImageProvider> _pageProviders = {};
  final Set<int> _bubbleLoading = {};
  final Set<int> _maskBuilding = {};
  final TransformationController _transformController = TransformationController();
  late AnimationController _panAnim;
  Animation<Matrix4>? _panTween;
  final Map<int, (int, int)> _imageDimensions = {};
  final Set<int> _readyPages = {};
  bool? _lastPortrait;
  String? _lastReadingDirection;
  String? _lastReadingMode;
  bool _isZoomed = false;
  String? _lastPageFit;
  Matrix4? _lockedTransform;
  @visibleForTesting
  bool get zoomLocked => _lockedTransform != null;

  /// Set before a backward page turn so the next transform recalculation
  /// lands on the page's LAST step (a spread's right half), not step 0.
  /// Consumed in [_recalculateTransforms]; a flag rather than a post-frame
  /// jumpToEnd because fade lands 300ms later and none lands synchronously.
  bool _landAtEnd = false;
  final GlobalKey<PageReaderState> _pageReaderKey = GlobalKey<PageReaderState>();

  late ReadingSessionTracker _sessionTracker;
  late ReaderScreenController _screenController;

  late String _comicId;
  late String _comicPath;
  List<SeriesIssue>? _seriesIssues;
  int? _currentIssueIndex;
  String? _seriesId;
  String? _seriesName;
  /// True while the quick-settings UI is open, in EITHER presentation: the
  /// iPad popover or the phone bottom sheet. One flag rather than two so the
  /// tune button's highlight cannot disagree with what is on screen.
  bool _quickSettingsOpen = false;
  bool _moreOpen = false;
  Route<void>? _moreRoute;

  /// One-shot from "Clip a panel": the next tap clips the panel under it
  /// instead of being a normal reader tap (see the armed layer in the stack).
  bool _clipArmed = false;
  bool _showSleepWarning = false;
  bool _showBedtime = false;
  Timer? _bedtimeSnooze;

  ClaudePanelMode _claudeMode = ClaudePanelMode.off;

  /// Mounted on first open, then kept for this reader so toggling never
  /// reloads.
  bool _claudeOpened = false;

  /// Set when the sleep timer fired; the next resume or reader interaction
  /// restores the wakelock (per "Keep screen on") and clears it.
  bool _sleptSinceActivity = false;

  /// True while a screen the reader pushed (series detail, a creator page)
  /// covers it; it releases the wakelock, so restores wait for the return
  /// path.
  bool _awayFromReader = false;

  /// The session tracker was paused by the app going to the background.
  bool _sessionPausedByLifecycle = false;

  /// Undoable jump. [_jumpOrigin] is the page read before the first jump
  /// (null = no chip); [_jumpTarget] the page jumped to. [_jumpUndone] means
  /// the reader is back on the origin and the chip offers Forward.
  /// [_jumpAt] is the page turns are counted from.
  int? _jumpOrigin;
  int _jumpTarget = 0;
  bool _jumpUndone = false;
  int _jumpTurns = 0;
  int _jumpAt = -1;

  /// Guards _markCurrentCompletedAndFlushSession against duplicate work.
  /// Reset to false implicitly when a fresh ReaderScreen mounts for the next comic.
  bool _completionFlushed = false;

  // Captured values for safe access in dispose() — ref is invalid after unmount
  bool _autoCleanupCapture = false;
  String _sourceIdCapture = 'default';
  DownloadManager? _downloadManagerCapture;
  ReaderState? _lastReaderStateCapture;
  bool _pendingPostFrame = false;

  ReaderKey get _readerKey => (
    comicId: _comicId,
    comicPath: _comicPath,
    seriesIssues: _seriesIssues,
    currentIssueIndex: _currentIssueIndex,
  );

  bool _initialPageApplied = false;

  /// Set once scroll mode has reported a page: from then on the provider's
  /// current page is real, not its starting 0.
  bool _scrollReported = false;
  String? _localPagesPath;

  /// Opened once per reader session and cancelled when RemoteControlListener
  /// disposes — that cancel is what tells the relay this iPad stopped
  /// reading. Must not be re-resolved in build(): a new stream per frame
  /// would reconnect in a loop, and re-reading it on an active-source switch
  /// would bind to a disposed session.
  late final Stream<Map<String, dynamic>> _remoteCommands;

  /// Readers currently mounted. A replaced reader is disposed after its
  /// successor's initState, so it must leave process-wide state (system UI,
  /// wakelock, brightness, image cache) alone while another reader is live.
  static int _liveReaders = 0;

  @override
  void initState() {
    super.initState();
    _liveReaders++;
    _comicId = widget.comicId;
    _comicPath = widget.comicPath;
    _seriesIssues = widget.seriesIssues;
    _currentIssueIndex = widget.currentIssueIndex;
    // Openers that only know the file (Read home, Files) leave these out:
    // the comic's folder is its series.
    final folder = seriesFromComicPath(_comicPath);
    _seriesId = (widget.seriesId?.isNotEmpty ?? false) ? widget.seriesId : folder?.id;
    _seriesName = (widget.seriesName?.isNotEmpty ?? false) ? widget.seriesName : folder?.name;
    // Komga ids carry no folder: ask the mirror.
    if (_seriesId == null) {
      ref.read(mirrorDbProvider).seriesIdForComic(_comicId).then((id) {
        if (mounted) _seriesId ??= id;
      }).ignore();
    }
    _pageController = PageController(initialPage: widget.initialPage);
    _remoteCommands = ref.read(remoteCommandsProvider)();
    _overlayAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _panAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    )
      ..addListener(() {
        if (_panTween != null) {
          _transformController.value = _panTween!.value;
        }
      })
      ..addStatusListener((status) {
        // After a programmatic transform animation (e.g., double-tap zoom or
        // spread step), sync _isZoomed and the zoom-lock pipeline with the
        // controller's final scale. Without this, ZoomWrapper's panEnabled
        // stays stale (PageView keeps owning horizontal swipe), and zoom lock
        // never captures the new transform.
        if (status == AnimationStatus.completed && mounted) {
          final scale = _transformController.value.entry(0, 0);
          final zoomed = scale > 1.01;
          if (_isZoomed != zoomed) {
            setState(() => _isZoomed = zoomed);
          }
          _onTransformEnd(_transformController.value);
        }
      });
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersive);
    WidgetsBinding.instance.addObserver(this);
    _sessionTracker = ReadingSessionTracker(
      comicId: _comicId,
      deriveSeriesId: _deriveSeriesId,
      initialPage: widget.initialPage,
    );
    _screenController = ReaderScreenController();
    SleepTimer.instance.attach(
      this,
      // Release the wakelock and let iOS auto-lock on its own idle timer. The
      // reader stays open, so waking the device returns to the current page.
      // Dim to the floor meanwhile, and optionally hand off to the user's
      // Shortcut (Focus / DND — no app API for those).
      onFired: () async {
        if (!mounted) return;
        _screenController.setKeepScreenOn(false);
        _sleptSinceActivity = true;
        setState(() => _showSleepWarning = false);
        await _screenController.dimForSleep();
        if (mounted && await ref.read(sleepShortcutProvider.future)) {
          runSleepShortcut();
        }
      },
      onWarning: () {
        if (mounted) setState(() => _showSleepWarning = true);
      },
    );
    // Sidecars come from a Gutter server; other sources have none, so don't
    // ask them on every page. Panels mode still finds panels on the device.
    _serverBubbles = ref.read(isCustomSourceProvider);
    _bubbleRepo = BubbleRepository(
      client: ref.read(apiClientProvider),
      queue: ref.read(syncQueueProvider),
      mirror: ref.read(mirrorDbProvider),
    );
    // Fires at once when settings are already loaded (every reader after the first),
    // and again when they arrive or change. Only bubble-relevant changes act.
    ref.listenManual<AsyncValue<ReaderSettings>>(settingsProvider, (prev, next) {
      final a = prev?.value, b = next.value;
      if (b == null) return;
      SleepTimer.instance.warningLead = Duration(seconds: b.sleepWarningSec);
      final zoomChanged = (a?.zoomMode ?? 'off') != b.zoomMode; // dim is read at build; no re-step
      final lockChanged = (a?.zoomLock ?? false) != b.zoomLock && (b.zoomMode != 'off' || (a?.zoomMode ?? 'off') != 'off');
      if (zoomChanged || lockChanged) _refreshBubbleSteps();
      // Picking a new tap layout shows its map until the next tap.
      if (a != null && a.tapZoneLayout != b.tapZoneLayout && b.tapZoneLayout != 'disabled') {
        setState(() {
          _showOnboarding = true;
          _peekZones = false;
        });
      }
    }, fireImmediately: true);
    _checkLocalDownload();
    // Enable wakelock if setting is on. Opening a comic never arms the
    // sleep timer — only the moon button does.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // The notifier is keyed by comic: a stale hold from a previous reader
      // of the same comic would have no chip to release it.
      ref.read(readerProvider(_readerKey).notifier).releaseHold();
      _showWarningIfInLead(); // carried over from the previous reader
      _maybeBedtimeReminder();
      final settings = ref.read(settingsProvider).value;
      if (settings == null) return;
      if (settings.keepScreenOn) {
        _screenController.setKeepScreenOn(true);
      }
    });
  }

  Future<void> _checkLocalDownload() async {
    final sourceId = ref.read(activeSourceProvider).id;
    final path = await downloadedPagesPath(sourceId, _comicId);
    if (mounted && path != null) {
      setState(() => _localPagesPath = path);
      _bubbleRepo?.localDir = p.dirname(path);
      _bubbles.clear();
      _bubbleSteps.clear();
      _loadBubbles(_shownPage);
    }
  }


  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    SleepTimer.instance.detach(this);
    _bedtimeSnooze?.cancel();

    // Use captured values — ref is invalid after unmount
    if (_autoCleanupCapture && _localPagesPath != null) {
      final pageCount = _lastReaderStateCapture?.info?.pageCount ?? 0;
      final currentPage = _lastReaderStateCapture?.currentPage ?? 0;
      if (pageCount > 0 && currentPage >= pageCount - 1) {
        _downloadManagerCapture?.delete(_comicId, _sourceIdCapture);
      }
    }

    final currentPage = _lastReaderStateCapture?.currentPage ?? widget.initialPage;
    _sessionTracker.endSessionWithPage(currentPage);
    _pageController.dispose();
    _panController.dispose();
    for (final masks in _bubbleMasks.values) {
      for (final m in masks.values) {
        m.image.dispose();
      }
    }
    _transformController.dispose();
    _panAnim.dispose();
    _overlayAnim.dispose();
    _prefetcher?.dispose();
    if (--_liveReaders == 0) {
      // Closing the reader (back to the library) turns the timer off.
      SleepTimer.instance.cancel();
      _screenController.dispose();
      // Free comic page images from memory when leaving the reader.
      PaintingBinding.instance.imageCache.clear();
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
    // Else: another reader is already live (pushReplacement for end card ->
    // next issue, or picking an issue from series detail) and owns the
    // shared deadline now. detach(this) above already dropped this reader's
    // callbacks; cancelling here would kill the carry-over deadline the new
    // reader is relying on.
    super.dispose();
  }

  String _deriveSeriesId() {
    if (_seriesId != null && _seriesId!.isNotEmpty) return _seriesId!;
    return seriesFromComicPath(_comicPath)?.id ?? '';
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final currentPage = _lastReaderStateCapture?.currentPage ?? widget.initialPage;
    // Not on inactive: in iPhone Duo / iPad Split View the reader stays on
    // screen while inactive, and Control Center or a notification only
    // makes it inactive. Only a real pause ends the session.
    if (state == AppLifecycleState.paused) {
      _sessionTracker.pause(currentPage);
      _sessionPausedByLifecycle = true;
    } else if (state == AppLifecycleState.resumed) {
      // resume() restarts the clock, so only after a real pause.
      if (_sessionPausedByLifecycle) _sessionTracker.resume(currentPage);
      _sessionPausedByLifecycle = false;
      // Timers do not run reliably while suspended — recheck the deadline.
      SleepTimer.instance.resync();
      // resync() cancels any overdue warn timer and _armFor won't reschedule
      // one at/under the lead, so a lock/unlock inside the lead needs this
      // to re-show the warning.
      _showWarningIfInLead();
      _noteReaderActivity();
    }
  }

  /// Ryan is reading again: if the timer fired since the last activity,
  /// put the wakelock back the way the setting wants it.
  void _noteReaderActivity() {
    // Series page open: leave the flag for the return path to restore.
    if (_sleptSinceActivity && !_awayFromReader) _restoreWakelock();
  }

  /// Wakelock back per "Keep screen on"; any pending fire is answered.
  void _restoreWakelock() {
    _sleptSinceActivity = false;
    _screenController.undoSleepDim();
    final settings = ref.read(settingsProvider).value;
    if (settings != null) _screenController.setKeepScreenOn(settings.keepScreenOn);
  }

  /// A deadline already inside the warning lead (carried over from another
  /// reader or the series page) has had its warning timer go by: show it now.
  void _showWarningIfInLead() {
    final left = SleepTimer.instance.remaining;
    if (left != null && left > Duration.zero &&
        left <= SleepTimer.instance.warningLead && mounted) {
      setState(() => _showSleepWarning = true);
    }
  }

  /// Late, timer off, not yet nagged tonight (or a snooze is up): offer to
  /// start it. A snooze still running re-checks when it's due.
  Future<void> _maybeBedtimeReminder() async {
    if (SleepTimer.instance.remaining != null) return;
    final reminder = ref.read(bedtimeReminderProvider.notifier);
    if (!await reminder.claim(clock.now())) {
      final until = await reminder.snoozedUntil();
      final wait = until?.difference(clock.now());
      if (!mounted || wait == null || wait.isNegative) return;
      _bedtimeSnooze?.cancel();
      _bedtimeSnooze = Timer(wait, _maybeBedtimeReminder);
      return;
    }
    if (!mounted || SleepTimer.instance.remaining != null) return;
    setState(() => _showBedtime = true);
  }

  void _onMoonTap() {
    final settings = ref.read(settingsProvider).value ?? const ReaderSettings();
    SleepTimer.instance.start(nextMoonStep(
        remaining: SleepTimer.instance.remaining,
        startingMin: settings.sleepTimerMin));
    setState(() => _showSleepWarning = false);
  }

  /// Any banner action means the warning is answered — run it and hide.
  void _resolveSleepWarning(VoidCallback action) {
    action();
    setState(() => _showSleepWarning = false);
  }

  /// Public for the reader test harness.
  void showChrome() {
    _noteReaderActivity();
    // Mid-hide counts as hidden: forward() cancels the reverse, whose
    // completion callback then never runs.
    if (_showToolbar && _overlayAnim.status != AnimationStatus.reverse) return;
    setState(() => _showToolbar = true);
    _overlayAnim.forward();
  }

  void hideChrome() {
    _noteReaderActivity();
    // The iPad Aa popover and the more menu hang off the bar; close them too
    // (a volume-key or remote page turn hides the bar under them).
    if (_quickSettingsOpen && LayoutBreakpoint.isTablet(context)) {
      setState(() => _quickSettingsOpen = false);
    }
    if (_moreRoute case final r? when r.isActive) {
      Navigator.of(context).removeRoute(r);
    }
    if (!_showToolbar) return;
    _overlayAnim.reverse().then((_) {
      if (mounted) setState(() => _showToolbar = false);
    });
  }

  void _handleLeft(ReaderSettings settings) {
    if (settings.readingDirection == 'rtl') {
      _handleVolumeUp();
    } else {
      _handleVolumeDown();
    }
  }

  void _handleRight(ReaderSettings settings) {
    if (settings.readingDirection == 'rtl') {
      _handleVolumeDown();
    } else {
      _handleVolumeUp();
    }
  }

  void _onZoomChanged(bool zoomed) {
    if (_isZoomed != zoomed) {
      setState(() => _isZoomed = zoomed);
      if (!zoomed) {
        _lockedTransform = null;
        if (_bubbleStepsStale) {
          _bubbleStepsStale = false;
          _refreshBubbleSteps();
        }
      }
    }
  }

  void _onTransformEnd(Matrix4 transform) {
    final settings = ref.read(settingsProvider).value ?? const ReaderSettings();
    if (!settings.zoomLock) return;
    final scale = transform.entry(0, 0);
    if (scale <= 1.01) {
      _lockedTransform = null;
    } else if (_offStep) {
      // Only a real user zoom locks. A reader-set step (fit width, auto-zoom,
      // spread/panel/bubble) also ends interactions — a one-finger swipe up
      // does — and locking it would make every later swipe pan, not show chrome.
      _lockedTransform = transform.clone();
    }
  }

  Color _bgColor(String theme) {
    switch (theme) {
      case 'white':
      case 'paper': // legacy value
        return Colors.white;
      case 'sepia':
        return const Color(0xFFF4ECD8);
      default:
        return Colors.black;
    }
  }



  void _onImageLoaded(int page, int width, int height) {
    if (_imageDimensions.containsKey(page)) return;
    _imageDimensions[page] = (width, height);
    final isCurrent =
        ref.read(readerProvider(_readerKey)).value?.currentPage == page;
    try {
      if (isCurrent) {
        final settings = ref.read(settingsProvider).value ?? const ReaderSettings();
        if (settings.zoomLock && _lockedTransform != null) {
          _transformController.value = _lockedTransform!;
          _panController.setTransforms([_lockedTransform!]);
        } else {
          _recalculateTransforms(page, width, height, instant: true);
          _easeFromCover();
        }
      }
    } catch (e) {
      debugPrint('Transform calculation failed for page $page: $e');
    }
    // Always mark page as ready so it becomes visible even if transforms failed
    setState(() => _readyPages.add(page));
    if (isCurrent) CoverReveal.of(context)?.ready();

    // First-run hint: check once per reader session, after the first page
    // the user sees has loaded.
    if (!_onboardingChecked) {
      _onboardingChecked = true;
      shouldShowTapZoneOnboarding().then((show) {
        if (!mounted) return;
        if (show) {
          setState(() => _showOnboarding = true);
        } else if (ref.read(zonePeekProvider) &&
            ref.read(settingsProvider).value?.tapZoneLayout != 'disabled') {
          setState(() => _peekZones = true);
        }
      });
    }
  }

  bool _coverEasePending = true;

  /// Under a cover flight the first page shows where the cover landed (the
  /// contain rect, identity) and eases to its first step once the cover has
  /// handed over, instead of appearing already zoomed.
  void _easeFromCover() {
    final reveal = CoverReveal.of(context);
    if (reveal == null || !_coverEasePending) return;
    _coverEasePending = false;
    final target = _transformController.value.clone();
    if (target.isIdentity()) return;
    _transformController.value = Matrix4.identity();
    reveal.shown.then((_) {
      if (mounted && _transformController.value.isIdentity()) {
        _animateTo(target);
      }
    });
  }

  Rect? _displayRectFor(int page, Size viewport) {
    final dims = _imageDimensions[page];
    if (dims == null) return null;
    return calculateDisplayRect(
      imageWidth: dims.$1,
      imageHeight: dims.$2,
      viewportWidth: viewport.width,
      viewportHeight: viewport.height,
      fit: BoxFit.contain,
    );
  }

  void _handleDoubleTap(Offset positionInOverlay) {
    final state = ref.read(readerProvider(_readerKey)).value;
    if (state == null) return;
    final page = state.currentPage;
    final dims = _imageDimensions[page];
    if (dims == null) return;

    final viewport = MediaQuery.of(context).size;
    final displayRect = _displayRectFor(page, viewport);
    if (displayRect == null) return;

    // Collapse any active multi-step sequence so InteractiveViewer is in single-step mode.
    // Balloon steps stay: the next tap animates back to the next balloon's step.
    final settings = ref.read(settingsProvider).value ?? const ReaderSettings();
    if (_panController.hasMultipleSteps && !_bubbleActive(page, settings) && !_panelActive(page, settings)) {
      _panController.setTransforms([Matrix4.identity()]);
    }

    final currentScale = _transformController.value.entry(0, 0);
    final isCurrentlyZoomed = currentScale > 1.5;

    final Matrix4 target;
    if (isCurrentlyZoomed) {
      target = Matrix4.identity();
    } else {
      target = zoomAroundPoint(
        imagePoint: positionInOverlay,
        targetScale: 2.5,
        viewport: viewport,
        displayRect: displayRect,
      );
    }

    _animateTo(target);
  }

  /// The pan-sequence steps for an image of the given size in [viewport].
  List<Matrix4> _transformsFor(
      int imageWidth, int imageHeight, Size viewport, ReaderSettings settings) {
    // Always compute where the image actually renders (contain)
    final containRect = calculateDisplayRect(
      imageWidth: imageWidth,
      imageHeight: imageHeight,
      viewportWidth: viewport.width,
      viewportHeight: viewport.height,
      fit: BoxFit.contain,
    );
    return calculatePageTransforms(
      containRect: containRect,
      viewportSize: viewport,
      // Spread zoom steps are Pro; without it a spread shows whole.
      isSpread: ref.read(proProvider) && isSpread(imageWidth, imageHeight),
      isPortrait: viewport.height > viewport.width,
      isRtl: settings.readingDirection == 'rtl',
      fitMode: settings.pageFit,
    );
  }

  /// The page has been pinched or dragged away from what the current step shows.
  /// Not the same as [_isZoomed]: fit-width steps are scaled but not zoomed.
  bool get _offStep {
    final m = _transformController.value, step = _panController.currentTransform;
    if ((m.entry(0, 0) - step.entry(0, 0)).abs() > 0.01 * step.entry(0, 0)) return true;
    // mid-step the page is still travelling to the step's place; that's not off it
    if (_panAnim.isAnimating) return false;
    return (m.getTranslation() - step.getTranslation()).length > 4;
  }

  /// The user owns the transform: pinched off the step, or a zoom-lock carried
  /// over a page turn (which makes the locked transform the step). One-finger
  /// drags pan, and a swipe up doesn't show the chrome.
  bool get _userZoomed {
    final settings = ref.read(settingsProvider).value ?? const ReaderSettings();
    return _offStep || (settings.zoomLock && _lockedTransform != null);
  }

  /// Bubble steps replace chunk pan on [page] only when every condition in the
  /// spec's "Fallback" list holds.
  bool _bubbleActive(int page, ReaderSettings settings) {
    final pb = _bubbles[page];
    if (!settings.bubbleZoom || settings.zoomLock || settings.readingMode != 'page') return false;
    if (pb == null || pb.bubbles.isEmpty) return false;
    // A spread on a portrait screen renders too small for readable pop-outs; keep its spread pan.
    final view = MediaQuery.sizeOf(context);
    return !(isSpread(pb.width, pb.height) && view.height > view.width);
  }

  /// Panel steps replace chunk pan on [page] with panels mode and at least two
  /// panels. Unlike balloons, a spread on a portrait screen keeps them.
  bool _panelActive(int page, ReaderSettings settings) {
    final pb = _bubbles[page];
    if (settings.zoomMode != 'panels' || settings.zoomLock || settings.readingMode != 'page') return false;
    return pb != null && pb.panels.length >= 2;
  }

  /// Panel step k's box on the unmoved page, in screen coordinates.
  Rect? _panelRectOnScreen(int page, int k, Size viewport) {
    final pb = _bubbles[page];
    final display = _displayRectFor(page, viewport);
    if (pb == null || display == null || k < 1 || k > pb.panels.length) return null;
    return panelOnScreen(display, Size(pb.width.toDouble(), pb.height.toDouble()), pb.panels[k - 1]);
  }

  /// The steps for [page]: n + 1 for a page with n balloons (a chain of joined
  /// balloons counts as one), else today's transforms.
  List<Matrix4> _stepsFor(int page, int imageWidth, int imageHeight, Size viewport,
      ReaderSettings settings) {
    if (_panelActive(page, settings)) {
      final pb = _bubbles[page]!;
      final display = _displayRectFor(page, viewport);
      if (display != null) {
        // iPad, fit width on a sideways screen: the page keeps that scale and
        // each step scrolls the panel into view under its pop-out.
        final fit = _transformsFor(imageWidth, imageHeight, viewport, settings).first.entry(0, 0);
        if (LayoutBreakpoint.isTablet(context) && fit > 1.001 && !isSpread(imageWidth, imageHeight)) {
          final px = Size(pb.width.toDouble(), pb.height.toDouble());
          return bubbleScrollSteps(
            scale: fit,
            page: display,
            screen: viewport,
            steps: [for (final p in pb.panels) (panelOnScreen(display, px, p), null)],
          );
        }
        return panelSteps(
          page: display,
          pagePx: Size(pb.width.toDouble(), pb.height.toDouble()),
          screen: viewport,
          panels: pb.panels,
          popout: LayoutBreakpoint.isTablet(context),
        );
      }
    }
    if (!_bubbleActive(page, settings)) {
      return _transformsFor(imageWidth, imageHeight, viewport, settings);
    }
    // ponytail: n + 1 contain-fit steps. The overlay draws balloon step
    // `currentIndex` (0 = whole page), so tap zones, volume keys and land-at-end
    // on page-back all step balloons with no new code paths. The page only
    // slides, never scales: just far enough for a tailed pop-out to grow out
    // of its tail and still fit on screen.
    final groups = bubbleGroups(_bubbles[page]!, _bubbleMasks[page]);
    // Fit width on a sideways screen: the page stays at that scale and each
    // step scrolls it (bubbleScrollSteps).
    final fit = _transformsFor(imageWidth, imageHeight, viewport, settings).first.entry(0, 0);
    final display = _displayRectFor(page, viewport);
    if (fit > 1.001 && display != null && !isSpread(imageWidth, imageHeight)) {
      return bubbleScrollSteps(
        scale: fit,
        page: display,
        screen: viewport,
        steps: [for (final g in groups) _bubbleStepRect(page, g, viewport) ?? (Rect.zero, null)],
      );
    }
    return [
      Matrix4.identity(),
      for (final g in groups)
        () {
          final (on, tail) = _bubbleStepRect(page, g, viewport) ?? (Rect.zero, null);
          if (tail == null) return Matrix4.identity();
          final slide = popoutSlide(
            popoutRect(
              on,
              viewport,
              tail: tail,
              clamp: false,
              maxScale: g.length > 1 ? chainPopScale : maxPopScale,
            ),
            viewport,
          );
          return Matrix4.translationValues(slide.dx, slide.dy, 0);
        }(),
    ];
  }

  /// Where balloon step [group]'s crops and tail tip sit on the unmoved page.
  (Rect, Offset?)? _bubbleStepRect(int page, List<Bubble> group, Size viewport) {
    final pb = _bubbles[page];
    final display = _displayRectFor(page, viewport);
    if (pb == null || display == null) return null;
    final s = display.width / pb.width;
    Offset onScreen(Offset p) => display.topLeft + p * s;
    final masks = _bubbleMasks[page];
    final all = group
        .map((b) => masks?[b.label]?.pageRect ?? paddedBubbleRect(b, pb))
        .reduce((a, b) => a.expandToInclude(b));
    final tail = group.map((b) => masks?[b.label]?.tail).nonNulls.firstOrNull;
    return (
      Rect.fromPoints(onScreen(all.topLeft), onScreen(all.bottomRight)),
      tail == null ? null : onScreen(tail),
    );
  }

  Future<void> _loadBubbles(int page) async {
    final settings = ref.read(settingsProvider).value ?? const ReaderSettings();
    final repo = _bubbleRepo;
    if (settings.zoomMode == 'off' || settings.zoomLock || repo == null) return;
    if (!_bubbleLoading.add(page)) return;
    try {
      var pb = _bubbles[page] ?? (_serverBubbles ? await repo.forPage(_comicId, page) : null);
      if (pb == null && settings.zoomMode == 'panels') {
        pb = await repo.detectedPanels(_comicId, page, () => _pageImageFor(page));
      }
      if (!mounted || pb == null || (pb.bubbles.isEmpty && pb.panels.isEmpty)) return;
      final isNew = !_bubbles.containsKey(page);
      _bubbles[page] = pb;
      final dims = _imageDimensions[page];
      // A late sidecar only takes over a page the reader hasn't started panning or zoomed.
      if (isNew && _shownPage == page && dims != null && _panController.currentIndex == 0 && !_offStep) {
        _recalculateTransforms(page, dims.$1, dims.$2, instant: true);
      }
      setState(() {});
      if (pb.bubbles.isNotEmpty) _ensureMasks(page);
    } catch (e) {
      debugPrint('bubbles: page $page: $e'); // the page keeps chunk pan
    } finally {
      _bubbleLoading.remove(page);
    }
  }

  /// Builds a page's balloon cut-outs once both its sidecar and its image
  /// provider are known: from the full-resolution page when it resolves, else
  /// from the stored label alone. Until then balloons pop out as rounded rects.
  Future<void> _ensureMasks(int page) async {
    // Only bubble zoom uses cut-outs and the art map; panels mode skips the page decode.
    if (!(ref.read(settingsProvider).value?.bubbleZoom ?? false)) return;
    final pb = _bubbles[page], provider = _pageProviders[page];
    if (pb == null || provider == null || _bubbleMasks.containsKey(page)) return;
    if (!_maskBuilding.add(page)) return;
    ui.Image? image;
    try {
      try {
        image = await _resolvePageImage(provider).timeout(const Duration(seconds: 10));
      } catch (e) {
        debugPrint('bubbles: page $page image unavailable, using the stored mask: $e');
      }
      Map<int, BubbleMask> masks;
      try {
        masks = await buildBubbleMasks(pb, page: image);
      } catch (e) {
        // Bad mask PNG from the host job: pop out with the rounded-rect fallback.
        debugPrint('bubbles: page $page mask unusable: $e');
        masks = {};
      }
      if (!mounted) {
        for (final m in masks.values) {
          m.image.dispose();
        }
        return;
      }
      _bubbleMasks[page] = masks;
      if (image != null) {
        try {
          _bubbleArt[page] = await buildArtMap(pb, image); // ponytail: reads the page's pixels a second time
        } catch (e) {
          debugPrint('bubbles: page $page no art map: $e'); // pop-outs place by tail alone
        }
        if (!mounted) return;
      }
      // Cut-outs merge chains into one step and give tails their slide:
      // re-step a page not yet started.
      final dims = _imageDimensions[page];
      if (_shownPage == page && dims != null && _panController.currentIndex == 0 && !_offStep &&
          _bubbleActive(page, ref.read(settingsProvider).value ?? const ReaderSettings())) {
        _recalculateTransforms(page, dims.$1, dims.$2, instant: true);
      }
      setState(() {});
    } finally {
      image?.dispose();
      _maskBuilding.remove(page);
    }
  }

  /// The decoded page behind [provider] (an image-cache hit for the page on screen).
  /// The decoded page for on-device panels: the provider the page view built,
  /// else the network page under the prefetcher's cache key. Null for a
  /// downloaded page the view hasn't built yet ([onPageProvider] retries it).
  Future<ui.Image?> _pageImageFor(int page) async {
    final provider = _pageProviders[page] ??
        (_localPagesPath == null ? CachedNetworkImageProvider(ref.read(apiClientProvider).pageUrl(_comicId, page)) : null);
    if (provider == null) return null;
    try {
      return await _resolvePageImage(provider).timeout(const Duration(seconds: 10));
    } catch (e) {
      debugPrint('panels: page $page image unavailable: $e');
      return null;
    }
  }

  Future<ui.Image> _resolvePageImage(ImageProvider provider) {
    final done = Completer<ui.Image>();
    final stream = provider.resolve(ImageConfiguration.empty);
    late final ImageStreamListener listener;
    listener = ImageStreamListener((info, _) {
      stream.removeListener(listener);
      if (!done.isCompleted) done.complete(info.image.clone());
      info.dispose();
    }, onError: (Object e, StackTrace? st) {
      stream.removeListener(listener);
      if (!done.isCompleted) done.completeError(e, st);
    });
    stream.addListener(listener);
    return done.future;
  }

  /// Mask images are small but add up over a 1,000-page collection: keep ±2 pages.
  void _evictBubbleMasks(int current) {
    _bubbleArt.removeWhere((page, _) => (page - current).abs() > 2);
    _bubbleMasks.removeWhere((page, masks) {
      if ((page - current).abs() <= 2) return false;
      for (final m in masks.values) {
        m.image.dispose();
      }
      return true;
    });
  }

  /// The page on screen. Reader state lags the PageView until the first
  /// post-frame goToPage, so prefer the controller, then initialPage.
  int get _shownPage => _pageController.hasClients
      ? (_pageController.page?.round() ?? widget.initialPage)
      : widget.initialPage;

  /// Set when a settings change arrives while the page is zoomed; applied on unzoom.
  bool _bubbleStepsStale = false;

  /// Setting or zoom lock changed: rebuild the current page's steps from scratch,
  /// but never snap a zoomed page back to fit.
  void _refreshBubbleSteps() {
    final page = _shownPage;
    final dims = _imageDimensions[page];
    if (_offStep) {
      _bubbleStepsStale = true;
    } else if (dims != null) {
      _recalculateTransforms(page, dims.$1, dims.$2,
          instant: true, keepPlace: true);
    }
    _loadBubbles(page);
    _loadBubbles(page + 1);
  }

  /// Long-press swaps a popped-out balloon with the next; anywhere else it clips a panel.
  void _handleLongPress(ReaderSettings settings, Offset pos) {
    if (_handleBubbleLongPress(settings)) return;
    if (ref.read(isCustomSourceProvider)) _clipPanel(settings, pos);
  }

  bool _handleBubbleLongPress(ReaderSettings settings) {
    final page = ref.read(readerProvider(_readerKey)).value?.currentPage;
    if (page == null || _offStep || !_bubbleActive(page, settings)) return false;
    final pb = _bubbles[page]!;
    final steps = _bubbleSteps[page];
    final k = _panController.currentIndex; // 0 = whole page, k = step k
    if (steps == null || k < 1 || k >= steps.length) return false;
    final g = steps[k - 1];
    steps[k - 1] = steps[k];
    steps[k] = g;
    pb.applyOrder([for (final s in steps) for (final b in s) b.label]);
    HapticFeedback.selectionClick();
    setState(() {});
    _bubbleRepo?.saveOrder(_comicId, page, pb);
    return true;
  }

  /// The panel being clipped, on screen; outlined until the share sheet closes.
  Rect? _clipOutline;

  /// Crops the panel under [pos] from the full page and opens the share sheet
  /// (Save Image, Copy, Messages...). Off a panel, or on a page without panel
  /// data, says so instead.
  Future<void> _clipPanel(ReaderSettings settings, Offset pos) async {
    final page = ref.read(readerProvider(_readerKey)).value?.currentPage;
    final provider = page == null ? null : _pageProviders[page];
    if (page == null || provider == null || settings.readingMode != 'page' || _clipOutline != null) return;
    ui.Image? image;
    try {
      // Sidecars load only with zoom on; with it off, fetch this one now.
      final pb = _bubbles[page] ?? await _bubbleRepo?.forPage(_comicId, page);
      final display = mounted ? _displayRectFor(page, MediaQuery.sizeOf(context)) : null;
      if (display == null || !mounted) return;
      if (pb == null || pb.panels.isEmpty) return _clipHint('No panels detected on this page yet.');
      final pagePx = Size(pb.width.toDouble(), pb.height.toDouble());
      final m = _transformController.value;
      final k = _panController.currentIndex;
      // A panel step clips its panel wherever the press lands: on the iPad it covers the page.
      final Rect? panel = _panelActive(page, settings) && k >= 1 && k <= pb.panels.length && !_offStep
          ? pb.panels[k - 1]
          : panelAt(pb.panels, (MatrixUtils.transformPoint(Matrix4.inverted(m), pos) - display.topLeft) /
              (display.width / pagePx.width));
      if (panel == null) return _clipHint('No panel here. Long-press inside a panel to clip it.');
      final outline = MatrixUtils.transformRect(m, panelOnScreen(display, pagePx, panel));
      HapticFeedback.mediumImpact();
      setState(() => _clipOutline = outline);
      image = await _resolvePageImage(provider).timeout(const Duration(seconds: 10));
      final file = await _panelPng(image, panel, pagePx, page);
      if (!mounted) return;
      await Share.shareXFiles([XFile(file.path, mimeType: 'image/png')], sharePositionOrigin: outline);
    } catch (e) {
      debugPrint('clip: page $page: $e');
    } finally {
      image?.dispose();
      if (mounted && _clipOutline != null) setState(() => _clipOutline = null);
    }
  }

  void _clipHint(String text) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text), duration: const Duration(seconds: 2)));
  }

  /// [panel] (sidecar page pixels) cut from the decoded [image], as a PNG in the temp dir.
  Future<File> _panelPng(ui.Image image, Rect panel, Size pagePx, int page) async {
    final k = image.width / pagePx.width; // the decoded page can differ in size from the sidecar's
    final r = panel.intersect(Offset.zero & pagePx);
    final src = Rect.fromLTRB(r.left * k, r.top * k, r.right * k, r.bottom * k);
    final recorder = ui.PictureRecorder();
    Canvas(recorder).drawImageRect(image, src, Offset.zero & src.size, Paint());
    final picture = recorder.endRecording();
    final clip = await picture.toImage(src.width.round(), src.height.round());
    try {
      final png = await clip.toByteData(format: ui.ImageByteFormat.png);
      final file = File(p.join((await getTemporaryDirectory()).path, 'panel-p${page + 1}.png'));
      return file.writeAsBytes(png!.buffer.asUint8List());
    } finally {
      clip.dispose();
      picture.dispose();
    }
  }

  /// The first time a balloon pops out, say how to fix a wrong order; never again.
  void _queueSwapHint() {
    final prefs = ref.read(sharedPrefsProvider);
    if (_swapHintQueued || (prefs.getBool(_swapHintKey) ?? false)) return;
    _swapHintQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      prefs.setBool(_swapHintKey, true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Wrong order? Long-press to swap this balloon with the next.')),
      );
    });
  }

  Widget? _buildBubbleOverlay(int page, ReaderSettings settings) {
    final k = _panController.currentIndex;
    final pb = _bubbles[page];
    final steps = _bubbleSteps[page];
    final provider = _pageProviders[page];
    if (k == 0 || _offStep || pb == null || steps == null || provider == null) return null;
    if (!_bubbleActive(page, settings) || k > steps.length) return null;
    _queueSwapHint();
    final at = _bubbleStepRect(page, steps[k - 1], MediaQuery.sizeOf(context));
    if (at == null) return null;
    final (on, tail) = at;
    // Placed against where the step's slide is taking the page, not where it is now.
    final m = _panController.currentTransform;
    final masks = _bubbleMasks[page];
    final parts = [
      for (final b in steps[k - 1])
        (src: masks?[b.label]?.pageRect ?? paddedBubbleRect(b, pb), mask: masks?[b.label]?.image),
    ];
    return BubblePopOverlay(
      pageImage: provider,
      parts: parts,
      onScreen: MatrixUtils.transformRect(m, on),
      tail: tail == null ? null : MatrixUtils.transformPoint(m, tail),
      artCost: _artCost(page, m, parts.map((p) => p.src).reduce((a, b) => a.expandToInclude(b))),
      label: steps[k - 1].first.label,
    );
  }

  /// iPad panel zoom: the current panel lifted out over the unmoved page.
  Widget? _buildPanelOverlay(int page, ReaderSettings settings) {
    final k = _panController.currentIndex;
    final provider = _pageProviders[page];
    if (k == 0 || _offStep || provider == null || !LayoutBreakpoint.isTablet(context)) return null;
    if (!_panelActive(page, settings)) return null;
    final pb = _bubbles[page]!;
    final on = _panelRectOnScreen(page, k, MediaQuery.sizeOf(context));
    if (on == null) return null;
    return BubblePopOverlay(
      pageImage: provider,
      parts: [(src: pb.panels[k - 1], mask: null)],
      onScreen: MatrixUtils.transformRect(_panController.currentTransform, on),
      label: k,
      maxScale: 1.5,
      heightCap: 0.85,
      // A panel too wide to grow still lifts out at its own size, so every
      // step shows which panel is current.
      minScale: 1,
      minGrowth: 1,
    );
  }

  /// Panel zoom's dim: a hole at the current panel, or none between steps.
  Widget _buildPanelDim(int page, ReaderSettings settings) {
    final k = _panController.currentIndex;
    Rect? hole;
    // Mid-slide the scale is off the step's; that's travel, not a pinch: keep the hole.
    if (settings.panelDim && k > 0 && (_panAnim.isAnimating || !_offStep) && _panelActive(page, settings)) {
      final on = _panelRectOnScreen(page, k, MediaQuery.sizeOf(context));
      if (on != null) hole = MatrixUtils.transformRect(_transformController.value, on);
    }
    return PanelDimOverlay(hole: hole);
  }

  /// Art (page px²) a pop-out at a screen rect would hide on [page] under
  /// transform [m], not counting the balloon's own spot [own] (page px).
  double Function(Rect)? _artCost(int page, Matrix4 m, Rect own) {
    final art = _bubbleArt[page], pb = _bubbles[page];
    final display = _displayRectFor(page, MediaQuery.sizeOf(context));
    if (art == null || pb == null || display == null) return null;
    final s = display.width / pb.width;
    final toPage = Matrix4.tryInvert(
      m.clone()
        ..translateByDouble(display.left, display.top, 0, 1)
        ..scaleByDouble(s, s, 1, 1),
    );
    if (toPage == null) return null;
    return (r) => art.cover(MatrixUtils.transformRect(toPage, r), except: own);
  }

  /// What [_recalculateTransforms] will apply when [page] becomes current.
  /// Drives the incoming fade overlay. Null when the page's size is unknown.
  Matrix4? _landingTransformFor(int page, Size viewport) {
    final settings = ref.read(settingsProvider).value ?? const ReaderSettings();
    if (settings.zoomLock && _lockedTransform != null) return _lockedTransform;
    final dims = _imageDimensions[page];
    if (dims == null) return null;
    final transforms = _stepsFor(page, dims.$1, dims.$2, viewport, settings);
    if (transforms.isEmpty) return null;
    return _landAtEnd ? transforms.last : transforms.first;
  }

  /// Width / height of [page] if its size is known, else of any page seen
  /// (a comic's pages are nearly all one shape), else a typical 2:3.
  double _knownPageAspect(int page) {
    final d = _imageDimensions[page] ??
        (_imageDimensions.isEmpty ? null : _imageDimensions.values.first);
    return d == null || d.$2 == 0 ? 2 / 3 : d.$1 / d.$2;
  }

  /// [keepPlace]: the steps are being rebuilt for the page already on screen
  /// (a setting or the orientation changed), so land on the step showing
  /// what was in view instead of the page's first step.
  void _recalculateTransforms(int page, int imageWidth, int imageHeight,
      {bool instant = false, bool keepPlace = false}) {
    if (!mounted) return;
    final size = MediaQuery.sizeOf(context);
    final settings = ref.read(settingsProvider).value ?? const ReaderSettings();
    final transforms = _stepsFor(page, imageWidth, imageHeight, size, settings);
    final previous = _transformController.value.clone();

    _panController.setTransforms(transforms);
    // ponytail: after a rotation `previous` was framed for the old viewport;
    // inverting it at the new centre is close enough to pick a step.
    if (keepPlace) _panController.jumpToNearest(previous, size);
    final pb = _bubbles[page];
    if (pb != null) _bubbleSteps[page] = bubbleGroups(pb, _bubbleMasks[page]);
    if (_landAtEnd) {
      _landAtEnd = false;
      _panController.jumpToEnd();
    }
    if (instant) {
      _transformController.value = _panController.currentTransform;
    } else {
      _animateTo(_panController.currentTransform);
    }
  }

  /// Turn the page directly via PageController instead of going through the
  /// provider→rebuild→sync path. [delta] is +1 (forward) or -1 (backward).
  /// The PageView's onPageChanged callback updates the provider state.
  /// Returns false when there was no page to turn to.
  bool _turnPage(int delta, ReaderSettings settings) {
    _noteReaderActivity();
    if (!_pageController.hasClients) return false;
    final current = _pageController.page?.round() ?? 0;
    final target = current + delta;
    final pageCount =
        ref.read(readerProvider(_readerKey)).value?.info?.pageCount ?? 0;
    final hasSeriesContext =
        ref.read(readerProvider(_readerKey)).value?.hasSeriesContext == true;
    final maxTarget = hasSeriesContext ? pageCount : pageCount - 1;
    if (target < 0 || target > maxTarget) return false;

    if (settings.pageAnimation == 'fade') {
      _pageReaderKey.currentState?.fadeToPage(target);
    } else if (settings.pageAnimation == 'none') {
      _pageController.jumpToPage(target);
    } else {
      _pageController.animateToPage(
        target,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOutCubic,
      );
    }
    return true;
  }

  /// Turn to the previous page in reading order and land on its last step.
  /// The flag is set first because 'none' fires onPageChanged synchronously.
  void _turnPageBack(int delta, ReaderSettings settings) {
    _landAtEnd = true;
    if (!_turnPage(delta, settings)) _landAtEnd = false;
  }

  void _animateTo(Matrix4 target) {
    if (!mounted) return;
    final begin = _transformController.value.clone();
    _panTween = Matrix4Tween(begin: begin, end: target).animate(
      CurvedAnimation(parent: _panAnim, curve: Curves.easeInOut),
    );
    _panAnim.forward(from: 0.0);
  }

  /// Every jump lands here: scrubber release, thumbnail, go-to field, page
  /// grid, chapter list, remote `goto`. Offers the Back chip and holds saved
  /// progress at the origin until the reader reads on.
  void _jumpToPage(int page) {
    final state = ref.read(readerProvider(_readerKey)).value;
    final from = state?.currentPage ?? 0;
    final to = _moveTo(page);
    final scroll = ref.read(settingsProvider).value?.readingMode == 'scroll';
    // ponytail: scroll mode doesn't move the view on a jump (known gap), so
    // no chip there. The end card completes the issue, so it isn't undoable.
    if (to == from || scroll || to >= (state?.info?.pageCount ?? 0)) return;
    final origin = _jumpOrigin ?? from;
    setState(() {
      _jumpOrigin = origin;
      _jumpUndone = to == origin;
      _jumpTarget = to == origin ? from : to;
      _jumpTurns = 0;
    });
    ref.read(readerProvider(_readerKey).notifier).holdProgressAt(origin);
  }

  /// Move to [page] (provider state + PageController for page mode +
  /// prefetch warm-up) without offering the chip. Returns the landed page.
  int _moveTo(int page) {
    final settings =
        ref.read(settingsProvider).value ?? const ReaderSettings();
    final notifier = ref.read(readerProvider(_readerKey).notifier);
    final from = ref.read(readerProvider(_readerKey)).value?.currentPage ?? 0;
    notifier.goToPage(page);
    // Follow the provider's clamped result rather than the caller's number.
    // goToPage() already bounds the page; jumping the PageController to the
    // raw value desynced the view from the state, and `page` can come off
    // the network (a remote `goto`) where nothing validated it at all.
    final target = ref.read(readerProvider(_readerKey)).value?.currentPage ?? 0;
    // Set before jumpToPage, whose onPageChanged must not count as a turn.
    _jumpAt = target;
    _sessionTracker.jumped(from, target);
    if (settings.readingMode != 'scroll') {
      _pageController.jumpToPage(target);
    }
    _prefetcher?.onPageJump(
      targetPage: target,
      rtl: settings.readingDirection == 'rtl',
      context: context,
    );
    return target;
  }

  /// The chip: back to the origin, or forward again. Never a new origin.
  void _toggleJump() {
    final dest = _jumpUndone ? _jumpTarget : _jumpOrigin!;
    _moveTo(dest);
    setState(() {
      _jumpUndone = !_jumpUndone;
      _jumpTurns = 0;
    });
  }

  /// Chip gone (×, read on, issue done): progress saves the current page again.
  void _dismissJump() {
    if (_jumpOrigin == null) return;
    if (mounted) setState(() => _jumpOrigin = null);
    ref.read(readerProvider(_readerKey).notifier).holdProgressAt(null);
  }

  /// An ordinary page turn landed on [page]; three of them dismiss the chip.
  void _countTurn(int page) {
    if (_jumpOrigin == null || page == _jumpAt) return;
    _jumpAt = page;
    if (++_jumpTurns >= 3) _dismissJump();
  }

  Widget? _buildJumpChip() {
    final origin = _jumpOrigin;
    if (origin == null) return null;
    return JumpBackChip(
      page: (_jumpUndone ? _jumpTarget : origin) + 1,
      forward: _jumpUndone,
      onTap: _toggleJump,
      onDismiss: _dismissJump,
    );
  }

  Future<void> _openPageGrid() async {
    final state = ref.read(readerProvider(_readerKey)).value;
    if (state == null) return;
    final pageCount = state.info?.pageCount ?? 0;
    if (pageCount <= 0) return;
    final client = ref.read(apiClientProvider);
    final selected = await Navigator.of(context).push<int>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => PageGridOverlay(
          totalPages: pageCount,
          currentPage: state.currentPage,
          pageUrlBuilder: (p) => client.pageUrl(widget.comicId, p),
          localPagesPath: _localPagesPath,
          bookmarkPages: state.bookmarks.map((b) => b.pageNum).toList(),
          chapters: mergeChapters(
            comicInfo: state.info?.chapters ?? const [],
            user: state.chapters,
          ),
          onAddChapter: (page) =>
              ref.read(readerProvider(_readerKey).notifier).addChapter(page, ''),
        ),
      ),
    );
    if (selected == null || !mounted) return;
    _jumpToPage(selected);
  }

  void _openChapterList() {
    final state = ref.read(readerProvider(_readerKey)).value;
    if (state == null) return;
    final notifier = ref.read(readerProvider(_readerKey).notifier);
    final merged = mergeChapters(
      comicInfo: state.info?.chapters ?? const [],
      user: state.chapters,
    );
    showChapterListSheet(
      context,
      chapters: merged,
      currentPage: state.currentPage,
      onJump: _jumpToPage,
      onAdd: notifier.addChapter,
      onRename: notifier.renameChapter,
      onDelete: notifier.deleteChapter,
      onDetect: ref.read(isCustomSourceProvider) ? _detectChapters : null,
    );
  }

  void _detectChapters() {
    final st = ref.read(readerProvider(_readerKey)).value;
    final title = st?.info?.title.trim().isNotEmpty == true ? st!.info!.title : 'comic';
    ref.read(scanProvider.notifier).start(
          comicId: widget.comicId,
          title: title,
          exemplarPage: st?.currentPage,
        );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Scanning for chapters in the background…')),
      );
    }
  }

  void _handleVolumeUp() {
    // If we're parked on the end card, treat volume-up as "next issue".
    final state = ref.read(readerProvider(_readerKey)).value;
    final pageCount = state?.info?.pageCount ?? 0;
    final onEndCard = state != null &&
        state.hasSeriesContext &&
        pageCount > 0 &&
        state.currentPage == pageCount;
    if (onEndCard && _nextReadable(state).issue != null) {
      _advanceToNextIssue();
      return;
    }

    final result = _panController.advance();
    if (result == PanResult.viewportChanged) {
      _animateTo(_panController.currentTransform);
    } else if (result == PanResult.sequenceEnd) {
      final settings = ref.read(settingsProvider).value ?? const ReaderSettings();
      if (settings.readingDirection == 'rtl') {
        _turnPage(-1, settings);
      } else {
        _turnPage(1, settings);
      }
    }
  }

  /// The issue "Next" opens. Online: the next in the series. Offline: the
  /// next one on the device, with [skipped] = the one in order that isn't.
  ({SeriesIssue? issue, int index, SeriesIssue? skipped}) _nextReadable(
      ReaderState state) {
    final issues = state.seriesIssues;
    final cur = state.currentIssueIndex;
    if (issues == null || cur == null || cur + 1 >= issues.length) {
      return (issue: null, index: -1, skipped: null);
    }
    if (ref.read(connectivityProvider)) {
      return (issue: issues[cur + 1], index: cur + 1, skipped: null);
    }
    final onDevice = ref.read(onDeviceProvider).comicIds;
    final skipped = onDevice.contains(issues[cur + 1].id) ? null : issues[cur + 1];
    for (var i = cur + 1; i < issues.length; i++) {
      if (onDevice.contains(issues[i].id)) {
        return (issue: issues[i], index: i, skipped: skipped);
      }
    }
    return (issue: null, index: -1, skipped: skipped);
  }

  WidgetBuilder? _buildEndCardBuilder(ReaderState state) {
    if (!state.hasSeriesContext) return null;

    final issues = state.seriesIssues!;
    final baseReadCount = issues.where((i) {
      final cp = i.currentPage;
      final tp = i.totalPages;
      return cp != null && tp != null && tp > 0 && cp >= tp;
    }).length;
    // The seriesIssues snapshot is captured at reader-open time, so the
    // current issue isn't reflected as read even after we mark it complete.
    // If the user is on the end card, count the current issue too.
    final pageCount = state.info?.pageCount ?? 0;
    final onEndCard = pageCount > 0 && state.currentPage == pageCount;
    final readCount = onEndCard
        ? (baseReadCount + 1).clamp(0, issues.length)
        : baseReadCount;

    final info = state.info;
    final currentTitle = info?.title ?? state.comicPath.split('/').last;
    final currentSeries = _seriesName ?? info?.series ?? '';
    final source = ref.read(activeSourceProvider);
    final baseUrl = source.baseUrl;
    final currentCover = ref.read(issueCoverUrlProvider(state.comicId));

    // Server returns relative cover URLs (e.g. "/comics/<id>/cover"); resolve
    // against the active source baseUrl so CachedNetworkImage can fetch it.
    final readable = _nextReadable(state);
    final rawNext = readable.issue;
    final skipped = readable.skipped;
    final resolvedNext = rawNext == null
        ? null
        : SeriesIssue(
            id: rawNext.id,
            name: rawNext.name,
            number: rawNext.number,
            coverUrl: rawNext.coverUrl.isEmpty ||
                    rawNext.coverUrl.startsWith('http')
                ? rawNext.coverUrl
                : '$baseUrl${rawNext.coverUrl}',
            status: rawNext.status,
            currentPage: rawNext.currentPage,
            totalPages: rawNext.totalPages,
          );

    return buildEndCardPageBuilder(
      currentIssueTitle: currentTitle,
      currentSeriesName: currentSeries,
      currentCoverUrl: currentCover,
      readCount: readCount,
      totalCount: issues.length,
      nextIssue: resolvedNext,
      offlineNote: skipped == null
          ? null
          : '${skipped.number != null && skipped.number!.isNotEmpty ? '#${skipped.number}' : skipped.name} isn\'t on this ${LayoutBreakpoint.deviceNoun}',
      onNext: _advanceToNextIssue,
      onBackToSeries: () async {
        await _markCurrentCompletedAndFlushSession();
        if (mounted) Navigator.of(context).pop();
        unawaited(ReviewPrompt.maybeAsk());
      },
      onClose: () async {
        await _markCurrentCompletedAndFlushSession();
        if (mounted) Navigator.of(context).pop();
        unawaited(ReviewPrompt.maybeAsk());
      },
    );
  }

  Future<void> _markCurrentCompletedAndFlushSession() async {
    if (_completionFlushed) return;
    _completionFlushed = true;
    // Reached the end: drop the chip, the hold and any queued mid-issue save,
    // so nothing written after this can undo the completion.
    if (_jumpOrigin != null && mounted) setState(() => _jumpOrigin = null);
    ref.read(readerProvider(_readerKey).notifier)
        .releaseHold(cancelPendingSave: true);
    final state = ref.read(readerProvider(_readerKey)).value;
    final pageCount = state?.info?.pageCount ?? 0;
    if (pageCount > 0) {
      unawaited(ReviewPrompt.recordFinish());
      // Local-first: mark completed in the mirror so shelves update instantly
      // even if the network write fails.
      await ref.read(mirrorDbProvider).saveProgressLocal(
            comicId: _comicId,
            currentPage: pageCount,
            totalPages: pageCount,
          );
      for (final q in await ref
          .read(mirrorDbProvider)
          .autoRemoveOnComplete(_comicId)) {
        await ref
            .read(syncQueueProvider)
            ?.enqueue({'type': 'queue_upsert', 'payload': q.toSyncJson()});
      }
      final client = ref.read(apiClientProvider);
      try {
        // The cancelled debounce may have been carrying a fresh bookmark.
        await client.updateProgress(
          comicId: _comicId,
          currentPage: pageCount,
          totalPages: pageCount,
          bookmarks: state?.bookmarks,
        );
      } catch (_) {
        // Offline (or PUT failed): queue the completion so the next sync push
        // delivers it — and so the sync pull won't revert the local row.
        await ref.read(syncQueueProvider)?.enqueue({
          'type': 'progress',
          'payload': {
            'comic_id': _comicId,
            'current_page': pageCount,
            'total_pages': pageCount,
            'bookmarks': [...?state?.bookmarks.map((b) => b.toJson())],
          },
        });
      }
    }
    final currentPage =
        _lastReaderStateCapture?.currentPage ?? widget.initialPage;
    _sessionTracker.endSessionWithPage(currentPage);
  }

  Future<void> _advanceToNextIssue() async {
    // Read the next issue from current state before doing anything
    final currentState = ref.read(readerProvider(_readerKey)).value;
    if (currentState == null) return;
    final readable = _nextReadable(currentState);
    final next = readable.issue;
    if (next == null || !mounted) return;

    // Mark current comic as completed + flush session via the shared helper.
    await _markCurrentCompletedAndFlushSession();

    if (!mounted) return;

    // Push a fresh ReaderScreen — guarantees clean state (controllers,
    // animations, tap zones) via the normal widget lifecycle.
    final newIndex = readable.index;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        settings: const RouteSettings(name: '/reader'),
        transitionDuration: const Duration(milliseconds: 250),
        reverseTransitionDuration: const Duration(milliseconds: 250),
        pageBuilder: (_, _, _) => ReaderScreen(
          comicId: next.id,
          comicPath: next.name,
          seriesIssues: currentState.seriesIssues,
          currentIssueIndex: newIndex,
          seriesId: _seriesId,
          seriesName: _seriesName,
        ),
        transitionsBuilder: (_, animation, _, child) => FadeTransition(
          opacity: CurvedAnimation(parent: animation, curve: Curves.easeInOut),
          child: child,
        ),
      ),
    );
  }

  void _handleVolumeDown() {
    final result = _panController.retreat();
    if (result == PanResult.viewportChanged) {
      _animateTo(_panController.currentTransform);
    } else if (result == PanResult.sequenceStart) {
      final settings = ref.read(settingsProvider).value ?? const ReaderSettings();
      _turnPageBack(settings.readingDirection == 'rtl' ? 1 : -1, settings);
    }
  }

  void _handleOverscroll(EdgeDirection direction) {
    // Only handle when in a multi-step sequence — otherwise PageView's swipe
    // owns horizontal navigation and we'd double-fire page turns.
    if (!_panController.hasMultipleSteps) return;

    final settings = ref.read(settingsProvider).value ?? const ReaderSettings();
    final isRtl = settings.readingDirection == 'rtl';

    // Map physical edge to logical advance/retreat. RTL inverts.
    final shouldAdvance = isRtl
        ? direction == EdgeDirection.leftEdge
        : direction == EdgeDirection.rightEdge;

    if (shouldAdvance) {
      final result = _panController.advance();
      if (result == PanResult.viewportChanged) {
        _animateTo(_panController.currentTransform);
      } else if (result == PanResult.sequenceEnd) {
        _turnPage(isRtl ? -1 : 1, settings);
      }
    } else {
      final result = _panController.retreat();
      if (result == PanResult.viewportChanged) {
        _animateTo(_panController.currentTransform);
      } else if (result == PanResult.sequenceStart) {
        _turnPageBack(isRtl ? 1 : -1, settings);
      }
    }
  }

  void _saveSettings(ReaderSettings next, ReaderSettings prev) {
    ref.read(settingsProvider.notifier).save(next);
    if (next.keepScreenOn != prev.keepScreenOn) {
      _screenController.setKeepScreenOn(next.keepScreenOn);
    }
  }

  /// Phone host for the Aa panel: a glass sheet rounded only on top.
  void _showQuickSettings(BuildContext context, ReaderSettings settings) {
    setState(() => _quickSettingsOpen = true);
    // The sheet never rebuilds with fresh settings, so track the last edit
    // here: the sleep timer / keep-on re-arm only when they actually change.
    var prev = settings;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: context.scheme.scrim,
      isScrollControlled: true,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      builder: (_) => LiquidGlass(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
        padding: const EdgeInsets.only(top: 10),
        child: SafeArea(
          top: false,
          child: ReaderAaPanel(
            settings: settings,
            onChanged: (next) {
              _saveSettings(next, prev);
              prev = next;
            },
          ),
        ),
      ),
    ).whenComplete(() {
      // Clear on dismissal, however the sheet closed (tap-out or drag) —
      // otherwise the Aa pill stays lit for the session.
      if (mounted) setState(() => _quickSettingsOpen = false);
    });
  }

  /// Series name + issue number, e.g. "Batman #80".
  String _topBarTitle(ComicInfo? info) {
    final name = _seriesName ?? info?.series ?? info?.title ?? '';
    final number = info?.number;
    return number == null || number.isEmpty ? name : '$name #$number';
  }

  /// The issue's own title when it has one, else the current chapter's.
  String? _topBarLead(ReaderState state) {
    final own = state.info?.title.trim() ?? '';
    final series = _seriesName ?? state.info?.series ?? '';
    if (own.isNotEmpty && own != series) return own;
    return chapterTitleAt(
      mergeChapters(
        comicInfo: state.info?.chapters ?? const [],
        user: state.chapters,
      ),
      state.currentPage,
    );
  }

  /// Phone: popovers hang 6pt below the 52pt top bar (8pt under the safe
  /// area), inset 12pt plus the bar's 8pt end padding. iPad: they open
  /// beside the rail, level with its top.
  double get _popoverTop => LayoutBreakpoint.isTablet(context)
      ? MediaQuery.paddingOf(context).top + ReaderTopBar.railTop
      : MediaQuery.paddingOf(context).top + 66;
  double? get _popoverRight => !LayoutBreakpoint.isTablet(context)
      ? 20
      : _railOnLeft
          ? null
          : MediaQuery.paddingOf(context).right + _besideRail;
  double? get _popoverLeft => LayoutBreakpoint.isTablet(context) && _railOnLeft
      ? MediaQuery.paddingOf(context).left + _besideRail
      : null;
  static const _besideRail =
      ReaderTopBar.railMargin + ReaderTopBar.railWidth + 8;
  bool get _railOnLeft => ref.read(railSideProvider) == RailSide.left;

  /// Save progress and leave: the toolbar's close and the left-edge swipe.
  Future<void> _exitReader() async {
    await ref.read(readerProvider(_readerKey).notifier).saveProgressNow();
    if (mounted) Navigator.of(context).pop();
  }


  ReaderMoreMenu _moreMenu() {
    final hasSeries = _seriesId != null && _seriesId!.isNotEmpty;
    final scrollMode =
        ref.read(settingsProvider).value?.readingMode == 'scroll';
    final flagPage = _flaggablePage();
    final fixPage = _fixablePage();
    // Chapters and clipping need a Gutter server's detection.
    final gutter = ref.read(isCustomSourceProvider);
    return ReaderMoreMenu(
      onChapters: gutter ? _openChapterList : null,
      onAllPages: _openPageGrid,
      onRecap: hasSeries && !isStore ? _openRecap : null,
      // Clipping crops a paged page; scroll mode has none to crop.
      onClipPanel: scrollMode || !gutter ? null : _armClip,
      onIssueDetails: hasSeries ? _openIssueDetails : null,
      onFlagPage: flagPage == null ? null : () => _flagPage(flagPage),
      onFixPanels:
          fixPage == null ? null : () => _fixPage(fixPage, LabelMode.panels),
      onFixBalloons:
          fixPage == null ? null : () => _fixPage(fixPage, LabelMode.balloons),
      onCredits: _showCredits,
    );
  }

  void _showMoreMenu() {
    setState(() => _moreOpen = true);
    final menu = _moreMenu();
    // A route we hold, so hideChrome can close it (showGeneralDialog's
    // RawDialogRoute, built directly).
    final route = _moreRoute = RawDialogRoute<void>(
      barrierDismissible: true,
      barrierLabel: 'Close menu',
      barrierColor: context.scheme.scrim,
      transitionDuration: const Duration(milliseconds: 150),
      pageBuilder: (_, _, _) => Stack(
        children: [
          Positioned(
            top: _popoverTop,
            left: _popoverLeft,
            right: _popoverRight,
            child: menu,
          ),
        ],
      ),
      transitionBuilder: (_, anim, _, child) =>
          FadeTransition(opacity: anim, child: child),
    );
    Navigator.of(context).push(route).whenComplete(() {
      if (_moreRoute == route) _moreRoute = null;
      if (mounted) setState(() => _moreOpen = false);
    });
  }

  void _openRecap() => Navigator.of(context).push(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => RecapScreen(seriesId: _seriesId!),
        ),
      );

  /// The page a flag would name: only with panel or bubble zoom on, in paged
  /// mode, on a real page (not the end card). Null when flagging is off.
  int? _flaggablePage() {
    // Flags feed a Gutter server's labeller: personal builds only.
    if (isStore || !ref.read(isCustomSourceProvider)) return null;
    final settings = ref.read(settingsProvider).value ?? const ReaderSettings();
    if (settings.zoomMode == 'off' || settings.readingMode != 'page') return null;
    final reader = ref.read(readerProvider(_readerKey)).value;
    final page = reader?.currentPage;
    if (page == null || page >= (reader?.info?.pageCount ?? 0)) return null;
    return page;
  }

  void _onTwoFingerTap() {
    final page = _flaggablePage();
    if (page != null) _flagPage(page);
  }

  /// Asks what's wrong, then sends the page to the detector's labelling queue;
  /// the page itself stays as it is until a retrained detector ships.
  Future<void> _flagPage(int page) async {
    hideChrome();
    final zoom = (ref.read(settingsProvider).value ?? const ReaderSettings()).zoomMode;
    final reason = await showFlagReasonCard(context, zoom: zoom, page: page);
    if (reason == null || !mounted) return;
    try {
      await ref.read(apiClientProvider).flagPage(_comicId, page, reason: reason, zoom: zoom);
      if (mounted) _clipHint('Flagged page ${page + 1}');
    } catch (_) {
      if (mounted) _clipHint("Couldn't flag this page — is the server reachable?");
    }
  }

  /// The page a Fix… item would act on: like [_flaggablePage] but without
  /// the zoom-mode requirement — fixing doesn't need panel/bubble zoom on.
  int? _fixablePage() {
    // The labeller is a Gutter server's, and personal builds only.
    if (isStore || !ref.read(isCustomSourceProvider)) return null;
    final settings = ref.read(settingsProvider).value ?? const ReaderSettings();
    if (settings.readingMode != 'page') return null;
    final reader = ref.read(readerProvider(_readerKey)).value;
    final page = reader?.currentPage;
    if (page == null || page >= (reader?.info?.pageCount ?? 0)) return null;
    return page;
  }

  /// Flags [page] under [mode]'s reason, imports it into the labeller's
  /// queue, then opens the labeller straight to that one page.
  Future<void> _fixPage(int page, LabelMode mode) async {
    hideChrome();
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AlertDialog(
        content: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 16),
            Text('Adding page to the label set…'),
          ],
        ),
      ),
    );
    try {
      final id = await fixPageId(
        api: ref.read(apiClientProvider),
        labels: ref.read(labelClientProvider),
        comicId: _comicId,
        page: page,
        mode: mode,
      );
      if (!mounted) return;
      Navigator.of(context).pop();
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => LabelScreen(singleId: id, initialMode: mode),
        ),
      );
    } on LabelImportMissing {
      if (!mounted) return;
      Navigator.of(context).pop();
      _clipHint("This page can't be added to the label set");
    } on LabelFlagFailed {
      if (!mounted) return;
      Navigator.of(context).pop();
      _clipHint("Couldn't flag this page — is the server reachable?");
    } catch (_) {
      if (!mounted) return;
      Navigator.of(context).pop();
      _clipHint("Couldn't reach the label server");
    }
  }

  void _armClip() {
    hideChrome();
    setState(() => _clipArmed = true);
    _clipHint('Tap a panel to clip it');
  }

  /// The issue's series page, pushed over the reader so Back returns to the
  /// comic on the same page.
  Future<void> _openIssueDetails() async {
    if (_seriesId == null || _seriesId!.isEmpty) return;
    hideChrome();
    await ref.read(readerProvider(_readerKey).notifier).saveProgressNow();
    if (!mounted) return;
    // The series page covers the reader: show the status bar, stop counting
    // reading time and release the wakelock until it pops. The sleep
    // deadline keeps running.
    final page = _lastReaderStateCapture?.currentPage ?? widget.initialPage;
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    _sessionTracker.pause(page);
    _screenController.setKeepScreenOn(false);
    _awayFromReader = true;
    final result = await Navigator.of(context).push(MaterialPageRoute<String>(
      settings: const RouteSettings(name: '/series-detail'),
      builder: (_) =>
          SeriesDetailScreen(seriesId: _seriesId!, fromReader: true),
    ));
    _awayFromReader = false;
    // 'replaced': an issue was opened and this reader is about to be swapped
    // out — the new reader arms all of this itself.
    if (!mounted || result == SeriesDetailScreen.replacedResult) return;
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersive);
    _sessionTracker.resume(
        _lastReaderStateCapture?.currentPage ?? widget.initialPage);
    // Back to reading: restore per the setting whether or not the timer
    // fired meanwhile, and show a warning that came due on the series page.
    _restoreWakelock();
    _showWarningIfInLead();
  }

  /// Reader "..." menu entry: the issue's credits, server-sourced when
  /// ComicVine enrichment has them, else from the raw ComicInfo fields.
  /// Styling mirrors `_showQuickSettings`; tapping a row leaves the reader
  /// the same way `_openIssueDetails` does, via [_openCreatorFromSheet].
  void _showCredits() {
    final reader = ref.read(readerProvider(_readerKey)).value;
    final fallbackTitle =
        stripComicExtension((reader?.comicPath ?? _comicPath).split('/').last);
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: context.scheme.scrim,
      isScrollControlled: true,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      builder: (_) => LiquidGlass(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
        padding: const EdgeInsets.only(top: 10),
        child: SafeArea(
          top: false,
          child: IssueCreditsSheet(
            comicId: _comicId,
            info: reader?.info,
            title: fallbackTitle,
            // Creator pages come from a Gutter server's credits index.
            onOpen: ref.read(isCustomSourceProvider)
                ? (id, name) => _openCreatorFromSheet(id, name)
                : null,
          ),
        ),
      ),
    );
  }

  /// Leaves the reader to show a creator page, then restores reader chrome
  /// on return — the credits-sheet equivalent of `_openIssueDetails`.
  Future<void> _openCreatorFromSheet(int id, String name) async {
    hideChrome();
    await ref.read(readerProvider(_readerKey).notifier).saveProgressNow();
    if (!mounted) return;
    final page = _lastReaderStateCapture?.currentPage ?? widget.initialPage;
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    _sessionTracker.pause(page);
    _screenController.setKeepScreenOn(false);
    _awayFromReader = true;
    await openCreator(context, ref, id: id, name: name);
    _awayFromReader = false;
    if (!mounted) return;
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersive);
    _sessionTracker.resume(
        _lastReaderStateCapture?.currentPage ?? widget.initialPage);
    _restoreWakelock();
    _showWarningIfInLead();
  }

  @override
  Widget build(BuildContext context) {
    final readerAsync = ref.watch(readerProvider(_readerKey));
    final settingsAsync = ref.watch(settingsProvider);
    final settings = settingsAsync.value ?? const ReaderSettings();
    final client = ref.watch(apiClientProvider);

    // Capture for dispose() — ref is invalid after unmount
    _autoCleanupCapture = ref.watch(autoCleanupDownloadsProvider);
    _sourceIdCapture = ref.watch(activeSourceProvider).id;
    _downloadManagerCapture = ref.watch(downloadManagerProvider);
    _sessionTracker.updateCaptures(
      client: client,
      syncQueue: ref.watch(syncQueueProvider),
    );

    // Wait for both reader data and settings before showing content
    // Spinner only before the first value: a refresh with data in hand must
    // not unmount the PageView, or the remount lands on the provider's page.
    if ((settingsAsync.isLoading && !settingsAsync.hasValue) ||
        (readerAsync.isLoading && !readerAsync.hasValue)) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    // Scroll mode has no first-page signal; its own placeholders show.
    if (settings.readingMode == 'scroll') CoverReveal.of(context)?.ready();

    return Scaffold(
      backgroundColor: _bgColor(settings.theme),
      // The keyboard (Claude panel) must not shrink and refit the comic;
      // the panel ends above it on its own.
      resizeToAvoidBottomInset: false,
      body: readerAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        // Store users get plain words; personal builds keep the raw error.
        error: (e, _) => _deadEnd(context, isStore
            ? 'Couldn\'t open this comic. Check your connection and try again.'
            : 'Couldn\'t open this comic.\n$e'),
        data: (readerState) {
          final pageCount = readerState.info?.pageCount ?? 0;
          if (pageCount == 0) {
            return _deadEnd(
                context,
                ref.watch(connectivityProvider)
                    ? 'This comic has no pages.'
                    : 'Not on this ${LayoutBreakpoint.deviceNoun}, and you\'re offline.');
          }
          return _buildReaderBody(
              context, readerState, settings, pageCount, client);
        },
      ),
    );
  }

  /// A reader that can't show pages never strands you: why, and a way out.
  Widget _deadEnd(BuildContext context, String message) {
    CoverReveal.of(context)?.ready();
    return SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off_rounded,
                  size: 40, color: Colors.white54),
              const SizedBox(height: 16),
              Text(message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70, fontSize: 16)),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.arrow_back_rounded),
                label: const Text('Back'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildReaderBody(
    BuildContext context,
    ReaderState readerState,
    ReaderSettings settings,
    int pageCount,
    ApiClient client,
  ) {
    _lastReaderStateCapture = readerState;

    final isRtl = settings.readingDirection == 'rtl';

    // Recalculate transforms when orientation, direction, mode, or fit changes
    final screenSize = MediaQuery.sizeOf(context);
    final isPortrait = screenSize.height > screenSize.width;
    final orientationChanged = _lastPortrait != null && _lastPortrait != isPortrait;
    final directionChanged = _lastReadingDirection != null &&
        _lastReadingDirection != settings.readingDirection;
    final modeChanged = _lastReadingMode != null &&
        _lastReadingMode != settings.readingMode;
    final fitChanged = _lastPageFit != null &&
        _lastPageFit != settings.pageFit;
    // Scroll mode has no chip (no turn counting there): drop it, as × would.
    if (modeChanged && settings.readingMode == 'scroll' && _jumpOrigin != null) {
      _jumpOrigin = null;
      ref.read(readerProvider(_readerKey).notifier).holdProgressAt(null);
    }
    if (orientationChanged || directionChanged || modeChanged || fitChanged) {
      // Use PageController as source of truth — provider state may be stale
      // due to the 2-second save debounce.
      final controllerPage = _pageController.hasClients
          ? (_pageController.page?.round() ?? readerState.currentPage)
          : readerState.currentPage;
      if (controllerPage != readerState.currentPage) {
        ref.read(readerProvider(_readerKey).notifier).goToPage(controllerPage);
      }
      final dims = _imageDimensions[controllerPage];
      if (dims != null && !_pendingPostFrame) {
        _pendingPostFrame = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _pendingPostFrame = false;
          if (mounted) {
            _recalculateTransforms(controllerPage, dims.$1, dims.$2,
                keepPlace: true);
          }
        });
      }
    }
    _lastPortrait = isPortrait;
    _lastReadingDirection = settings.readingDirection;
    _lastReadingMode = settings.readingMode;
    _lastPageFit = settings.pageFit;

    // Sync page controller to state changes
    if (!_pendingPostFrame) {
      _pendingPostFrame = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _pendingPostFrame = false;
        if (!mounted || !_pageController.hasClients) return;
        final current = _pageController.page?.round() ?? 0;
        // On first frame, update provider to match initialPage rather than
        // jumping controller to provider's default (0)
        if (!_initialPageApplied) {
          _initialPageApplied = true;
          if (widget.initialPage > 0 && current == widget.initialPage) {
            ref.read(readerProvider(_readerKey).notifier).goToPage(widget.initialPage);
            return;
          }
        }
        if (current != readerState.currentPage) {
          if (settings.pageAnimation == 'fade') {
            // Only trigger fade if not already mid-fade
            final pageReaderState = _pageReaderKey.currentState;
            if (pageReaderState != null && !pageReaderState.isFading) {
              pageReaderState.fadeToPage(readerState.currentPage);
            }
          } else if (settings.pageAnimation == 'slide') {
            _pageController.animateToPage(
              readerState.currentPage,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOutCubic,
            );
          } else {
            _pageController.jumpToPage(readerState.currentPage);
          }
        }
      });
    }

    final source = ref.read(activeSourceProvider);
    _prefetcher ??= PagePrefetcher(
      totalPages: pageCount,
      pageUrlBuilder: (p) => client.pageUrl(_comicId, p),
      headersFor: (url) => imageHeadersFor(source, url),
    );

    final jumpChip = _buildJumpChip();
    final isTablet = LayoutBreakpoint.isTablet(context);
    final railOnLeft = ref.watch(railSideProvider) == RailSide.left;
    final topBar = ReaderTopBar(
      rail: isTablet,
      railOnLeft: railOnLeft,
      title: _topBarTitle(readerState.info),
      subtitleLead: _topBarLead(readerState),
      pagesLeft: (pageCount - readerState.currentPage - 1)
          .clamp(0, pageCount),
      accent: accent,
      isBookmarked: ref
          .read(readerProvider(_readerKey).notifier)
          .isBookmarked(readerState.currentPage),
      isSettingsOpen: _quickSettingsOpen,
      isMoreOpen: _moreOpen,
      onClose: _exitReader,
      onBookmark: () {
        ref
            .read(readerProvider(_readerKey).notifier)
            .toggleBookmark(readerState.currentPage);
        setState(() {});
      },
      onSettings: () {
        if (LayoutBreakpoint.isTablet(context)) {
          setState(() => _quickSettingsOpen = !_quickSettingsOpen);
        } else {
          _showQuickSettings(context, settings);
        }
      },
      onMore: _showMoreMenu,
      // A short menu isn't worth a tap: its items go straight on the bar.
      inlineMore: switch (_moreMenu().items) {
        final items when items.length <= ReaderMoreMenu.inlineMax => items,
        _ => null,
      },
      sleepRemaining: () => SleepTimer.instance.remaining,
      onSleepTimer: _onMoonTap,
      claudeMode: _claudeMode,
      // The Claude panel needs the server: no button offline. Personal only.
      onClaude: !isStore && ref.watch(connectivityProvider)
          ? () => setState(() {
                _claudeOpened = true;
                _claudeMode = _claudeMode.next;
              })
          : null,
      onTitleTap: _seriesId != null && _seriesId!.isNotEmpty
          ? _openIssueDetails
          : null,
    );

    final stack = Stack(
      children: [
        // Main content
        if (settings.readingMode == 'scroll')
          NotificationListener<ScrollUpdateNotification>(
            onNotification: (notification) {
              hideChrome();
              return false;
            },
            child: ScrollReader(
              pageCount: pageCount,
              pageUrlBuilder: (p) => client.pageUrl(_comicId, p),
              localPagesPath: _localPagesPath,
              prefetcher: _prefetcher,
              rtl: isRtl,
              endCardBuilder: _buildEndCardBuilder(readerState),
              // The page being read: the provider holds it once either mode
              // has synced; before that (opened straight into scroll) it's
              // still at 0, so use the page the reader was opened at.
              initialPage: _initialPageApplied || _scrollReported
                  ? readerState.currentPage
                  : widget.initialPage,
              pageAspect: _knownPageAspect(readerState.currentPage),
              onPageChanged: (page) {
                _scrollReported = true;
                ref.read(readerProvider(_readerKey).notifier).goToPage(page);
              },
            ),
          )
        else
          PageReader(
            key: _pageReaderKey,
            controller: _pageController,
            pageCount: pageCount,
            pageUrlBuilder: (p) => client.pageUrl(_comicId, p),
            localPagesPath: _localPagesPath,
            rtl: isRtl,
            isZoomed: _isZoomed,
            onZoomChanged: _onZoomChanged,
            readyPages: _readyPages,
            pageAnimation: settings.pageAnimation,
            onTransformEnd: _onTransformEnd,
            onPageChanged: (page) {
              ref.read(readerProvider(_readerKey).notifier).goToPage(page);
              _countTurn(page);
              if (pageCount > 0 && page == pageCount) {
                _markCurrentCompletedAndFlushSession();
              }
              hideChrome();
              _panController.reset();
              _evictBubbleMasks(page);
              _loadBubbles(page);
              _loadBubbles(page + 1);
              // Reset zoom state — new page's ZoomWrapper starts unzoomed
              // but won't call onZoomChanged(false), leaving _isZoomed stuck.
              if (_isZoomed) {
                setState(() => _isZoomed = false);
              }
              final settings = ref.read(settingsProvider).value ?? const ReaderSettings();
              if (settings.zoomLock && _lockedTransform != null) {
                _transformController.value = _lockedTransform!;
                _panController.setTransforms([_lockedTransform!]);
              } else {
                _transformController.value = Matrix4.identity();
                final dims = _imageDimensions[page];
                if (dims != null) {
                  // Slide hides the identity→fitted move under the page
                  // slide. Fade and none land in a single frame, so the
                  // fitted transform must be there in that same frame.
                  final instant = settings.pageAnimation != 'slide';
                  _recalculateTransforms(page, dims.$1, dims.$2, instant: instant);
                }
              }
            },
            prefetcher: _prefetcher,
            onImageLoaded: _onImageLoaded,
            onPageProvider: (page, provider) {
              _pageProviders[page] = provider;
              // Called during build: start the cut-outs once the frame is done.
              if (_bubbles[page]?.bubbles.isNotEmpty ?? false) scheduleMicrotask(() => _ensureMasks(page));
              // A downloaded page's image is only known now: on-device panels can run.
              if (!_bubbles.containsKey(page)) scheduleMicrotask(() => _loadBubbles(page));
            },
            transformationController: _transformController,
            displayRectForPage: _displayRectFor,
            landingTransformFor: _landingTransformFor,
            onOverscroll: _handleOverscroll,
            allowPan: () => _userZoomed,
            endCardBuilder: _buildEndCardBuilder(readerState),
          ),

        // Bubble or panel zoom pop-out and the panel dim; rebuilt whenever
        // the pan step or transform changes.
        ListenableBuilder(
          // the transform too: a pinch off the step hides the pop-out
          listenable: Listenable.merge([_panController, _transformController]),
          builder: (context, _) => Stack(
            children: [
              _buildPanelDim(readerState.currentPage, settings),
              _buildBubbleOverlay(readerState.currentPage, settings) ??
                  _buildPanelOverlay(readerState.currentPage, settings) ??
                  const SizedBox.shrink(),
            ],
          ),
        ),
        if (_clipOutline case final r?)
          Positioned.fromRect(
            rect: r.inflate(2),
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.all(color: Theme.of(context).colorScheme.primary, width: 3),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
          ),
        // Tap zones — hidden on the end card so button taps aren't intercepted
        if (readerState.info != null &&
            readerState.currentPage < readerState.info!.pageCount)
          TapZoneOverlay(
            layout: settings.tapZoneLayout,
            onLeft: () => _handleLeft(settings),
            onRight: () => _handleRight(settings),
            onBack: _handleVolumeDown,
            onForward: _handleVolumeUp,
            chromeVisible: () => _showToolbar,
            scrollMode: () => settings.readingMode == 'scroll',
            offStep: () => _userZoomed,
            onShowChrome: showChrome,
            onHideChrome: hideChrome,
            onDoubleTap: _handleDoubleTap,
            onLongPress: (pos) => _handleLongPress(settings, pos),
            onTwoFingerTap: _onTwoFingerTap,
          ),

        // "Clip a panel" armed: this layer takes the next tap whole, so it
        // clips there and can never also turn the page or toggle chrome.
        if (_clipArmed)
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapUp: (d) {
                setState(() => _clipArmed = false);
                _clipPanel(settings, d.localPosition);
              },
              // A swipe or pinch disarms rather than being swallowed: that
              // gesture is lost, but the next one reaches the reader.
              // ponytail: forwarding it to the page needs a gesture-arena
              // handoff; add if users miss the first swipe.
              onScaleStart: (_) => setState(() => _clipArmed = false),
            ),
          ),

        // First-run hint: above the page and tap zones, below the chrome bars.
        if (_showOnboarding)
          TapZoneOnboarding(
            accent: accent,
            layout: settings.tapZoneLayout,
            rtl: isRtl,
            onDismiss: () => setState(() => _showOnboarding = false),
          )
        else if (_peekZones)
          IgnorePointer(
            child: TapZoneOnboarding(
              peek: true,
              accent: accent,
              layout: settings.tapZoneLayout,
              rtl: isRtl,
              onDismiss: () => setState(() => _peekZones = false),
            ),
          ),

        // Ambient progress (visible when chrome hidden)
        if (!_showToolbar) ...[
          // Swipe in from the left edge to leave, as iOS back does.
          // Translucent, so taps on the strip still reach the tap zones.
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            width: 24,
            child: GestureDetector(
              key: const Key('reader.edgeExit'),
              behavior: HitTestBehavior.translucent,
              onHorizontalDragStart: (_) => _edgeDrag = 0,
              onHorizontalDragUpdate: (d) => _edgeDrag += d.delta.dx,
              onHorizontalDragEnd: (d) {
                if (_edgeDrag > 80 || (d.primaryVelocity ?? 0) > 300) _exitReader();
              },
            ),
          ),
          AmbientProgressRail(
            progress: pageCount > 0 ? (readerState.currentPage + 1) / pageCount : 0,
            totalPages: pageCount,
            bookmarkPages: readerState.bookmarks.map((b) => b.pageNum).toList(),
          ),
          FloatingPagePill(
            currentPage: readerState.currentPage,
            totalPages: pageCount,
          ),
          // Above the page pill; with chrome up it rides on the bottom bar.
          if (jumpChip != null)
            Positioned(
              left: 0,
              right: 0,
              // Pill: bottom 22, ~24 tall. The pill ignores the inset; the
              // chip adds it so it clears the home indicator too.
              bottom: 58 + MediaQuery.paddingOf(context).bottom,
              child: Center(child: jumpChip),
            ),
        ],

        // Bottom control bar
        if (_showToolbar)
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 1),
                end: Offset.zero,
              ).animate(CurvedAnimation(
                parent: _overlayAnim,
                curve: Curves.easeOut,
              )),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (jumpChip != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: jumpChip,
                    ),
                  FilmstripScrubber(
                    currentPage: readerState.currentPage,
                    totalPages: pageCount,
                    pageUrlBuilder: (p) => client.pageUrl(widget.comicId, p),
                    localPagesPath: _localPagesPath,
                    bookmarkPages:
                        readerState.bookmarks.map((b) => b.pageNum).toList(),
                    chapterPages: mergeChapters(
                      comicInfo: readerState.info?.chapters ?? const [],
                      user: readerState.chapters,
                    ).map((c) => c.pageNum).toList(),
                    onOpenGrid: _openPageGrid,
                    onPageSelected: _jumpToPage,
                    accent: accent,
                  ),
                ],
              ),
            ),
          ),

        // Bedtime reminder card; only the card itself takes touches.
        if (_showBedtime)
          Positioned.fill(
            child: BedtimeCard(
              minutes: settings.sleepTimerMin,
              accent: accent,
              onStart: () {
                setState(() => _showBedtime = false);
                if (SleepTimer.instance.remaining == null) _onMoonTap();
              },
              onDismiss: () => setState(() => _showBedtime = false),
              onSnooze: () async {
                setState(() => _showBedtime = false);
                await ref.read(bedtimeReminderProvider.notifier).snooze(clock.now());
                _maybeBedtimeReminder();
              },
            ),
          ),

        // Sleep warning: over the bottom bar (its buttons sit there), under the
        // top bar so the moon stays tappable.
        if (_showSleepWarning)
          Positioned.fill(
            child: SleepWarningOverlay(
              accent: accent,
              remaining: () => SleepTimer.instance.remaining ?? Duration.zero,
              lead: SleepTimer.instance.warningLead,
              onExtend: () =>
                  _resolveSleepWarning(() => SleepTimer.instance.extend(15)),
              onRestart: () => _resolveSleepWarning(
                  () => SleepTimer.instance.start(settings.sleepTimerMin)),
              onCancel: () => _resolveSleepWarning(SleepTimer.instance.cancel),
              onDismiss: () => setState(() => _showSleepWarning = false),
            ),
          ),

        // Top info bar; on iPad the same controls as a right-edge rail,
        // faded rather than slid (rail and title tag sit on opposite sides).
        if (_showToolbar && isTablet)
          Positioned.fill(
            child: FadeTransition(opacity: _overlayAnim, child: topBar),
          )
        else if (_showToolbar)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, -1),
                end: Offset.zero,
              ).animate(CurvedAnimation(
                parent: _overlayAnim,
                curve: Curves.easeOut,
              )),
              child: topBar,
            ),
          ),

        // Claude panel: over the chrome so the filmstrip can't cover its reply
        // box; it starts below the title tag, under the Aa popover.
        if (_claudeOpened && isTablet && ref.watch(connectivityProvider))
          ClaudePanel(
            mode: _claudeMode,
            railOnLeft: railOnLeft,
          ),

        // iPad Aa popover, hanging under the Aa pill; tapping outside closes.
        if (_quickSettingsOpen && LayoutBreakpoint.isTablet(context)) ...[
          Positioned.fill(
            child: GestureDetector(
              onTap: () => setState(() => _quickSettingsOpen = false),
              child: ColoredBox(color: context.scheme.scrim),
            ),
          ),
          Positioned(
            top: _popoverTop,
            left: _popoverLeft,
            right: _popoverRight,
            width: 360,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height - _popoverTop - 20,
              ),
              child: LiquidGlass(
                child: ReaderAaPanel(
                  settings: settings,
                  onChanged: (next) => _saveSettings(next, settings),
                ),
              ),
            ),
          ),
        ],

      ],
    );

    Widget body = stack;
    if (settings.readingMode != 'scroll' && settings.volumeKeys) {
      body = VolumeKeyListener(
        enabled: true,
        onVolumeUp: _handleVolumeUp,
        onVolumeDown: _handleVolumeDown,
        child: body,
      );
    }

    // Remote control wraps OUTERMOST and unconditionally: it must work
    // regardless of the volume-keys setting, and its slot must never change
    // widget type. _remoteCommands is single-subscription (one SSE
    // connection per reader session), so a re-inflate here would re-listen
    // and throw. Nesting the conditional VolumeKeyListener underneath keeps
    // this element stable across settings changes made inside the reader.
    // Neither listener intercepts the other's input, so the order is free.
    // Commands route into the very same handlers a volume press uses, so
    // spread stepping, fades and transforms behave identically.
    final wrapped = RemoteControlListener(
      commands: _remoteCommands,
      onNext: _handleVolumeUp,
      onPrev: _handleVolumeDown,
      onBookmark: () {
        final state = ref.read(readerProvider(_readerKey)).value;
        if (state == null) return;
        ref
            .read(readerProvider(_readerKey).notifier)
            .toggleBookmark(state.currentPage);
        setState(() {});
      },
      onNextIssue: _advanceToNextIssue,
      onGoto: _jumpToPage,
      child: body,
    );

    // Publish the snapshot the phone renders. Fire-and-forget, and safe to
    // call every build: RemoteSession dedupes, and it is the only object that
    // knows when its stream reconnected and the hub therefore forgot.
    final snapshot = RemoteSnapshot(
      comicId: readerState.comicId,
      series: readerState.info?.series ?? '',
      page: readerState.currentPage,
      totalPages: readerState.info?.pageCount ?? 0,
      bookmarked:
          readerState.bookmarks.any((b) => b.pageNum == readerState.currentPage),
      hasNextIssue: _nextReadable(readerState).issue != null,
      readingMode: settings.readingMode,
    );
    ref.read(remoteSessionProvider).publishState(snapshot);

    return wrapped;
  }
}

