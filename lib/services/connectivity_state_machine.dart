enum ConnectivityState { online, unsure, offline }

class ConnectivityTransition {
  final ConnectivityState from;
  final ConnectivityState to;
  const ConnectivityTransition(this.from, this.to);

  bool get changed => from != to;

  bool get publicBoolChanged =>
      (from == ConnectivityState.offline) != (to == ConnectivityState.offline);
}

class ConnectivityStateMachine {
  static const int failureThreshold = 3;
  static const Duration onlinePollInterval = Duration(seconds: 30);
  static const Duration offlinePollInterval = Duration(seconds: 5);

  Duration get pollInterval => _state == ConnectivityState.online
      ? onlinePollInterval
      : offlinePollInterval;

  ConnectivityState _state = ConnectivityState.online;
  int _consecutiveFailures = 0;

  ConnectivityState get state => _state;
  bool get isOnline => _state != ConnectivityState.offline;

  ConnectivityTransition reportOutcome(bool reachedServer) {
    final from = _state;
    if (reachedServer) {
      _consecutiveFailures = 0;
      _state = ConnectivityState.online;
    } else {
      _consecutiveFailures++;
      if (_state == ConnectivityState.online) {
        _state = ConnectivityState.unsure;
      } else if (_state == ConnectivityState.unsure &&
          _consecutiveFailures >= failureThreshold) {
        _state = ConnectivityState.offline;
      }
    }
    return ConnectivityTransition(from, _state);
  }
}
