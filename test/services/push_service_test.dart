import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:comic_reader_app/app.dart';
import 'package:comic_reader_app/models/server_source.dart';
import 'package:comic_reader_app/providers/navigation_provider.dart';
import 'package:comic_reader_app/services/push_service.dart';

const channel = MethodChannel('app.comic_reader/push');

const source = ServerSource(
  id: 'default',
  name: 'My Server',
  type: SourceType.custom,
  baseUrl: 'https://lcs.example.org',
  authType: AuthType.apiKey,
  apiKey: 's3cret',
);

/// Delivers a native → Dart call on [channel], as PushBridge.swift would.
Future<void> fromNative(String method, Object? args) async {
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  await messenger.handlePlatformMessage(
    channel.name,
    const StandardMethodCodec().encodeMethodCall(MethodCall(method, args)),
    (_) {},
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('registerDevice posts token with source auth', () async {
    late http.Request sent;
    final svc = PushService(
      channel: channel,
      client: MockClient((req) async {
        sent = req;
        return http.Response('', 204);
      }),
      source: () => source,
      onTap: (_) {},
    );
    await svc.registerDevice('abc', 'sandbox');
    expect(sent.method, 'POST');
    expect(sent.url.toString(), 'https://lcs.example.org/devices');
    expect(sent.headers['Authorization'], 'Bearer s3cret');
    expect(sent.headers['Content-Type'], startsWith('application/json'));
    expect(jsonDecode(sent.body), {'token': 'abc', 'env': 'sandbox'});
  });

  test('registerDevice swallows non-2xx and network errors', () async {
    for (final client in [
      MockClient((_) async => http.Response('', 401)),
      MockClient((_) async => throw http.ClientException('offline')),
    ]) {
      final svc = PushService(
          channel: channel, client: client, source: () => source, onTap: (_) {});
      await svc.registerDevice('abc', 'sandbox'); // must not throw
    }
  });

  test('start invokes register and handles token callback', () async {
    final calls = <String>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      return call.method == 'register' ? true : null;
    });
    var posts = 0;
    final svc = PushService(
      channel: channel,
      client: MockClient((_) async {
        posts++;
        return http.Response('', 204);
      }),
      source: () => source,
      onTap: (_) {},
    );
    await svc.start();
    expect(calls, ['register', 'initialScreen']);
    await fromNative('token', {'token': 'abc', 'env': 'production'});
    expect(posts, 1);
  });

  test('tap callback forwards screen; cold-start initialScreen too', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      return switch (call.method) {
        'register' => true,
        'initialScreen' => 'read',
        _ => null,
      };
    });
    final taps = <String?>[];
    final svc = PushService(
      channel: channel,
      client: MockClient((_) async => http.Response('', 204)),
      source: () => source,
      onTap: taps.add,
    );
    await svc.start();
    expect(taps, ['read']);
    await fromNative('tap', {'screen': 'review'});
    expect(taps, ['read', 'review']);
  });

  test('start is a no-op where the native side is missing', () async {
    final svc = PushService(
      channel: channel,
      client: MockClient((_) async => http.Response('', 204)),
      source: () => source,
      onTap: (_) => fail('no tap expected'),
    );
    await svc.start(); // no mock handler → MissingPluginException, swallowed
  });

  sourceChangeTests();
}

void sourceChangeTests() {
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  test('sourceChanged re-sends the last token; no-op before one arrives', () async {
    messenger.setMockMethodCallHandler(
        channel, (call) async => call.method == 'register' ? true : null);
    final auths = <String?>[];
    var current = source.copyWith(apiKey: '');
    final svc = PushService(
      channel: channel,
      client: MockClient((req) async {
        auths.add(req.headers['Authorization']);
        return http.Response('', req.headers['Authorization'] == 'Bearer s3cret' ? 204 : 401);
      }),
      source: () => current,
      onTap: (_) {},
    );
    await svc.sourceChanged();
    expect(auths, isEmpty);
    await svc.start();
    await fromNative('token', {'token': 'abc', 'env': 'sandbox'});
    current = source; // user sets the API key / keychain load finishes
    await svc.sourceChanged();
    expect(auths, ['Bearer ', 'Bearer s3cret']);
    messenger.setMockMethodCallHandler(channel, null);
  });

  testWidgets('read tap pops pushed routes back to the shell', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await tester.pumpWidget(MaterialApp(
      navigatorKey: navigatorKey,
      home: const Text('shell'),
    ));
    navigatorKey.currentState!
        .push(MaterialPageRoute(builder: (_) => const Text('reader')));
    await tester.pumpAndSettle();
    expect(find.text('reader'), findsOneWidget);
    container.read(navigationProvider.notifier).go(NavDestination.library);

    routePushTap(container, 'read');
    await tester.pumpAndSettle();
    expect(find.text('reader'), findsNothing);
    expect(find.text('shell'), findsOneWidget);
    expect(container.read(navigationProvider), NavDestination.read);
  });
}
