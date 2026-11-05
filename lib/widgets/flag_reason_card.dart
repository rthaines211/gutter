import 'package:flutter/material.dart';
import '../config/scheme.dart';
import 'liquid_glass.dart';

/// The reasons the reader offers per zoom mode; the server accepts the same.
const flagReasons = <String, List<(String, String)>>{
  'panels': [
    ('order', 'Order is wrong'),
    ('panel_missing', 'A panel is missing'),
    ('panel_cut', 'A panel is cut wrong'),
  ],
  'bubbles': [
    ('order', 'Order is wrong'),
    ('balloon_missing', 'A balloon is missing'),
    ('balloon_cut', 'A balloon is cut wrong'),
  ],
};

/// Asks what's wrong with [page] (0-based) in [zoom] mode. Returns the reason
/// code, or null on Cancel / tap outside (nothing gets flagged).
Future<String?> showFlagReasonCard(BuildContext context,
    {required String zoom, required int page}) {
  final reasons = flagReasons[zoom] ?? const [];
  return showDialog<String>(
    context: context,
    barrierColor: context.scheme.scrim,
    builder: (context) {
      final scheme = context.scheme;
      return Center(
        child: Material(
          type: MaterialType.transparency,
          child: SizedBox(
            width: 300,
            child: LiquidGlass(
              radius: 18,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 18, 16, 8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text("What's wrong on page ${page + 1}?",
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: scheme.tx)),
                    const SizedBox(height: 12),
                    for (final (code, label) in reasons)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: SizedBox(
                          width: double.infinity,
                          height: 46,
                          child: TextButton(
                            style: TextButton.styleFrom(
                              backgroundColor: scheme.tx.withValues(alpha: 0.08),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                            onPressed: () => Navigator.of(context).pop(code),
                            child: Text(label, style: TextStyle(fontSize: 15, color: scheme.tx)),
                          ),
                        ),
                      ),
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: Text('Cancel', style: TextStyle(color: scheme.tx.withValues(alpha: 0.6))),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}
