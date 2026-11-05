import 'package:flutter/material.dart';
import '../config/scheme.dart';
import 'liquid_glass.dart';

/// The reader's "…" menu. Shown as a route (the reader anchors it under the
/// button); each item pops the menu, then runs its action.
class ReaderMoreMenu extends StatelessWidget {
  final VoidCallback onChapters;
  final VoidCallback onAllPages;

  /// Null hides the item (no series to recap).
  final VoidCallback? onRecap;
  /// Null hides the item (scroll mode: no page to clip from).
  final VoidCallback? onClipPanel;

  /// Null hides the item (no series page to open).
  final VoidCallback? onIssueDetails;

  /// Null hides the item (not on a page, e.g. the end card).
  final VoidCallback? onFlagPage;

  /// Null hides the item (not on a page, e.g. the end card).
  final VoidCallback? onFixPanels;
  /// Null hides the item (not on a page, e.g. the end card).
  final VoidCallback? onFixBalloons;

  /// Null hides the item.
  final VoidCallback? onCredits;

  const ReaderMoreMenu({
    super.key,
    required this.onChapters,
    required this.onAllPages,
    this.onRecap,
    this.onClipPanel,
    this.onIssueDetails,
    this.onFlagPage,
    this.onFixPanels,
    this.onFixBalloons,
    this.onCredits,
  });

  @override
  Widget build(BuildContext context) {
    final items = <(IconData, String, VoidCallback)>[
      (Icons.toc, 'Chapters', onChapters),
      (Icons.grid_view, 'All pages', onAllPages),
      if (onRecap case final recap?) (Icons.history, 'Recap so far', recap),
      if (onClipPanel case final clip?) (Icons.crop, 'Clip a panel', clip),
      if (onFlagPage case final flag?) (Icons.flag_outlined, 'Flag page', flag),
      if (onFixPanels case final fix?) (Icons.crop_square, 'Fix panels', fix),
      if (onFixBalloons case final fix?)
        (Icons.chat_bubble_outline, 'Fix balloons', fix),
      if (onIssueDetails case final details?)
        (Icons.info_outline, 'Issue details', details),
      if (onCredits case final credits?)
        (Icons.people_alt_outlined, 'Credits', credits),
    ];
    final scheme = context.scheme;
    return Material(
      type: MaterialType.transparency,
      child: SizedBox(
        width: 230,
        child: LiquidGlass(
          radius: 16,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final (i, (icon, label, onTap)) in items.indexed)
                InkWell(
                  onTap: () {
                    Navigator.of(context).pop();
                    onTap();
                  },
                  child: Container(
                    height: 46,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    decoration: i == 0
                        ? null
                        : BoxDecoration(
                            border: Border(
                              top: BorderSide(color: scheme.hair, width: 0.5),
                            ),
                          ),
                    child: Row(
                      children: [
                        Icon(icon, size: 18, color: scheme.tx),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            label,
                            style: TextStyle(fontSize: 15, color: scheme.tx),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
