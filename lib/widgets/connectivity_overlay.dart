import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../config/app_theme.dart';
import '../config/scheme.dart';
import '../app.dart' show navigatorKey;
import '../config/layout_breakpoint.dart';
import '../providers/connectivity_provider.dart';
import '../providers/download_provider.dart';
import '../providers/navigation_provider.dart';
import '../screens/downloads_screen.dart';

/// App-wide connection alert. Wrap at [MaterialApp.builder] so it overlays the
/// Navigator (and therefore pushed routes such as the Reader).
///
/// Reads the existing [connectivityProvider] bool — no new state. Renders a
/// persistent top strip while offline and a transient toast on each transition.
class ConnectivityOverlay extends ConsumerStatefulWidget {
  final Widget child;
  const ConnectivityOverlay({super.key, required this.child});

  @override
  ConsumerState<ConnectivityOverlay> createState() =>
      _ConnectivityOverlayState();
}

class _ConnectivityOverlayState extends ConsumerState<ConnectivityOverlay> {
  Timer? _toastTimer;
  bool _showToast = false;
  bool _toastIsOffline = false;
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _initialized = true);
    });
  }

  @override
  void dispose() {
    _toastTimer?.cancel();
    super.dispose();
  }

  void _triggerToast(bool isOffline) {
    HapticFeedback.mediumImpact();
    setState(() {
      _showToast = true;
      _toastIsOffline = isOffline;
    });
    _toastTimer?.cancel();
    _toastTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _showToast = false);
    });
  }

  /// Banner tap: re-check the connection, and from the main screens jump to
  /// what's on this iPad. Not from a pushed screen (the reader sits under
  /// this banner; a stray tap must not yank you out of a comic).
  void _openDownloads(BuildContext context) {
    ref.read(connectivityProvider.notifier).check();
    final nav = navigatorKey.currentState;
    if (nav == null || nav.canPop()) return;
    if (LayoutBreakpoint.isTablet(context)) {
      ref.read(navigationProvider.notifier).go(NavDestination.downloads);
    } else {
      nav.push(MaterialPageRoute(
        settings: const RouteSettings(name: '/downloads'),
        builder: (_) => const DownloadsScreen(),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final isOnline = ref.watch(connectivityProvider);

    ref.listen<bool>(connectivityProvider, (prev, next) {
      if (!_initialized) return; // suppress flashes on launch
      if (prev == next) return;
      _triggerToast(!next);
    });

    final topInset = MediaQuery.of(context).padding.top;

    return Stack(
      children: [
        widget.child,
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: ValueListenableBuilder<bool>(
            valueListenable: atRootRoute,
            builder: (context, atRoot, strip) => IgnorePointer(
              ignoring: isOnline || !atRoot,
              child: AnimatedSlide(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeInOutCubic,
                offset: isOnline || !atRoot ? const Offset(0, -1) : Offset.zero,
                child: strip,
              ),
            ),
            child: _OfflineStrip(
              topInset: topInset,
              label: _offlineLabel(ref.watch(onDeviceProvider).comicIds.length,
                  pretend: ref.watch(simulateOfflineProvider)),
              onTap: () => _openDownloads(context),
            ),
          ),
        ),
        if (_showToast)
          Positioned(
            top: topInset + (isOnline ? 12 : 48),
            left: 0,
            right: 0,
            child: Center(child: _Toast(isOffline: _toastIsOffline)),
          ),
      ],
    );
  }
}

/// True while only the app shell is on the navigator. The offline strip
/// shows only then: over the reader (or any pushed page) it would cover the
/// top bar and its close button.
final atRootRoute = ValueNotifier<bool>(true);

class RootRouteObserver extends NavigatorObserver {
  // After the frame: listeners rebuild widgets, and these callbacks can run
  // mid-build.
  void _update() => WidgetsBinding.instance.addPostFrameCallback(
      (_) => atRootRoute.value = !(navigator?.canPop() ?? false));

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) => _update();
  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) => _update();
  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _update();
  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) =>
      _update();
}

String _offlineLabel(int n, {bool pretend = false}) {
  final what = switch (n) {
    0 => 'nothing downloaded',
    1 => '1 comic on this iPad',
    _ => '$n comics on this iPad',
  };
  return '${pretend ? 'Pretend offline' : 'Offline'} · $what';
}

class _OfflineStrip extends StatelessWidget {
  final double topInset;
  final String label;
  final VoidCallback onTap;
  const _OfflineStrip(
      {required this.topInset, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: EdgeInsets.fromLTRB(16, topInset + 6, 16, 8),
          color: context.scheme.s2,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.cloud_off_rounded, size: 14, color: AppTheme.amber),
              const SizedBox(width: 8),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.amber,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Toast extends StatelessWidget {
  final bool isOffline;
  const _Toast({required this.isOffline});

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: context.scheme.s2,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: context.scheme.hairStrong, width: 0.5),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isOffline ? Icons.cloud_off_rounded : Icons.cloud_done_rounded,
              size: 14,
              color: isOffline ? AppTheme.amber : AppTheme.accent,
            ),
            const SizedBox(width: 8),
            Text(
              isOffline ? 'Connection lost' : 'Back online',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: context.scheme.tx,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
