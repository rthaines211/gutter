// lib/screens/library_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../config/app_theme.dart';
import '../config/flavor.dart';
import '../config/layout_breakpoint.dart';
import '../config/scheme.dart';
import '../config/library_sections.dart';
import '../models/library_filter.dart';
import '../models/series.dart';
import '../providers/library_provider.dart';
import '../providers/grid_density_provider.dart';
import '../providers/mirror_provider.dart';
import '../providers/providers.dart';
import '../providers/source_provider.dart';
import '../models/collection.dart';
import '../providers/collection_provider.dart';
import '../providers/smart_filter_provider.dart';
import '../providers/queue_provider.dart';
import '../widgets/library_search_bar.dart';
import '../widgets/views_pill_row.dart';
import '../widgets/facet_picker_sheet.dart';
import '../widgets/series_grid_tile.dart';
import '../widgets/series_list_tile.dart';
import '../widgets/shimmer_box.dart';
import '../widgets/sort_picker_sheet.dart';
import '../widgets/library_section_header.dart';
import '../providers/library_mode_provider.dart';
import '../widgets/library_index_rail.dart';
import '../widgets/library_mode_pill.dart';
import 'series_detail_screen.dart';
import '../widgets/series_detail_panel.dart';
import '../providers/download_provider.dart';
import '../providers/accent_provider.dart';
import '../providers/connectivity_provider.dart';
import '../providers/scan_status_provider.dart';
import '../widgets/scan_banner.dart';
import '../widgets/sync_progress_view.dart';
import '../widgets/creator_search_rows.dart';

