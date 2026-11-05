import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Represents which screen is showing in the app shell.
/// Phone: 0=Read, 1=Library, 2=Creators, 3=Review, 4=More
/// iPad sidebar maps its rows to these same indices plus sub-screens.
enum NavDestination {
  read,       // index 0
  library,    // index 1
  downloads,  // (phone: under More; iPad: sidebar row)
  queues,     // (phone: under More; iPad: sidebar row)
  arcs,       // (phone: under More; iPad: sidebar row) — story arcs synced from Mylar
  stats,      // (phone: under More; iPad: sidebar row)
  settings,   // (phone: under More; iPad: sidebar gear)
  review,     // appended after settings so existing indices don't shift (phone: tab 3)
  creators,   // appended last so existing indices don't shift (phone: tab 2)
}

/// Destinations that need the server; hidden while offline.
const onlineOnlyDestinations = {
  NavDestination.creators,
  NavDestination.review,
  NavDestination.stats,
};

class NavigationNotifier extends Notifier<NavDestination> {
  @override
  NavDestination build() => NavDestination.read;

  void go(NavDestination dest) => state = dest;

  /// Map NavDestination to the phone tab bar index (0-4).
  int get tabIndex {
    switch (state) {
      case NavDestination.read:
        return 0;
      case NavDestination.library:
        return 1;
      case NavDestination.creators:
        return 2;
      case NavDestination.review:
        return 3;
      default:
        return 4; // everything else lives under More
    }
  }

  /// Set destination from phone tab bar index.
  void setTabIndex(int index) {
    switch (index) {
      case 0:
        state = NavDestination.read;
      case 1:
        state = NavDestination.library;
      case 2:
        state = NavDestination.creators;
      case 3:
        state = NavDestination.review;
      case 4:
        // Only switch to More if we're not already on a More sub-screen
        if (tabIndex != 4) state = NavDestination.downloads;
    }
  }
}

final navigationProvider =
    NotifierProvider<NavigationNotifier, NavDestination>(
  NavigationNotifier.new,
);
