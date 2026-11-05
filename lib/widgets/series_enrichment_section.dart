import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/app_theme.dart';
import '../config/comic_style.dart';
import '../config/creator_roles.dart';
import '../config/scheme.dart';
import '../models/creator.dart';
import '../services/mirror/library_view.dart' show splitCreators;
import 'creator_detail_panel.dart' show openCreator;

/// One creator's role group: the role label plus every [Creator] credited
/// under it (e.g. "writer" -> Scott Snyder, James Tynion IV).
class _RoleGroup {
  final String role;
  final List<Creator> creators;
  const _RoleGroup(this.role, this.creators);
}

/// A single tappable name, flattened out of a [Creator] whose `name` may
/// itself be a comma-separated list (legacy unenriched metadata jams
/// several people into one entry — see `splitCreators`). [id] and
/// [tappable] come from the parent [Creator]: a comma-joined entry shares
/// one id/role across all of its split names, which is a known approximation
/// for that legacy shape.
class _Credit {
  final String name;
  final int id;
  final bool tappable;
  const _Credit(this.name, this.id, this.tappable);
}

List<_Credit> _flattenCredits(List<Creator> creators) {
  final out = <_Credit>[];
  for (final c in creators) {
    final tappable = c.role.split(',').any((r) => roleGroup(r) != null);
    final names = splitCreators(c.name);
    for (final n in names.isEmpty ? [c.name] : names) {
      out.add(_Credit(n, c.id, tappable));
    }
  }
  return out;
}

/// Builds the inline spans for a role group's credited names: tappable
/// (underlined-free, just a recognizer) for any in-scope role, plain text
/// otherwise. Used by both the collapsed summary line and the expanded
/// card, so both inherit maxLines/overflow clamping from [Text.rich].
///
/// Every recognizer created is also appended to [recognizers] so the caller
/// (a State) can dispose them — a TapGestureRecognizer left undisposed
/// leaks, and nothing but a State's `dispose()` can own that cleanup.
List<InlineSpan> _creditSpans(
  BuildContext context,
  WidgetRef ref,
  List<Creator> creators, {
  required List<TapGestureRecognizer> recognizers,
}) {
  final credits = _flattenCredits(creators);
  final spans = <InlineSpan>[];
  for (var i = 0; i < credits.length; i++) {
    if (i > 0) spans.add(const TextSpan(text: ', '));
    final credit = credits[i];
    if (!credit.tappable) {
      spans.add(TextSpan(text: credit.name));
      continue;
    }
    final recognizer = TapGestureRecognizer()
      ..onTap = () => openCreator(context, ref, id: credit.id, name: credit.name);
    recognizers.add(recognizer);
    spans.add(TextSpan(text: credit.name, recognizer: recognizer));
  }
  return spans;
}

/// Description (collapsed to 3 lines, tap to expand) + creators grouped by
/// primary role: one summary line ("WRITER  Names  +3 more"), tap to expand
/// into a card grid. Renders nothing when there's no
/// enrichment data, so it's safe to drop into the header unconditionally.
///
/// Sits on the page background (below the header's backdrop fade), so every
/// colour here follows the active [Scheme] — see
/// docs/superpowers/DEFERRED.md §"The scrim bug class".
class SeriesEnrichmentSection extends ConsumerStatefulWidget {
  final String? description;
  final List<Creator> creators;
  final Color accent;

  const SeriesEnrichmentSection({
    super.key,
    required this.description,
    required this.creators,
    this.accent = AppTheme.accent,
  });

  @override
  ConsumerState<SeriesEnrichmentSection> createState() =>
      _SeriesEnrichmentSectionState();
}

