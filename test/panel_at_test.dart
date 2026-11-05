import 'package:comic_reader_app/services/panel_steps.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const big = Rect.fromLTRB(0, 0, 100, 100);
  const inset = Rect.fromLTRB(10, 10, 30, 30);
  const other = Rect.fromLTRB(100, 0, 200, 100);

  test('picks the panel under the point', () {
    expect(panelAt([big, other], const Offset(150, 50)), other);
  });

  test('an inset wins over the panel around it', () {
    expect(panelAt([big, inset], const Offset(20, 20)), inset);
    expect(panelAt([big, inset], const Offset(60, 60)), big);
  });

  test('null in a gutter or with no panels', () {
    expect(panelAt([big], const Offset(150, 50)), isNull);
    expect(panelAt(const [], Offset.zero), isNull);
  });
}
