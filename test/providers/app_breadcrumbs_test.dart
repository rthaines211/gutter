import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:comic_reader_app/providers/app_breadcrumbs.dart';

void main() {
  group('AppBreadcrumbs', () {
    late ProviderContainer container;
    setUp(() => container = ProviderContainer());
    tearDown(() => container.dispose());

    test('default state is unknown route and null fields', () {
      final s = container.read(appBreadcrumbsProvider);
      expect(s.route, '/');
      expect(s.comicId, isNull);
      expect(s.page, isNull);
      expect(s.totalPages, isNull);
      expect(s.lastAction, isNull);
    });

    test('setRoute updates the route and lastAction', () {
      container
          .read(appBreadcrumbsProvider.notifier)
          .setRoute('/reader');
      final s = container.read(appBreadcrumbsProvider);
      expect(s.route, '/reader');
      expect(s.lastAction, 'route');
    });

    test('readerOpened populates comic fields and clears them on close', () {
      final n = container.read(appBreadcrumbsProvider.notifier);
      n.readerOpened(comicId: 'abc', totalPages: 100, initialPage: 5);
      var s = container.read(appBreadcrumbsProvider);
      expect(s.comicId, 'abc');
      expect(s.totalPages, 100);
      expect(s.page, 5);
      expect(s.lastAction, 'comic_opened');

      n.readerPageTurn(comicId: 'abc', page: 10);
      s = container.read(appBreadcrumbsProvider);
      expect(s.page, 10);
      expect(s.lastAction, 'page_turn');

      n.readerClosed();
      s = container.read(appBreadcrumbsProvider);
      expect(s.comicId, isNull);
      expect(s.page, isNull);
      expect(s.totalPages, isNull);
      expect(s.lastAction, 'comic_closed');
    });

    test('toJson omits null fields', () {
      final n = container.read(appBreadcrumbsProvider.notifier);
      n.setRoute('/library');
      final json = container.read(appBreadcrumbsProvider).toJson();
      expect(json['route'], '/library');
      expect(json.containsKey('comicId'), isFalse);
      expect(json.containsKey('page'), isFalse);
    });
  });
}
