import 'dart:async';

import 'package:flutter/material.dart';

/// Dispatches remote-control commands to reader callbacks.
///
/// Modeled on [VolumeKeyListener]: an external input source wrapped around
/// the reader that calls the same handlers a volume press would. Taking the
/// command stream as a parameter keeps it testable without a network.
class RemoteControlListener extends StatefulWidget {
  final Widget child;
  final Stream<Map<String, dynamic>> commands;
  final VoidCallback onNext;
  final VoidCallback onPrev;
  final VoidCallback onBookmark;
  final VoidCallback onNextIssue;
  final void Function(int page) onGoto;
  final bool enabled;

  const RemoteControlListener({
    super.key,
    required this.child,
    required this.commands,
    required this.onNext,
    required this.onPrev,
    required this.onBookmark,
    required this.onNextIssue,
    required this.onGoto,
    this.enabled = true,
  });

  @override
  State<RemoteControlListener> createState() => _RemoteControlListenerState();
}

class _RemoteControlListenerState extends State<RemoteControlListener> {
  StreamSubscription<Map<String, dynamic>>? _sub;

  @override
  void initState() {
    super.initState();
    _subscribe();
  }

  @override
  void didUpdateWidget(RemoteControlListener oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.commands != widget.commands ||
        oldWidget.enabled != widget.enabled) {
      _sub?.cancel();
      _sub = null;
      _subscribe();
    }
  }

  void _subscribe() {
    if (!widget.enabled) return;
    _sub = widget.commands.listen(_dispatch);
  }

  void _dispatch(Map<String, dynamic> cmd) {
    if (!mounted) return;
    switch (cmd['type']) {
      case 'next':
        widget.onNext();
      case 'prev':
        widget.onPrev();
      case 'bookmark':
        widget.onBookmark();
      case 'nextIssue':
        widget.onNextIssue();
      case 'goto':
        widget.onGoto(cmd['page'] is int ? cmd['page'] as int : 0);
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
