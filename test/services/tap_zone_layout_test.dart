import 'package:flutter_test/flutter_test.dart';
import 'package:comic_reader_app/services/tap_zone_layout.dart';

void main() {
  test('standard: left third, center menu, right third', () {
    expect(actionAt('standard', const Offset(0.1, 0.5)), TapAction.left);
    expect(actionAt('standard', const Offset(0.5, 0.5)), TapAction.menu);
    expect(actionAt('standard', const Offset(0.9, 0.5)), TapAction.right);
  });

  test('disabled: menu everywhere', () {
    expect(actionAt('disabled', const Offset(0.05, 0.05)), TapAction.menu);
    expect(actionAt('disabled', const Offset(0.95, 0.95)), TapAction.menu);
  });

  test('edge: left quarter prev, center band menu, right rest next', () {
    expect(actionAt('edge', const Offset(0.1, 0.6)), TapAction.left);
    expect(actionAt('edge', const Offset(0.5, 0.6)), TapAction.menu); // center opens menu
    expect(actionAt('edge', const Offset(0.5, 0.1)), TapAction.menu); // full height
    expect(actionAt('edge', const Offset(0.9, 0.6)), TapAction.right);
  });

  test('unknown layout behaves as standard', () {
    expect(actionAt('bogus', const Offset(0.1, 0.5)), TapAction.left);
  });

  test('standard boundaries: x=1/3 is menu, x=2/3 is right', () {
    expect(actionAt('standard', const Offset(1 / 3, 0.5)), TapAction.menu);
    expect(actionAt('standard', const Offset(2 / 3, 0.5)), TapAction.right);
  });

  test('edge boundaries: x=0.25 is menu, x=0.55 is next', () {
    expect(actionAt('edge', const Offset(0.25, 0.5)), TapAction.menu);
    expect(actionAt('edge', const Offset(0.55, 0.5)), TapAction.right);
  });

  test('thumb: right strip top back, bottom forward, rest menu', () {
    expect(actionAt('thumb', const Offset(0.9, 0.2)), TapAction.back);
    expect(actionAt('thumb', const Offset(0.9, 0.8)), TapAction.forward);
    expect(actionAt('thumb', const Offset(0.6, 0.5)), TapAction.forward); // boundary
    expect(actionAt('thumb', const Offset(0.3, 0.2)), TapAction.menu);
    expect(actionAt('thumb', const Offset(0.3, 0.8)), TapAction.menu);
  });
}
