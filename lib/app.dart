import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'config/app_theme.dart';
import 'config/flavor.dart';
import 'providers/app_breadcrumbs.dart';
import 'providers/scheme_provider.dart';
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
    final breadcrumbs = ref.read(appBreadcrumbsProvider.notifier);
    final scheme = ref.watch(schemeProvider).scheme;
    return MaterialApp(
      navigatorKey: navigatorKey,
      title: appName,
      theme: AppTheme.themeData(scheme),
      navigatorObservers: [
        BreadcrumbRouteObserver(onRoute: breadcrumbs.setRoute),
        RootRouteObserver(),
      ],
      builder: (context, child) => ConnectivityOverlay(
        child: LongboxSplash(child: child ?? const SizedBox.shrink()),
      ),
      home: const AppShell(),
    );
  }
}
