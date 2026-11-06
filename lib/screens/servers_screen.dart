import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/app_theme.dart';
import '../config/scheme.dart';
import '../models/server_source.dart';
import '../providers/accent_provider.dart';
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
              title: Text(s.name, style: TextStyle(color: context.scheme.tx)),
              subtitle: Text(
                  '${s.type == SourceType.komga ? 'Komga' : 'Gutter'} · '
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
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'edit', child: Text('Edit')),
                  PopupMenuItem(value: 'signout', child: Text('Sign out')),
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
        ],
      ),
    );
  }

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
              body: 'Its library and downloads on this iPad are removed.',
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
        title: 'Sign out of ${s.name}?',
        body: 'Its library, downloads and reading stats on this iPad are '
            'removed.',
        action: 'Sign out')) {
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
  if (await actions.pendingCount(s) == 0) return true;
  var left = await actions.flushOutbox(s);
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
