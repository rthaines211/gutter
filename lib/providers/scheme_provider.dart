import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../config/scheme.dart';
import 'providers.dart';

const _prefsKey = 'theme_scheme';

enum SchemeId {
  oledBlack,
  sepiaPaper;

  Scheme get scheme => switch (this) {
        SchemeId.oledBlack => Scheme.oledBlack,
        SchemeId.sepiaPaper => Scheme.sepiaPaper,
      };
}

class SchemeNotifier extends Notifier<SchemeId> {
  @override
  SchemeId build() {
    final stored = ref.watch(sharedPrefsProvider).getString(_prefsKey);
    return SchemeId.values.firstWhere(
      (e) => e.name == stored,
      orElse: () => SchemeId.sepiaPaper,
    );
  }

  void select(SchemeId id) {
    state = id;
    ref.read(sharedPrefsProvider).setString(_prefsKey, id.name);
  }
}

final schemeProvider =
    NotifierProvider<SchemeNotifier, SchemeId>(SchemeNotifier.new);