class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key});

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> {
  Color get accent => ref.watch(accentProvider).value ?? AppTheme.accent;

  final _searchController = TextEditingController();
  final _scrollController = ScrollController();

  /// Keeps the header's state (search focus) when it moves between pinned
  /// and scrolling as the body height crosses [_minPinnedHeight].
  final _headerKey = GlobalKey();
  static const _minPinnedHeight = 420.0;
  bool _scanWatched = false;
  bool _headerPinned = false;

  /// Pinned header height, so the pull-to-refresh spinner starts below it.
  double _refreshEdge = 0;

  void _measureHeader() {
    if (!mounted) return;
    final box = _headerKey.currentContext?.findRenderObject() as RenderBox?;
    final edge = _headerPinned && box != null && box.hasSize ? box.size.height : 0.0;
    if (edge != _refreshEdge) setState(() => _refreshEdge = edge);
  }
  String? _selectedSeriesId;
  String get _viewMode => ref.watch(librarySmartFilterProvider);

  // Index rail (Task 5) state. Populated each time the sectioned grid is
  // built (`_buildSectionedGrid`, which runs before the rail in the Stack's
  // child order) so the rail — built afterward in the same frame — can read
  // the current sections without recomputing sort/filter/group itself.
  List<LibrarySection> _lastSections = const [];
  final Map<String, GlobalKey> _sectionKeys = {};
  int _lastColumns = 4;

  static const _indexKeys = [
    '#', 'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M',
    'N', 'O', 'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z',
  ];

  /// A–Z headers + index rail. Both the grid branch and the rail read this one
  /// getter so they can never disagree. Sectioning is only correct on a
  /// name-ascending sort — see `_buildSectionedGrid`'s doc comment — so the
  /// mode alone isn't enough.
  bool _isSectioned(LibraryFilter filter) =>
      ref.watch(libraryModeProvider) == LibraryMode.sectioned &&
      filter.sort == 'name' &&
      filter.order == 'asc';

  /// Publisher headers. Unlike A–Z these hold under any sort — the grouping is
  /// on a different field than the ordering.
  bool _isByPublisher() =>
      ref.watch(libraryModeProvider) == LibraryMode.publisher;

  @override
  void initState() {
    super.initState();
    // Provider is the single source of truth for the query; seed the bar from
    // it so a recreated screen (switch-based nav) re-shows an active search
    // instead of an empty bar over a live filter.
    _searchController.text = ref.read(libraryFilterProvider).query;
    // Offline, open on "On iPad" (when on All); back online, return to All —
    // unless the reader picked another view meanwhile.
    ref.listenManual<bool>(connectivityProvider, (_, online) {
      final status = ref.read(libraryFilterProvider).status;
      final filters = ref.read(libraryFilterProvider.notifier);
      if (!online && status == 'all') {
        _autoOnDevice = true;
        filters.setStatus('on_device');
      } else if (online && _autoOnDevice) {
        _autoOnDevice = false;
        if (status == 'on_device') filters.setStatus('all');
      }
    }, fireImmediately: true);
  }

  bool _autoOnDevice = false;

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  /// Row height for one grid row, derived from the grid's own layout
  /// constants (`childAspectRatio: 0.55`, spacing 10 at 3 columns else 14)
  /// rather than a hardcoded guess. `availableWidth` must match the sliver's
  /// actual cross-axis extent (screen width minus the grid's horizontal
  /// padding, including the +14 right margin reserved for this rail).
  double _rowHeight(double availableWidth, int columns) {
    final spacing = columns == 3 ? 10.0 : 14.0;
    final tileWidth = (availableWidth - (columns - 1) * spacing) / columns;
    final tileHeight = tileWidth / 0.55; // childAspectRatio = width / height
    return tileHeight + spacing;
  }

  /// Scrolls to the section for [key]. If its header is already built (its
  /// GlobalKey has a live context), `ensureVisible` does the job exactly. A
  /// 300-series library won't have distant sections built, so in that case
  /// we jump to an estimated offset — summing prior sections' header height,
  /// row count, and section padding — then correct it with a post-frame
  /// `ensureVisible` once the target header has actually been laid out.
  void _scrollToSection(String key, int columns) {
    final targetContext = _sectionKeys[key]?.currentContext;
    if (targetContext != null) {
      Scrollable.ensureVisible(
        targetContext,
        alignment: 0.0,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic,
      );
      return;
    }

    final index = _lastSections.indexWhere((s) => s.key == key);
    if (index <= 0 || !_scrollController.hasClients) return;

    // Anchor the estimate on the first section's built position when
    // available (it's near the top of the list and almost always mounted),
    // so we're only estimating the distance *between* sections rather than
    // guessing the height of the header content above the grid too.
    // Measured against the scroll viewport, not the screen: the pinned
    // header above the scroll view would otherwise skew the estimate.
    final anchorRender = _sectionKeys[_lastSections.first.key]
        ?.currentContext
        ?.findRenderObject();
    final anchorOffset = anchorRender != null
        ? RenderAbstractViewport.of(anchorRender)
            .getOffsetToReveal(anchorRender, 0.0)
            .offset
        : _scrollController.offset;

    const headerHeight = 36.0; // LibrarySectionHeaderDelegate's fixed extent
    const sectionPadding = 24.0; // top(8) + bottom(16) SliverPadding around each grid
    final rowHeight = _rowHeight(MediaQuery.of(context).size.width - 16 - 16 - 14, columns);

    var estimate = anchorOffset;
    for (var i = 0; i < index; i++) {
      final rows = (_lastSections[i].series.length / columns).ceil();
      estimate += headerHeight + rows * rowHeight + sectionPadding;
    }

    final max = _scrollController.position.maxScrollExtent;
    _scrollController.jumpTo(estimate.clamp(0, max));

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final ctx = _sectionKeys[key]?.currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(
          ctx,
          alignment: 0.0,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOutCubic,
        );
      }
    });
  }

  void _selectSeries(String seriesId) {
    setState(() => _selectedSeriesId = seriesId);
  }

  void _rescanLibrary() {
    HapticFeedback.selectionClick();
    ref.read(scanStatusProvider.notifier).startScan();
  }

  @override
  Widget build(BuildContext context) {
    // A new client (server URL or credentials changed, e.g. after onboarding)
    // gets its own first-scan check: the last one may have hit a 401.
    ref.listen(apiClientProvider, (_, _) {
      if (_scanWatched) setState(() => _scanWatched = false);
    });
    final isOnline = ref.watch(connectivityProvider);
    final isCustom = ref.watch(isCustomSourceProvider);
    final usesMirror = ref.watch(hasMirrorProvider);
    final libraryAsync = usesMirror
        ? ref.watch(libraryProvider)
        : ref.watch(opdsLibraryProvider);
    final source = ref.watch(activeSourceProvider);
    final serverUrl = usesMirror ? source.baseUrl : '';
    final filter = ref.watch(libraryFilterProvider);
    final viewMode = ref.watch(libraryViewModeProvider);
    final activeCollection = ref.watch(activeCollectionProvider);
    final collectionsAsync = ref.watch(collectionsProvider);
    final tablet = LayoutBreakpoint.isTablet(context);
    final density = ref.watch(gridDensityProvider);
    final columns = columnsForWidth(
      MediaQuery.of(context).size.width,
      density: density,
      tablet: tablet,
    );
    // Handoff: detail panel is 40% wide in landscape, 46% in portrait.
    final panelFraction =
        MediaQuery.orientationOf(context) == Orientation.portrait ? 0.46 : 0.40;

    return Scaffold(
      backgroundColor: context.scheme.bg,
      body: SafeArea(
        bottom: false,
        child: Stack(
          children: [
            tablet
                ? RefreshIndicator(
                    color: accent,
                    backgroundColor: context.scheme.s2,
                    edgeOffset: _refreshEdge,
                    onRefresh: () async {
                      await ref.read(connectivityProvider.notifier).check();
                      if (!ref.read(connectivityProvider)) {
                        HapticFeedback.mediumImpact();
                        ref.invalidate(downloadedLibraryProvider);
                      } else if (!usesMirror) {
                        HapticFeedback.mediumImpact();
                        return ref.refresh(opdsLibraryProvider.future);
                      } else {
                        HapticFeedback.mediumImpact();
                        final engine = ref.read(syncEngineProvider);
                        if (engine != null) {
                          try {
                            await engine.sync(force: true);
                          } catch (_) {}
                        }
                        if (isCustom) _rescanLibrary();
                      }
                    },
                    child: _selectedSeriesId == null
                        ? _buildScrollView(tablet, columns, libraryAsync, serverUrl, filter, viewMode, activeCollection, collectionsAsync, isCustom, isOnline)
                        // Split view: grid keeps ~60%, panel takes 40%
                        // landscape / 46% portrait with a left ink border
                        // (handoff). Columns recompute against the grid's real
                        // width so 4 columns don't get crushed.
                        : LayoutBuilder(builder: (context, box) {
                            final panelWidth = box.maxWidth * panelFraction;
                            final gridWidth = box.maxWidth - panelWidth;
                            return Row(
                              children: [
                                SizedBox(
                                  width: gridWidth,
                                  child: _buildScrollView(
                                    tablet,
                                    columnsForWidth(gridWidth,
                                        density: density, tablet: tablet),
                                    libraryAsync, serverUrl, filter, viewMode,
                                    activeCollection, collectionsAsync,
                                    isCustom, isOnline),
                                ),
                                Container(
                                  width: panelWidth,
                                  decoration: BoxDecoration(
                                    border: Border(
                                      left: BorderSide(
                                          color: context.scheme.ink, width: 1),
                                    ),
                                  ),
                                  child: SeriesDetailPanel(
                                    key: ValueKey(_selectedSeriesId),
                                    seriesId: _selectedSeriesId!,
                                    onClose: () => setState(
                                        () => _selectedSeriesId = null),
                                    accent: accent,
                                  ),
                                ),
                              ],
                            );
                          }),
                  )
              : RefreshIndicator(
                  color: accent,
                  backgroundColor: context.scheme.s2,
                  edgeOffset: _refreshEdge,
                  onRefresh: () async {
                    await ref.read(connectivityProvider.notifier).check();
                    if (!ref.read(connectivityProvider)) {
                      HapticFeedback.mediumImpact();
                      ref.invalidate(downloadedLibraryProvider);
                    } else if (!usesMirror) {
                      HapticFeedback.mediumImpact();
                      return ref.refresh(opdsLibraryProvider.future);
                    } else {
                      HapticFeedback.mediumImpact();
                      final engine = ref.read(syncEngineProvider);
                      if (engine != null) {
                        try {
                          await engine.sync(force: true);
                        } catch (_) {}
                      }
                      if (isCustom) _rescanLibrary();
                    }
                  },
                  child: _buildScrollView(tablet, columns, libraryAsync, serverUrl, filter, viewMode, activeCollection, collectionsAsync, isCustom, isOnline),
                ),
            // Scan progress banner
            const Positioned(
              left: 0,
              right: 0,
              bottom: 8,
              child: ScanBanner(),
            ),
            // A-Z index rail. Only meaningful when the grid is actually
            // sectioned (same condition as `_buildSectionedGrid`, read
            // through `_isSectioned` so the two can't disagree) — on any
            // other sort there are no section headers to scroll to.
            // Lives in the Stack, not as a sibling sliver: SliverMainAxisGroup
            // doesn't propagate its children's maxScrollObstructionExtent to
            // its own SliverGeometry, so a sliver placed after it can't see
            // the pinned headers and would mis-position (Task 4 review).
            if (_isSectioned(filter) &&
                !(tablet && _selectedSeriesId != null) &&
                !(viewMode == 'list' && !tablet) &&
                !_viewMode.startsWith('smart:'))
              // Centred with Align rather than stretched top-to-bottom: a
              // full-height child would sit over the grid's right edge and
              // swallow scroll drags there (worst on iPad landscape).
              Positioned(
                right: 2,
                top: 0,
                bottom: 0,
                child: Align(
                  alignment: Alignment.centerRight,
                  // 27 letters need ~400pt; phone landscape / keyboard up is
                  // shorter, so shrink rather than overflow.
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: LibraryIndexRail(
                      allKeys: _indexKeys,
                      presentKeys: presentKeys(_lastSections).toSet(),
                      accent: accent,
                      onTap: (key) => _scrollToSection(key, _lastColumns),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildScrollView(
    bool tablet,
    int columns,
    AsyncValue<List<Series>> libraryAsync,
    String serverUrl,
    LibraryFilter filter,
    String viewMode,
    int? activeCollection,
    AsyncValue<List<Collection>> collectionsAsync,
    bool isCustom,
    bool isOnline,
  ) {
    // Pinned header: title, mode/sort, search, offline banner and chip row
    // stay put while the grid (and its section headers) scrolls beneath.
    final header = ListenableBuilder(
      key: _headerKey,
      listenable: _scrollController,
      builder: (context, child) => DecoratedBox(
        decoration: BoxDecoration(
          color: context.scheme.bg,
          // Hairline only once content has scrolled under the header.
          border: Border(
            bottom: BorderSide(
              color: _scrollController.hasClients &&
                      _scrollController.offset > 0
                  ? context.scheme.hair
                  : Colors.transparent,
              width: 0.5,
            ),
          ),
        ),
        child: child,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
        // Header — minimal: title + count + sort
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
          child: Row(
            children: [
              const Text('Library', style: AppTheme.titleLarge),
              const SizedBox(width: 10),
              libraryAsync.when(
                data: (list) => Text(
                  '${list.length}',
                  style: context.monoLabel,
                ),
                loading: () => const SizedBox.shrink(),
                error: (_, _) => const SizedBox.shrink(),
              ),
              if (libraryAsync.value?.isNotEmpty ?? false) ...[
                const SizedBox(width: 10),
                const Flexible(child: SyncIndicator()),
              ],
              const Spacer(),
              const LibraryModePill(),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () {
                  HapticFeedback.selectionClick();
                  showModalBottomSheet(
                    context: context,
                    backgroundColor: Colors.transparent,
                    builder: (_) => const SortPickerSheet(),
                  );
                },
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: context.scheme.s1,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: context.scheme.borderFaint,
                      width: 0.5,
                    ),
                  ),
                  child: Center(
                    child: Icon(Icons.sort, size: 14, color: context.scheme.t2),
                  ),
                ),
              ),
            ],
          ),
        ),

        if (libraryAsync.value?.isNotEmpty ?? false)
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 0, 20, 10),
            child: SyncIndicator.strip(),
          ),

        // Search bar — always visible
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
          child: LibrarySearchBar(
            controller: _searchController,
            onChanged: (v) => ref.read(libraryFilterProvider.notifier).setQuery(v),
            onFilterTap: () {
              showModalBottomSheet(
                context: context,
                isScrollControlled: true,
                backgroundColor: Colors.transparent,
                builder: (_) => const FacetPickerSheet(),
              );
            },
            activeFilterCount: filter.activeFilterCount,
            accent: accent,
          ),
        ),

        // Views pill row (status + smart filters + collections)
        if (isCustom) ViewsPillRow(accent: accent),
        ],
      ),
    );

    Widget scrollView(bool pinned) => CustomScrollView(
      controller: _scrollController,
      physics: const AlwaysScrollableScrollPhysics(
        parent: BouncingScrollPhysics(),
      ),
      slivers: [
        if (!pinned) SliverToBoxAdapter(child: header),

        if (filter.query.trim().isNotEmpty)
          if (!isStore)
            SliverToBoxAdapter(child: CreatorSearchRows(query: filter.query)),

        // Content based on view mode
        if (_viewMode.startsWith('smart:'))
          _buildSmartFilterGrid(tablet, columns, serverUrl)
        else
          ..._buildLibraryContent(
            libraryAsync, serverUrl, filter, viewMode,
            activeCollection, collectionsAsync, tablet, columns,
          ),

        // Fill any remaining viewport so content covers full screen
        const SliverFillRemaining(
          hasScrollBody: false,
          child: SizedBox.shrink(),
        ),
      ],
    );

    // Pinned only when the body is tall enough: on phone landscape or with
    // the keyboard up, a fixed header would squeeze the grid to nothing.
    return LayoutBuilder(builder: (context, box) {
      _headerPinned = box.maxHeight >= _minPinnedHeight;
      WidgetsBinding.instance.addPostFrameCallback((_) => _measureHeader());
      return _headerPinned
          ? Column(children: [header, Expanded(child: scrollView(true))])
          : scrollView(false);
    });
  }

  /// Builds the normal library content slivers (loading, error, or data).
  List<Widget> _buildLibraryContent(
    AsyncValue<List<Series>> libraryAsync,
    String serverUrl,
    LibraryFilter filter,
    String viewMode,
    int? activeCollection,
    AsyncValue<List<Collection>> collectionsAsync,
    bool tablet,
    int columns,
  ) {
    return [
      libraryAsync.when(
        loading: () => _buildShimmerGrid(tablet, columns),
        error: (err, _) => _buildErrorSliver(err),
        data: (seriesList) {
          var filteredList = seriesList;
          if (activeCollection != null) {
            final collections = collectionsAsync.value ?? [];
            final col = collections.where((c) => c.id == activeCollection).firstOrNull;
            if (col != null) {
              final idSet = col.seriesIds.toSet();
              filteredList = seriesList.where((s) => idSet.contains(s.id)).toList();
            }
          }

          if (filteredList.isEmpty) {
            final unfiltered = filter.isDefault && activeCollection == null;
            if (unfiltered && ref.read(isCustomSourceProvider)) {
              if (!_scanWatched) {
                _scanWatched = true;
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) {
                    ref.read(scanStatusProvider.notifier).watchIfBusy();
                  }
                });
              }
              final scan = ref.watch(scanStatusProvider);
              if (FirstScanProgress.shows(scan)) {
                return SliverFillRemaining(child: FirstScanProgress(scan: scan));
              }
            }
            if (unfiltered &&
                FirstSyncCard.shows(ref.watch(syncProgressProvider))) {
              return const SliverFillRemaining(child: FirstSyncCard());
            }
            return SliverFillRemaining(
              child: Center(
                child: Text(
                  unfiltered
                      ? (ref.read(isCustomSourceProvider)
                          ? 'No comics found in your library folder yet.'
                          : 'No series found.\nAdd comics and refresh.')
                      : 'No series match the current filters.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: context.scheme.t2),
                ),
              ),
            );
          }

          if (viewMode == 'list' && !tablet) {
            return _buildSeriesList(filteredList, serverUrl);
          }

          // sectionize() requires name-ascending order (its own contiguity
          // precondition); any other sort fragments into duplicate/
          // out-of-order headers, so fall back to the flat grid.
          if (_isSectioned(filter)) {
            return SliverMainAxisGroup(
              slivers:
                  _buildSectionedGrid(filteredList, tablet, columns, serverUrl),
            );
          }
          if (_isByPublisher()) {
            return SliverMainAxisGroup(
              slivers: _buildSectionedGrid(
                filteredList,
                tablet,
                columns,
                serverUrl,
                sections: sectionizeByPublisher(filteredList),
                showRailPadding: false,
              ),
            );
          }
          return _buildSeriesGrid(filteredList, tablet, columns, serverUrl);
        },
      ),
    ];
  }

  /// Series grid sliver.
  Widget _buildSeriesGrid(List<Series> seriesList, bool tablet, int columns, String serverUrl) {
    final coversDir = ref.watch(coversDirProvider);
    // Offline: how many of a series' issues are on the device (null online).
    final offline = !ref.watch(connectivityProvider);
    final perSeries = ref.watch(onDeviceProvider).perSeries;
    int? onDevice(String id) => offline ? (perSeries[id] ?? 0) : null;
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 120),
      sliver: SliverGrid(
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            final series = seriesList[index];
            return SeriesGridTile(
                series: series,
                serverUrl: serverUrl,
                density: ref.watch(gridDensityProvider),
                localCoverPath:
                    coversDir == null ? null : p.join(coversDir, '${series.id}.jpg'),
                onDevice: onDevice(series.id),
                onTap: () {
                  if (tablet) {
                    _selectSeries(series.id);
                  } else {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        settings: const RouteSettings(name: '/series-detail'),
                        builder: (_) => SeriesDetailScreen(seriesId: series.id),
                      ),
                    );
                  }
                },
                onLongPress: () => _showSeriesActions(context, ref, series),
            );
          },
          childCount: seriesList.length,
        ),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: columns,
          childAspectRatio: 0.55,
          crossAxisSpacing: columns == 3 ? 10 : 14,
          mainAxisSpacing: columns == 3 ? 10 : 14,
        ),
      ),
    );
  }

  /// Series grid split into pinned A–Z section headers + per-section grids.
  ///
  /// Only the main library list is sectioned. Smart-filter results
  /// (`_buildSmartFilterGrid`) keep the flat `_buildSeriesGrid` — those lists
  /// are rule-filtered, not necessarily alphabetically contiguous, and
  /// `sectionize` requires already-sorted input to produce correct groups.
  /// Shared by A–Z and publisher grouping — same slivers, different keys.
  /// [sections] defaults to A–Z; publisher mode passes its own and turns off
  /// [showRailPadding], since the index rail is A–Z only.
  List<Widget> _buildSectionedGrid(
      List<Series> seriesList, bool tablet, int columns, String serverUrl,
      {List<LibrarySection>? sections, bool showRailPadding = true}) {
    final coversDir = ref.watch(coversDirProvider);
    // Offline: how many of a series' issues are on the device (null online).
    final offline = !ref.watch(connectivityProvider);
    final perSeries = ref.watch(onDeviceProvider).perSeries;
    int? onDevice(String id) => offline ? (perSeries[id] ?? 0) : null;
    final density = ref.watch(gridDensityProvider);
    final groups = sections ?? sectionize(seriesList);
    _lastSections = groups;
    _lastColumns = columns;
    // Drop keys for section letters no longer present (filter/search
    // changed) so stale GlobalKeys don't linger.
    _sectionKeys.removeWhere((k, _) => !groups.any((s) => s.key == k));
    final out = <Widget>[];
    for (var i = 0; i < groups.length; i++) {
      final section = groups[i];
      final isLast = i == groups.length - 1;
      final headerKey = _sectionKeys.putIfAbsent(section.key, () => GlobalKey());
      // Each section is its own group so its header pins only while the
      // section is on screen, then the next one pushes it off. Siblings in
      // one group would all stay pinned and stack down the screen.
      out.add(SliverMainAxisGroup(slivers: [SliverPersistentHeader(
        pinned: true,
        delegate: LibrarySectionHeaderDelegate(
          label: section.key,
          count: section.series.length,
          headerKey: headerKey,
        ),
      ), SliverPadding(
        // Right padding clears the index rail (Task 5); bottom padding only
        // on the last section so the floating tab bar has room.
        padding: EdgeInsets.fromLTRB(
            16, 8, showRailPadding ? 16 + 14 : 16, isLast ? 120 : 16),
        sliver: SliverGrid(
          delegate: SliverChildBuilderDelegate(
            (context, index) {
              final series = section.series[index];
              return SeriesGridTile(
                  series: series,
                  serverUrl: serverUrl,
                  density: density,
                  localCoverPath:
                      coversDir == null ? null : p.join(coversDir, '${series.id}.jpg'),
                  onDevice: onDevice(series.id),
                  onTap: () {
                    if (tablet) {
                      _selectSeries(series.id);
                    } else {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          settings: const RouteSettings(name: '/series-detail'),
                          builder: (_) => SeriesDetailScreen(seriesId: series.id),
                        ),
                      );
                    }
                  },
                  onLongPress: () => _showSeriesActions(context, ref, series),
              );
            },
            childCount: section.series.length,
          ),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            childAspectRatio: 0.55,
            crossAxisSpacing: columns == 3 ? 10 : 14,
            mainAxisSpacing: columns == 3 ? 10 : 14,
          ),
        ),
      )]));
    }
    return out;
  }

  /// Series list sliver (phone only).
  Widget _buildSeriesList(List<Series> seriesList, String serverUrl) {
    return SliverPadding(
      padding: const EdgeInsets.only(bottom: 120),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            final series = seriesList[index];
            return SeriesListTile(
              series: series,
              serverUrl: serverUrl,
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    settings: const RouteSettings(name: '/series-detail'),
                    builder: (_) =>
                        SeriesDetailScreen(seriesId: series.id),
                  ),
                );
              },
              onLongPress: () => _showSeriesActions(context, ref, series),
            );
          },
          childCount: seriesList.length,
        ),
      ),
    );
  }

  /// Smart filter results grid.
  Widget _buildSmartFilterGrid(bool tablet, int columns, String serverUrl) {
    final filterId = int.tryParse(_viewMode.replaceFirst('smart:', ''));
    if (filterId == null) {
      return const SliverToBoxAdapter(child: SizedBox.shrink());
    }

    final async = ref.watch(smartFilterSeriesProvider(filterId));
    return async.when(
      loading: () => _buildShimmerGrid(tablet, columns),
      error: (err, _) => _buildErrorSliver(err),
      data: (seriesList) {
        if (seriesList.isEmpty) {
          return SliverFillRemaining(
            child: Center(
              child: Text(
                'No series match this filter.',
                style: TextStyle(color: context.scheme.t2),
              ),
            ),
          );
        }
        return _buildSeriesGrid(seriesList, tablet, columns, serverUrl);
      },
    );
  }

  /// Shimmer loading grid.
  Widget _buildShimmerGrid(bool tablet, int columns) {
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 120),
      sliver: SliverGrid(
        delegate: SliverChildBuilderDelegate(
          (context, index) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: ShimmerBox(radius: columns == 3 ? AppTheme.r12 : AppTheme.r16),
              ),
              const SizedBox(height: 6),
              const ShimmerBox(width: 80, height: 12),
              const SizedBox(height: 4),
              const ShimmerBox(width: 40, height: 10),
            ],
          ),
          childCount: columns * 5,
        ),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: columns,
          childAspectRatio: 0.55,
          crossAxisSpacing: columns == 3 ? 10 : 14,
          mainAxisSpacing: columns == 3 ? 10 : 14,
        ),
      ),
    );
  }

  /// Error sliver with retry button.
  Widget _buildErrorSliver(Object err) {
    return SliverFillRemaining(
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: context.scheme.t3),
            const SizedBox(height: 16),
            Text('Failed to load: $err',
              textAlign: TextAlign.center,
              style: TextStyle(color: context.scheme.t2)),
            const SizedBox(height: 16),
            GestureDetector(
              onTap: () {
                // libraryProvider streams from the mirror — a "not in mirror"
                // error only clears after a sync pull, so kick one off too.
                unawaited(ref
                        .read(syncEngineProvider)
                        ?.sync(force: true)
                        .catchError((_) {}) ??
                    Future.value());
                if (ref.read(hasMirrorProvider)) {
                  ref.invalidate(libraryProvider);
                } else {
                  ref.invalidate(opdsLibraryProvider);
                }
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                decoration: BoxDecoration(
                  color: accent,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text('Retry', style: TextStyle(fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showSeriesActions(BuildContext context, WidgetRef ref, Series series) {
    HapticFeedback.mediumImpact();
    final collectionsAsync = ref.read(collectionsProvider);
    showModalBottomSheet(
      context: context,
      backgroundColor: context.scheme.s2,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(top: 12, bottom: 16),
              decoration: BoxDecoration(
                color: ctx.scheme.hairStrong,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Text(series.name,
                style: TextStyle(
                    color: ctx.scheme.tx,
                    fontSize: 16,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 16),
            if (!series.isCompleted)
              ListTile(
                leading: const Icon(Icons.check_circle, color: AppTheme.green),
                title: Text('Mark as Read',
                    style: TextStyle(color: ctx.scheme.tx)),
                onTap: () {
                  Navigator.pop(ctx);
                  _markSeriesAsRead(ref, series);
                },
              ),
            if (!series.isUnread)
              ListTile(
                leading: Icon(Icons.remove_circle_outline,
                    color: ctx.scheme.t2),
                title: Text('Mark as Unread',
                    style: TextStyle(color: ctx.scheme.tx)),
                onTap: () {
                  Navigator.pop(ctx);
                  _markSeriesAsUnread(ref, series);
                },
              ),
            Divider(color: ctx.scheme.s1),
            if (collectionsAsync.value != null)
              ...collectionsAsync.value!.map((col) {
                final inCollection = col.seriesIds.contains(series.id);
                return ListTile(
                  leading: Icon(
                    inCollection ? Icons.bookmark : Icons.bookmark_border,
                    color: inCollection ? accent : ctx.scheme.t2,
                  ),
                  title: Text(
                    inCollection ? 'Remove from ${col.name}' : 'Add to ${col.name}',
                    style: TextStyle(color: ctx.scheme.tx),
                  ),
                  onTap: () {
                    Navigator.pop(ctx);
                    if (inCollection) {
                      ref.read(collectionsProvider.notifier).removeSeries(col.id, series.id);
                    } else {
                      ref.read(collectionsProvider.notifier).addSeries(col.id, series.id);
                    }
                  },
                );
              }),
            Divider(color: ctx.scheme.s1),
            Builder(builder: (_) {
              final queues = ref.read(queuesProvider).value ?? [];
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final q in queues)
                    ListTile(
                      leading: Icon(
                        q.seriesIds.contains(series.id)
                            ? Icons.playlist_add_check_rounded
                            : Icons.playlist_add_rounded,
                        color: q.seriesIds.contains(series.id)
                            ? accent
                            : ctx.scheme.t2,
                      ),
                      title: Text(
                        q.seriesIds.contains(series.id)
                            ? 'Remove from ${q.name}'
                            : 'Add to ${q.name}',
                        style: TextStyle(color: ctx.scheme.tx),
                      ),
                      onTap: () {
                        Navigator.pop(ctx);
                        final actions = ref.read(queueActionsProvider);
                        if (q.seriesIds.contains(series.id)) {
                          actions.removeSeries(q, series.id);
                        } else {
                          actions.addSeries(q, series.id);
                        }
                      },
                    ),
                ],
              );
            }),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _markSeriesAsRead(WidgetRef ref, Series series) async {
    final client = ref.read(apiClientProvider);
    try {
      final detail = await client.fetchSeriesDetail(series.id);
      final items = detail.issues
          .where((i) => i.status != 'completed')
          .map((i) => {
                'comic_id': i.id,
                'current_page': i.totalPages ?? 1,
                'total_pages': i.totalPages ?? 1,
              })
          .toList();
      if (items.isNotEmpty) {
        await client.batchUpdateProgress(items);
      }
      HapticFeedback.mediumImpact();
      final engine = ref.read(syncEngineProvider);
      if (engine != null) await engine.sync();
    } catch (_) {}
  }

  Future<void> _markSeriesAsUnread(WidgetRef ref, Series series) async {
    final client = ref.read(apiClientProvider);
    try {
      final detail = await client.fetchSeriesDetail(series.id);
      final ids = detail.issues
          .where((i) => i.status != 'unread')
          .map((i) => i.id)
          .toList();
      if (ids.isNotEmpty) {
        await client.batchDeleteProgress(ids);
      }
      HapticFeedback.mediumImpact();
      final engine = ref.read(syncEngineProvider);
      if (engine != null) await engine.sync();
    } catch (_) {}
  }

}