class _SeriesEnrichmentSectionState
    extends ConsumerState<SeriesEnrichmentSection> {
  bool _expanded = false;
  bool _creatorsExpanded = false;

  // Four columns once the section itself has room — matches the issue list's
  // panel-width breakpoint (see issue_list_view.dart) so both sections agree
  // on what "wide" means inside the same panel/full-screen host.
  static const double _wideBreakpoint = 820;

  /// Creator card height.
  ///
  /// The card's content is a fixed stack, so the grid takes an explicit extent
  /// — an aspect ratio would scale it with column width, which is what made
  /// these cards ~390pt tall on an iPad.
  ///
  /// Measured, not derived: rendering the real widget gives a 32pt avatar,
  /// 36pt for two lines of the 12.5pt name (18 per line — more than the raw
  /// font size, since the style's leading counts), and 14pt for the 9.5pt
  /// role. With the 6 + 2 gaps and 10 + 10 padding that is 110. Two more for
  /// the border and rounding slack.
  static const double _creatorCardHeight = 112;

  @override
  Widget build(BuildContext context) {
    final hasDescription =
        widget.description != null && widget.description!.trim().isNotEmpty;
    if (!hasDescription && widget.creators.isEmpty) {
      return const SizedBox.shrink();
    }

    final comic = ComicTokens.watch(ref, context, widget.accent);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (hasDescription) ...[
          const SizedBox(height: 12),
          GestureDetector(
            onTap: () => setState(() => _expanded = !_expanded),
            behavior: HitTestBehavior.opaque,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.description!,
                  maxLines: _expanded ? null : 3,
                  overflow: _expanded
                      ? TextOverflow.visible
                      : TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13.5,
                    height: 1.5,
                    color: context.scheme.t2,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _expanded ? 'LESS' : 'MORE',
                  style: context.monoCaption.copyWith(
                    fontSize: 10,
                    color: widget.accent,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
        if (widget.creators.isNotEmpty) ...[
          const SizedBox(height: 12),
          if (!_creatorsExpanded)
            _creatorsSummary(context)
          else ...[
            LayoutBuilder(
              builder: (context, constraints) {
                final crossAxisCount = constraints.maxWidth >= _wideBreakpoint
                    ? 4
                    : 2;
                return GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _roleGroups().length,
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: crossAxisCount,
                    crossAxisSpacing: 8,
                    mainAxisSpacing: 8,
                    // Fixed height, NOT an aspect ratio: the card's content is
                    // a fixed stack (10 pad + 32 avatar + 6 + name + 2 + role +
                    // 10 pad), so a ratio made the card as tall as it was wide
                    // — ~390pt on an iPad, with a single line of text floating
                    // in a void.
                    mainAxisExtent: _creatorCardHeight,
                  ),
                  itemBuilder: (context, index) =>
                      _CreatorCard(group: _roleGroups()[index], comic: comic),
                );
              },
            ),
            const SizedBox(height: 6),
            GestureDetector(
              onTap: () => setState(() => _creatorsExpanded = false),
              behavior: HitTestBehavior.opaque,
              child: Text(
                'LESS',
                style: context.monoCaption.copyWith(
                  fontSize: 10,
                  color: widget.accent,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ],
      ],
    );
  }

  /// The collapsed creators line: the writers (or the first role credited),
  /// then how many other roles the expanded grid holds.
  // Not tappable: this is a one-line preview that doubles as the expand
  // tap target (`onTap` below). A tappable name here would compete with
  // that tap in the gesture arena and win, silently breaking expand/collapse
  // instead of opening a creator page. Per-name taps live in the expanded
  // card grid only, where there's no competing gesture.
  Widget _creatorsSummary(BuildContext context) {
    final groups = _roleGroups();
    final lead = groups.firstWhere((g) => g.role == 'writer',
        orElse: () => groups.first);
    final more = groups.length - 1;
    final leadNames =
        _flattenCredits(lead.creators).map((c) => c.name).join(', ');
    return GestureDetector(
      key: const ValueKey('creators-summary'),
      onTap: () => setState(() => _creatorsExpanded = true),
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Text(lead.role.toUpperCase(),
                style: context.monoCaption.copyWith(fontSize: 9.5)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                leadNames,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: context.scheme.tx,
                ),
              ),
            ),
            if (more > 0) ...[
              const SizedBox(width: 8),
              Text(
                '+$more more',
                style: context.monoCaption.copyWith(
                  fontSize: 10,
                  color: widget.accent,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  List<_RoleGroup> _roleGroups() {
    // Group by primary role (first comma-separated token), preserving
    // first-seen order so writers (listed first by ComicVine) lead.
    final byRole = <String, List<Creator>>{};
    for (final c in widget.creators) {
      final role = c.role.split(',').first.trim().toLowerCase();
      byRole.putIfAbsent(role.isEmpty ? 'other' : role, () => []).add(c);
    }
    return [
      for (final entry in byRole.entries) _RoleGroup(entry.key, entry.value),
    ];
  }
}

/// A [ConsumerStatefulWidget] (not stateless) so the [TapGestureRecognizer]s
/// built by [_creditSpans] have a State to be disposed from.
class _CreatorCard extends ConsumerStatefulWidget {
  final _RoleGroup group;
  final ComicTokens comic;

  const _CreatorCard({required this.group, required this.comic});

  @override
  ConsumerState<_CreatorCard> createState() => _CreatorCardState();
}

class _CreatorCardState extends ConsumerState<_CreatorCard> {
  final List<TapGestureRecognizer> _recognizers = [];

  void _disposeRecognizers() {
    for (final r in _recognizers) {
      r.dispose();
    }
    _recognizers.clear();
  }

  @override
  void dispose() {
    _disposeRecognizers();
    super.dispose();
  }

  String _initials() {
    final creators = widget.group.creators;
    final first = creators.isNotEmpty ? creators.first.name.trim() : '';
    if (first.isEmpty) return '?';
    final parts = first
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1))
        .toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    // A rebuild (theme change, role group content change) replaces every
    // span, so last build's recognizers must go first or they'd leak.
    _disposeRecognizers();
    final group = widget.group;
    final comic = widget.comic;

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: context.scheme.s1,
        borderRadius: BorderRadius.circular(AppTheme.r14),
        border: Border.all(
          color: comic.hardShadow ? comic.ink : context.scheme.borderFaint,
          width: comic.hardShadow ? comic.borderWidth : 0.5,
        ),
        boxShadow: comic.hardShadow ? comic.cardShadow : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: context.scheme.s3,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                _initials(),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: context.scheme.tx,
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          // Flexible so the name absorbs any leftover or missing pixels rather
          // than overflowing the fixed-height card. It already ellipsizes, so
          // a tight fit degrades to one line instead of a yellow-stripe error.
          Flexible(
            child: Text.rich(
              TextSpan(
                children: _creditSpans(context, ref, group.creators,
                    recognizers: _recognizers),
              ),
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: context.scheme.tx,
              ),
              // Two lines: a role group often credits several people
              // ("Chris Batista, Eddy Barrows, Joe Bennett, ..."), and one line
              // hid most of them behind an ellipsis.
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            group.role.toUpperCase(),
            style: context.monoCaption.copyWith(fontSize: 9.5),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
