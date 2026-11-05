import 'package:flutter_test/flutter_test.dart';
import 'package:comic_reader_app/models/facet_value.dart';

void main() {
  group('FacetValue', () {
    test('fromJson parses correctly', () {
      final fv = FacetValue.fromJson({'value': 'DC Comics', 'count': 12});
      expect(fv.value, 'DC Comics');
      expect(fv.count, 12);
    });

    test('fromJson handles zero count', () {
      final fv = FacetValue.fromJson({'value': 'Unknown', 'count': 0});
      expect(fv.count, 0);
    });
  });
}
