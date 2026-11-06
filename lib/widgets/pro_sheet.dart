import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import '../config/app_theme.dart';
import '../config/scheme.dart';
import '../providers/accent_provider.dart';
import '../providers/pro_provider.dart';

const _features = [
  (Icons.download_for_offline_outlined, 'Offline downloads'),
  (Icons.center_focus_strong_outlined, 'Guided spread zoom'),
  (Icons.dns_outlined, 'More than one server'),
  (Icons.insights_outlined, 'Reading stats'),
];

/// True when Pro is unlocked; otherwise opens the paywall and returns false.
bool requirePro(BuildContext context, WidgetRef ref, {required String reason}) {
  if (ref.read(proProvider)) return true;
  showProSheet(context, reason: reason);
  return false;
}

Future<void> showProSheet(BuildContext context, {String? reason}) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.scheme.s2,
      builder: (_) => ProSheet(reason: reason),
    );

/// The one-time Pro unlock: features, price, Buy and Restore Purchases.
/// Closes itself once Pro unlocks.
class ProSheet extends ConsumerStatefulWidget {
  final String? reason;
  const ProSheet({super.key, this.reason});

  @override
  ConsumerState<ProSheet> createState() => _ProSheetState();
}

class _ProSheetState extends ConsumerState<ProSheet> {
  late final Future<ProductDetails?> _product =
      ref.read(proProvider.notifier).product;

  void _say(ScaffoldMessengerState messenger, String text) =>
      messenger.showSnackBar(SnackBar(content: Text(text)));

  Future<void> _buy() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(proProvider.notifier).buy();
    } catch (_) {
      _say(messenger, "Couldn't start the purchase. Try Restore Purchases.");
    }
  }

  /// StoreKit sends nothing when there's nothing to restore, so give it a
  /// few seconds and say so.
  Future<void> _restore() async {
    final messenger = ScaffoldMessenger.of(context);
    // The sheet may close (unlocked) before the wait ends.
    final container = ProviderScope.containerOf(context);
    try {
      await container.read(proProvider.notifier).restore();
    } catch (_) {
      _say(messenger, "Couldn't reach the App Store. Try again later.");
      return;
    }
    await Future<void>.delayed(const Duration(seconds: 5));
    if (container.read(proProvider)) return;
    _say(messenger, 'No purchase to restore.');
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(proProvider, (_, pro) {
      if (pro && mounted) Navigator.of(context).pop();
    });
    final accent = ref.watch(accentProvider).value ?? AppTheme.accent;
    return SafeArea(
      // Scrolls when large Dynamic Type makes it taller than the screen.
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Gutter Pro', style: Theme.of(context).textTheme.titleLarge),
            if (widget.reason != null) ...[
              const SizedBox(height: 6),
              Text(widget.reason!, style: TextStyle(color: context.scheme.t2)),
            ],
            const SizedBox(height: 16),
            for (final (icon, label) in _features)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(icon, color: accent),
                title: Text(label),
              ),
            const SizedBox(height: 8),
            Text('One purchase, every future version. No subscription.',
                style: TextStyle(color: context.scheme.t2)),
            const SizedBox(height: 16),
            FutureBuilder(
              future: _product,
              builder: (context, snap) {
                final product = snap.data;
                final pro = ref.watch(proProvider);
                return FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: accent),
                  onPressed: pro || product == null
                      ? null
                      : _buy,
                  child: Text(pro
                      ? 'Unlocked'
                      : product != null
                          ? 'Unlock for ${product.price}'
                          : snap.connectionState == ConnectionState.done
                              ? 'Unavailable'
                              : 'Loading…'),
                );
              },
            ),
            TextButton(
              onPressed: _restore,
              child: const Text('Restore Purchases'),
            ),
          ],
        ),
      ),
    );
  }
}
