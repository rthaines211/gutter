import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/widgets.dart';

class PagePrefetcher {
  static const int _defaultPrefetchCount = 5;
  static const int _boostPrefetchCount = 8;
  static const int _rapidReadThreshold = 3;
  static const Duration _speedWindow = Duration(milliseconds: 2000);
  static const Duration _cooldownDuration = Duration(seconds: 4);

  final int totalPages;
  final String Function(int page) pageUrlBuilder;

  int _prefetchCount = _defaultPrefetchCount;
  final List<DateTime> _recentPageTimes = [];
  Timer? _cooldownTimer;
  final Map<int, ({ImageStream stream, ImageStreamListener listener})> _inflightHandles = {};

  PagePrefetcher({
    required this.totalPages,
    required this.pageUrlBuilder,
  });

  List<int> prefetchRange({required int currentPage, required bool rtl}) {
    final List<int> pages = [];
    for (int i = 1; i <= _prefetchCount; i++) {
      final target = rtl ? currentPage - i : currentPage + i;
      if (target >= 0 && target < totalPages) {
        pages.add(target);
      }
    }
    return pages;
  }

  void onPageChanged({
    required int currentPage,
    required bool rtl,
    required BuildContext context,
  }) {
    _updateSpeed();
    _clearInflightTracking();

    final pages = prefetchRange(currentPage: currentPage, rtl: rtl);
    _precachePages(pages, context);
  }

  void _precachePages(List<int> pages, BuildContext context) {
    for (final page in pages) {
      if (_inflightHandles.containsKey(page)) continue;
      final url = pageUrlBuilder(page);
      final provider = CachedNetworkImageProvider(url);
      final stream = provider.resolve(const ImageConfiguration());
      final listener = ImageStreamListener(
        (info, sync) => _inflightHandles.remove(page),
        onError: (err, stack) => _inflightHandles.remove(page),
      );
      stream.addListener(listener);
      _inflightHandles[page] = (stream: stream, listener: listener);
    }
  }

  void _updateSpeed() {
    final now = DateTime.now();
    _recentPageTimes.removeWhere(
      (t) => now.difference(t).inMilliseconds > _speedWindow.inMilliseconds,
    );
    _recentPageTimes.add(now);

    if (_recentPageTimes.length >= _rapidReadThreshold) {
      _prefetchCount = _boostPrefetchCount;
    }

    _cooldownTimer?.cancel();
    _cooldownTimer = Timer(_cooldownDuration, () {
      _prefetchCount = _defaultPrefetchCount;
    });
  }

  void _clearInflightTracking() {
    for (final entry in _inflightHandles.values) {
      entry.stream.removeListener(entry.listener);
    }
    _inflightHandles.clear();
  }

  void onPageJump({
    required int targetPage,
    required bool rtl,
    required BuildContext context,
  }) {
    _recentPageTimes.clear();
    _prefetchCount = _defaultPrefetchCount;
    _clearInflightTracking();

    final pages = prefetchRange(currentPage: targetPage, rtl: rtl);
    _precachePages(pages, context);
  }

  @visibleForTesting
  void onPageChangedForTest() {
    _updateSpeed();
  }

  @visibleForTesting
  void onPageJumpForTest() {
    _recentPageTimes.clear();
    _prefetchCount = _defaultPrefetchCount;
    _clearInflightTracking();
  }

  void dispose() {
    _cooldownTimer?.cancel();
    _clearInflightTracking();
    _recentPageTimes.clear();
  }
}
