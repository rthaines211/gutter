import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../app.dart';
import '../models/server_source.dart';
import '../providers/navigation_provider.dart';
import '../providers/review_provider.dart';

/// Push notifications: registers this device's APNs token with the server and
/// routes notification taps. The native half is ios/Runner/PushBridge.swift.
class PushService {
  PushService({
    required this.channel,
    required this.client,
    required this.source,
    required this.onTap,
  });

  final MethodChannel channel;
  final http.Client client;
  final ServerSource Function() source;
  final void Function(String? screen) onTap;

  /// The last token APNs gave us, so a source change can re-send it.
  ({String token, String env})? _last;

  /// Asks for permission and registers with APNs. Call on every launch: tokens
  /// can rotate, and re-registering is an upsert on the server.
  Future<void> start() async {
    channel.setMethodCallHandler(_onNativeCall);
    try {
      await channel.invokeMethod<bool>('register');
      final screen = await channel.invokeMethod<String>('initialScreen');
      if (screen != null) onTap(screen);
    } on MissingPluginException {
      // No native side (tests, non-iOS): push is simply off.
    } on PlatformException catch (e) {
      debugPrint('push: $e');
    }
  }

  Future<void> _onNativeCall(MethodCall call) async {
    final args = Map<String, Object?>.from(call.arguments as Map? ?? const {});
    switch (call.method) {
      case 'token':
        _last = (token: args['token'] as String, env: args['env'] as String);
        await registerDevice(_last!.token, _last!.env);
      case 'tap':
        onTap(args['screen'] as String?);
    }
  }

  /// Re-sends the token after the active source changes: the API key being
  /// set in Settings, or loading from the keychain after the token arrived.
  /// Without this a 401 at launch lasts until the next cold start.
  Future<void> sourceChanged() async {
    final last = _last;
    if (last != null) await registerDevice(last.token, last.env);
  }

  /// Never throws: a server that's down or refuses the secret just means no
  /// pushes until the next launch.
  Future<void> registerDevice(String token, String env) async {
    final src = source();
    // Only a Gutter server takes device registrations.
    if (src.type != SourceType.custom) return;
    try {
      final resp = await client.post(
        Uri.parse('${src.baseUrl}/devices'),
        headers: {...src.authHeaders, 'Content-Type': 'application/json'},
        body: jsonEncode({'token': token, 'env': env}),
      );
      if (resp.statusCode >= 300) {
        debugPrint('push: register device → ${resp.statusCode}');
      }
    } catch (e) {
      debugPrint('push: register device failed: $e');
    }
  }
}

/// Where a notification tap lands: "read" → Read tab, "review" → the match
/// review queue. Anything else just opens the app.
void routePushTap(ProviderContainer container, String? screen) {
  switch (screen) {
    case 'read':
      // The reader is pushed over the shell; drop back so the tab is visible.
      navigatorKey.currentState?.popUntil((r) => r.isFirst);
      container.read(navigationProvider.notifier).go(NavDestination.read);
    case 'review':
      navigatorKey.currentState?.popUntil((r) => r.isFirst);
      // The pipeline pushed because the queue changed; drop the stale snapshot.
      container.invalidate(reviewQueueProvider);
      container.read(navigationProvider.notifier).go(NavDestination.review);
  }
}
