// lib/providers/library_mode_provider.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'providers.dart';

const _prefsKey = 'library_mode';

/// How the library groups its series.
enum LibraryMode {
  /// Sticky A–Z letter headers plus the right-edge index rail. Default.
  sectioned,

  /// Sticky publisher headers. No index rail (letters no longer map to sections).
  publisher,

  /// One flat grid, no headers.
  flat,
}

class LibraryModeNotifier extends Notifier<LibraryMode> {
  @override
  LibraryMode build() {
    final stored = ref.watch(sharedPrefsProvider).getString(_prefsKey);
    return LibraryMode.values
            .where((m) => m.name == stored)
            .firstOrNull ??
        LibraryMode.sectioned;
  }

  void select(LibraryMode mode) {
    state = mode;
    ref.read(sharedPrefsProvider).setString(_prefsKey, mode.name);
  }

  /// Sectioned → publisher → flat → sectioned.
  void cycle() =>
      select(LibraryMode.values[(state.index + 1) % LibraryMode.values.length]);
}

final libraryModeProvider =
    NotifierProvider<LibraryModeNotifier, LibraryMode>(LibraryModeNotifier.new);
