/// Which app this build is: the App Store app (the default) or the owner's
/// personal build, which `make ipad` marks with `--dart-define=FLAVOR=personal`.
/// Store hides the personal-only features (push, Claude, Review, Remote,
/// labeller, Creators) and ships no default server. Mutable so tests can flip
/// it (only tests assign it); `test/flutter_test_config.dart` runs the suite
/// as personal.
bool isStore = const String.fromEnvironment('FLAVOR') != 'personal';

String get appName => isStore ? 'Gutter' : 'Longbox';
