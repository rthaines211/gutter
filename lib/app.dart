import 'package:flutter/material.dart';
import 'providers/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'config/app_theme.dart';
import 'config/flavor.dart';
import 'providers/app_breadcrumbs.dart';
import 'providers/scheme_provider.dart';
import 'providers/source_provider.dart';
import 'screens/onboarding_screen.dart';
import 'services/breadcrumb_route_observer.dart';
import 'widgets/app_shell.dart';
import 'widgets/connectivity_overlay.dart';
import 'widgets/longbox_splash.dart';

/// Lets code outside the widget tree (notification taps) push routes.
final navigatorKey = GlobalKey<NavigatorState>();

class ComicReaderApp extends ConsumerWidget {
  const ComicReaderApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(sourceAuthSyncProvider);
    final breadcrumbs = ref.read(appBreadcrumbsProvider.notifier);
    final scheme = ref.watch(schemeProvider).scheme;
    final needsServer =
        ref.watch(activeSourceProvider.select((s) => s.baseUrl.isEmpty));
    return MaterialApp(
      navigatorKey: navigatorKey,
      debugShowCheckedModeBanner: false,
      title: appName,
      theme: AppTheme.themeData(scheme),
      navigatorObservers: [
        BreadcrumbRouteObserver(onRoute: breadcrumbs.setRoute),
        RootRouteObserver(),
      ],
      // No server yet (every fresh store install) reads as offline: skip the
      // offline strip while onboarding.
      builder: (context, child) {
        final splash = LongboxSplash(child: child ?? const SizedBox.shrink());
        return needsServer ? splash : ConnectivityOverlay(child: splash);
      },
      // Saving a URL in onboarding rebuilds this into the shell.
      home: needsServer ? const OnboardingScreen() : const AppShell(),
    );
  }
}
