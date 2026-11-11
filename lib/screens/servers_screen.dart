import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/app_theme.dart';
import '../config/layout_breakpoint.dart';
import '../config/scheme.dart';
import '../config/platform.dart';
import '../models/download_item.dart';
import '../models/server_source.dart';
import '../providers/download_provider.dart';
import '../providers/accent_provider.dart';
import '../providers/connectivity_provider.dart';
import '../providers/server_actions.dart';
import '../providers/source_provider.dart';
import '../widgets/pro_sheet.dart';
import 'onboarding_screen.dart';

/// Settings → Servers: switch, edit (type, address, login), sign out of, and
/// (Pro) add servers. Edit and Add reuse the onboarding form.
class ServersScreen extends ConsumerWidget {
  const ServersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sources = ref.watch(sourceListProvider);
    // The local source's row counts its comics.
    if (sources.any(_local)) ref.watch(downloadStateProvider);
    final active = ref.watch(activeSourceProvider);
    final accent = ref.watch(accentProvider).value ?? AppTheme.accent;
    return Scaffold(
      backgroundColor: context.scheme.bg,
      appBar: AppBar(
          backgroundColor: context.scheme.bg, title: const Text('Servers')),
      body: ListView(
        children: [
          for (final s in sources.where((s) => s.baseUrl.isNotEmpty))
            ListTile(
              title: Text(_local(s) ? _localName : s.name,
                  style: TextStyle(color: context.scheme.tx)),
              subtitle: Text(
                  _local(s)
                      ? _comics(_comicCount(ref, s))
                      : '${s.type.label} · '
                          '${Uri.tryParse(s.baseUrl)?.host ?? s.baseUrl}',
                  style: TextStyle(color: context.scheme.t2)),
              leading: Icon(s.id == active.id ? Icons.check : null,
                  color: accent),
              onTap: () {
                HapticFeedback.selectionClick();
                ref.read(activeSourceIdProvider.notifier).select(s.id);
              },
              trailing: PopupMenuButton<String>(
                tooltip: '${s.name} options',
                onSelected: (v) => v == 'edit'
                    ? _edit(context, ref, s)
                    : _signOut(context, ref, s),
                itemBuilder: (_) => [
                  // Nothing to edit on a source with no address or login.
                  if (!_local(s))
                    const PopupMenuItem(value: 'edit', child: Text('Edit')),
                  PopupMenuItem(
                      value: 'signout',
                      child: Text(_local(s) ? 'Remove' : 'Sign out')),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: OutlinedButton.icon(
              icon: Icon(Icons.add, color: accent),
              label: Text('Add server', style: TextStyle(color: accent)),
              onPressed: () => _add(context, ref),
            ),
          ),
          // Free, and next to any servers. iOS only in v1.
          if (!isAndroid && !sources.any(_local))
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: OutlinedButton.icon(
                icon: Icon(Icons.folder_open, color: accent),
                label: Text('Read files on this ${LayoutBreakpoint.deviceNoun}',
                    style: TextStyle(color: accent)),
                onPressed: () {
                  HapticFeedback.selectionClick();
                  ref.read(serverActionsProvider).addLocal();
                },
              ),
            ),
        ],
      ),
    );
  }

  static bool _local(ServerSource s) => s.type == SourceType.local;
  static String get _localName => 'On this ${LayoutBreakpoint.deviceNoun}';
  static String _comics(int n) => '$n ${n == 1 ? 'comic' : 'comics'}';

  /// Comics imported into (or downloaded from) [s] on this device.
  static int _comicCount(WidgetRef ref, ServerSource s) =>
      (ref.read(downloadManagerProvider)?.currentState.completed ??
              const <DownloadItem>[])
          .where((i) =>
              i.sourceId == s.id && i.status == DownloadStatus.completed)
          .length;

  void _add(BuildContext context, WidgetRef ref) {
    if (!requirePro(context, ref,
        reason: 'More than one server is part of Pro.')) {
      return;
    }
    _pushForm(context, null, (ctx, found) async {
      await ref.read(serverActionsProvider).save(found: found);
      if (ctx.mounted) Navigator.pop(ctx);
    });
  }

  void _edit(BuildContext context, WidgetRef ref, ServerSource s) {
    _pushForm(context, s, (ctx, found) async {
      if (!sameServer(s, found) &&
          !await confirmLeaveServer(ctx, ref, s,
              title: 'Replace ${s.name}?',
              body: 'Its library and downloads on this ${LayoutBreakpoint.deviceNoun} are removed.',
              action: 'Replace')) {
        return;
      }
      await ref.read(serverActionsProvider).save(old: s, found: found);
      if (ctx.mounted) Navigator.pop(ctx);
    });
  }

  void _pushForm(BuildContext context, ServerSource? initial,
      Future<void> Function(BuildContext, ServerSource) onConnected) {
    Navigator.of(context).push(MaterialPageRoute(
      settings: const RouteSettings(name: '/servers/edit'),
      builder: (ctx) => OnboardingScreen(
          initial: initial, onConnected: (found) => onConnected(ctx, found)),
    ));
  }

  Future<void> _signOut(
      BuildContext context, WidgetRef ref, ServerSource s) async {
    if (!await confirmLeaveServer(context, ref, s,
        title: _local(s) ? 'Remove $_localName?' : 'Sign out of ${s.name}?',
        body: _local(s)
            ? 'This deletes ${_comics(_comicCount(ref, s))} from this '
                '${LayoutBreakpoint.deviceNoun}, with their reading progress '
                'and stats. The original files you imported from are not '
                'touched.'
            : 'Its library, downloads and reading stats on this '
                '${LayoutBreakpoint.deviceNoun} are removed.',
        action: _local(s) ? 'Delete' : 'Sign out')) {
      return;
    }
    final last = ref.read(sourceListProvider).length == 1;
    await ref.read(serverActionsProvider).signOut(s);
    // The last server leaves a blank one: back to the root, which is now
    // onboarding.
    if (last && context.mounted) {
      Navigator.of(context).popUntil((r) => r.isFirst);
    }
  }
}

/// Asks before [s] is forgotten, then sends its queued changes first. Returns
/// false if the user cancels, or keeps changes that still won't send.
Future<bool> confirmLeaveServer(
    BuildContext context, WidgetRef ref, ServerSource s,
    {required String title,
    required String body,
    required String action}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: ctx.scheme.s1,
      title: Text(title),
      content: Text(body),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel')),
        TextButton(
            onPressed: () => Navigator.pop(ctx, true), child: Text(action)),
      ],
    ),
  );
  if (ok != true || !context.mounted) return false;
  final actions = ref.read(serverActionsProvider);
  final pending = await actions.pendingCount(s);
  if (pending == 0) return true;
  // Offline, a send would only sit out the HTTP timeout: ask at once.
  // Try again always sends.
  var left = ref.read(connectivityProvider)
      ? await actions.flushOutbox(s)
      : pending;
  while (left > 0) {
    if (!context.mounted) return false;
    final choice = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: ctx.scheme.s1,
        title: Text('$left ${left == 1 ? 'change' : 'changes'} not synced to '
            '${s.name}'),
        content: const Text(
            'Reading progress made offline has not reached the server yet.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, 'cancel'),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, 'discard'),
              child: const Text('Discard and continue')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, 'retry'),
              child: const Text('Try again')),
        ],
      ),
    );
    if (choice == 'discard') return true;
    if (choice != 'retry') return false;
    left = await actions.flushOutbox(s);
  }
  return true;
}
