import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

/// Reader's Claude panel: off, solid (interactive), or see-through (touches
/// fall through to the comic). The rail button cycles them in that order.
enum ClaudePanelMode {
  off,
  solid,
  ghost;

  ClaudePanelMode get next => values[(index + 1) % values.length];
}

const kClaudeUrl = 'https://claude.ai/code';

/// Drags go to the web view, not the page view or chrome swipe beneath.
final _eager = {
  Factory<OneSequenceGestureRecognizer>(EagerGestureRecognizer.new),
};

/// claude.ai in a web view over the comic, 40% wide on the side away from
/// the rail. Mounted on first open and kept (offstage) so toggling never
/// reloads; the default web data store keeps the login across launches.
class ClaudePanel extends StatelessWidget {
  const ClaudePanel({super.key, required this.mode, required this.railOnLeft});

  final ClaudePanelMode mode;
  final bool railOnLeft;

  @override
  Widget build(BuildContext context) {
    final ghost = mode == ClaudePanelMode.ghost;
    return Positioned(
      top: 0,
      // Above the keyboard while typing; the reader itself doesn't resize.
      bottom: MediaQuery.viewInsetsOf(context).bottom,
      left: railOnLeft ? null : 0,
      right: railOnLeft ? 0 : null,
      width: MediaQuery.sizeOf(context).width * 0.4,
      child: Offstage(
        offstage: mode == ClaudePanelMode.off,
        child: IgnorePointer(
          ignoring: ghost,
          child: Opacity(
            opacity: ghost ? 0.35 : 1,
            child: SafeArea(
              child: Padding(
                // Top clears the reader's title tag (Close lives there).
                padding: const EdgeInsets.fromLTRB(12, 84, 12, 12),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: const _ClaudeWeb(),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The page plus any popup it opens (Google sign-in uses one and posts the
/// result back to its opener, so the popup must be a real second window).
class _ClaudeWeb extends StatefulWidget {
  const _ClaudeWeb();

  @override
  State<_ClaudeWeb> createState() => _ClaudeWebState();
}

class _ClaudeWebState extends State<_ClaudeWeb> {
  static final _settings = InAppWebViewSettings(
    javaScriptCanOpenWindowsAutomatically: true,
    supportMultipleWindows: true,
  );

  CreateWindowAction? _popup;

  @override
  Widget build(BuildContext context) {
    return Stack(children: [
      InAppWebView(
        initialUrlRequest: URLRequest(url: WebUri(kClaudeUrl)),
        initialSettings: _settings,
        gestureRecognizers: _eager,
        onCreateWindow: (_, action) async {
          setState(() => _popup = action);
          return true;
        },
      ),
      if (_popup != null)
        Positioned.fill(
          child: InAppWebView(
            key: ValueKey(_popup!.windowId),
            windowId: _popup!.windowId,
            initialSettings: _settings,
            gestureRecognizers: _eager,
            onCloseWindow: (_) => setState(() => _popup = null),
          ),
        ),
    ]);
  }
}
