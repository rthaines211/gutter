// lib/providers/comic_style_provider.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/comic_style.dart';
import 'providers.dart';

const _prefsKey = 'comic_style';
const _default = ComicStyle.fullPop;

class ComicStyleNotifier extends Notifier<ComicStyle> {
  @override
  ComicStyle build() {
    final stored = ref.watch(sharedPrefsProvider).getString(_prefsKey);
    return ComicStyle.values
        .firstWhere((s) => s.name == stored, orElse: () => _default);
  }

  void select(ComicStyle style) {
    state = style;
    ref.read(sharedPrefsProvider).setString(_prefsKey, style.name);
  }
}

final comicStyleProvider =
    NotifierProvider<ComicStyleNotifier, ComicStyle>(ComicStyleNotifier.new);
