import 'package:flutter_test/flutter_test.dart';
import 'package:comic_reader_app/models/chapter_candidate.dart';

void main() {
  test('fromJson parses fields', () {
    final c = ChapterCandidate.fromJson({
      'page': 208, 'title': 'Superman and the Authority',
      'source': 'filename', 'confidence': 'high',
    });
    expect(c.page, 208);
    expect(c.title, 'Superman and the Authority');
    expect(c.source, 'filename');
  });

  test('fromJson tolerates missing fields', () {
    final c = ChapterCandidate.fromJson({'page': 0});
    expect(c.title, '');
    expect(c.confidence, 'medium');
  });
}
