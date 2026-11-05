import 'package:flutter_riverpod/flutter_riverpod.dart';

class AppBreadcrumbsState {
  final String route;
  final String? comicId;
  final int? page;
  final int? totalPages;
  final String? lastAction;

  const AppBreadcrumbsState({
    this.route = '/',
    this.comicId,
    this.page,
    this.totalPages,
    this.lastAction,
  });

  AppBreadcrumbsState copyWith({
    String? route,
    Object? comicId = _unset,
    Object? page = _unset,
    Object? totalPages = _unset,
    String? lastAction,
  }) {
    return AppBreadcrumbsState(
      route: route ?? this.route,
      comicId: identical(comicId, _unset) ? this.comicId : comicId as String?,
      page: identical(page, _unset) ? this.page : page as int?,
      totalPages: identical(totalPages, _unset)
          ? this.totalPages
          : totalPages as int?,
      lastAction: lastAction ?? this.lastAction,
    );
  }

  Map<String, Object?> toJson() => {
        'route': route,
        if (comicId != null) 'comicId': comicId,
        if (page != null) 'page': page,
        if (totalPages != null) 'totalPages': totalPages,
        if (lastAction != null) 'lastAction': lastAction,
      };
}

const _unset = Object();

class AppBreadcrumbsNotifier extends Notifier<AppBreadcrumbsState> {
  @override
  AppBreadcrumbsState build() => const AppBreadcrumbsState();

  void setRoute(String route) {
    state = state.copyWith(route: route, lastAction: 'route');
  }

  void readerOpened({
    required String comicId,
    required int totalPages,
    required int initialPage,
  }) {
    state = state.copyWith(
      comicId: comicId,
      totalPages: totalPages,
      page: initialPage,
      lastAction: 'comic_opened',
    );
  }

  void readerPageTurn({required String comicId, required int page}) {
    state = state.copyWith(
      comicId: comicId,
      page: page,
      lastAction: 'page_turn',
    );
  }

  void readerClosed() {
    state = state.copyWith(
      comicId: null,
      page: null,
      totalPages: null,
      lastAction: 'comic_closed',
    );
  }
}

final appBreadcrumbsProvider =
    NotifierProvider<AppBreadcrumbsNotifier, AppBreadcrumbsState>(
  AppBreadcrumbsNotifier.new,
);
