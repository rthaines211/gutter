import 'package:flutter_test/flutter_test.dart';
import 'package:comic_reader_app/services/connectivity_state_machine.dart';

void main() {
  group('ConnectivityStateMachine', () {
    late ConnectivityStateMachine sm;

    setUp(() {
      sm = ConnectivityStateMachine();
    });

    test('initial state is online', () {
      expect(sm.state, ConnectivityState.online);
      expect(sm.isOnline, isTrue);
    });

    test('single success keeps state online', () {
      sm.reportOutcome(true);
      expect(sm.state, ConnectivityState.online);
    });

    test('single failure transitions online -> unsure (still isOnline)', () {
      sm.reportOutcome(false);
      expect(sm.state, ConnectivityState.unsure);
      expect(sm.isOnline, isTrue);
    });

    test('failure then success returns to online and resets counter', () {
      sm.reportOutcome(false);
      sm.reportOutcome(true);
      expect(sm.state, ConnectivityState.online);
      // Next single failure should only put us back to unsure, not offline.
      sm.reportOutcome(false);
      expect(sm.state, ConnectivityState.unsure);
    });

    test('three consecutive failures commits to offline', () {
      sm.reportOutcome(false);
      sm.reportOutcome(false);
      sm.reportOutcome(false);
      expect(sm.state, ConnectivityState.offline);
      expect(sm.isOnline, isFalse);
    });

    test('further failures while offline stay offline', () {
      for (var i = 0; i < 5; i++) {
        sm.reportOutcome(false);
      }
      expect(sm.state, ConnectivityState.offline);
    });

    test('single success while offline returns to online and resets counter', () {
      for (var i = 0; i < 5; i++) {
        sm.reportOutcome(false);
      }
      sm.reportOutcome(true);
      expect(sm.state, ConnectivityState.online);
      // Confirm counter reset: one failure is unsure, not straight to offline.
      sm.reportOutcome(false);
      expect(sm.state, ConnectivityState.unsure);
    });

    test('reportOutcome returns transition info', () {
      final t1 = sm.reportOutcome(false);
      expect(t1.from, ConnectivityState.online);
      expect(t1.to, ConnectivityState.unsure);
      expect(t1.changed, isTrue);
      expect(t1.publicBoolChanged, isFalse);

      final t2 = sm.reportOutcome(false);
      expect(t2.from, ConnectivityState.unsure);
      expect(t2.to, ConnectivityState.unsure);
      expect(t2.changed, isFalse);

      sm.reportOutcome(false); // -> offline
      final t4 = sm.reportOutcome(true); // offline -> online
      expect(t4.from, ConnectivityState.offline);
      expect(t4.to, ConnectivityState.online);
      expect(t4.publicBoolChanged, isTrue);
    });

    test('pollInterval is 30s when online, 5s otherwise', () {
      expect(sm.pollInterval, const Duration(seconds: 30));
      sm.reportOutcome(false); // -> unsure
      expect(sm.pollInterval, const Duration(seconds: 5));
      sm.reportOutcome(false);
      sm.reportOutcome(false); // -> offline
      expect(sm.pollInterval, const Duration(seconds: 5));
      sm.reportOutcome(true); // -> online
      expect(sm.pollInterval, const Duration(seconds: 30));
    });
  });
}
