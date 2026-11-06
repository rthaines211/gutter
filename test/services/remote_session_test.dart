import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:comic_reader_app/services/remote_session.dart';

void main() {
  group('SseParser', () {
    test('extracts a single complete frame', () {
      final p = SseParser();
      expect(p.add('data: {"type":"next"}\n\n'), ['{"type":"next"}']);
    });

    test('buffers a frame split across chunks', () {
      final p = SseParser();
      expect(p.add('data: {"type":'), isEmpty);
      expect(p.add('"next"}\n\n'), ['{"type":"next"}']);
    });

    test('extracts two frames from one chunk', () {
      final p = SseParser();
      expect(
        p.add('data: {"a":1}\n\ndata: {"b":2}\n\n'),
        ['{"a":1}', '{"b":2}'],
      );
    });

    test('ignores keepalive comments', () {
      final p = SseParser();
      expect(p.add(': ping\n\n'), isEmpty);
    });

    test('keeps a trailing partial frame buffered', () {
      final p = SseParser();
      expect(p.add('data: {"a":1}\n\ndata: {"b":'), ['{"a":1}']);
      expect(p.add('2}\n\n'), ['{"b":2}']);
    });
  });

  group('RemoteSnapshot', () {
    test('round-trips through json', () {
      const s = RemoteSnapshot(
        comicId: 'abc',
        series: 'Saga',
        page: 4,
        totalPages: 20,
        bookmarked: true,
        hasNextIssue: false,
        readingMode: 'page',
      );
      final back = RemoteSnapshot.fromJson(s.toJson());
      expect(back.comicId, 'abc');
      expect(back.series, 'Saga');
      expect(back.page, 4);
      expect(back.totalPages, 20);
      expect(back.bookmarked, true);
      expect(back.hasNextIssue, false);
      expect(back.readingMode, 'page');
    });

    test('tolerates missing fields', () {
      final s = RemoteSnapshot.fromJson({'page': 2});
      expect(s.page, 2);
      expect(s.comicId, '');
      expect(s.totalPages, 0);
      expect(s.readingMode, 'page');
    });

    // An `as int?` cast on a JSON double throws inside the .map() feeding the
    // phone's StreamProvider, which kills that stream for the app's lifetime.
    test('accepts doubles for the numeric fields', () {
      final s = RemoteSnapshot.fromJson({'page': 4.0, 'totalPages': 20.0});
      expect(s.page, 4);
      expect(s.totalPages, 20);
    });
  });

  group('RemoteSession', () {
    late HttpServer server;
    late String baseUrl;
    late List<String> receivedPaths;
    late List<String> receivedBodies;
    late int commandStatus;

    setUp(() async {
      receivedPaths = [];
      receivedBodies = [];
      commandStatus = 204;
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      baseUrl = 'http://127.0.0.1:${server.port}';
      server.listen((req) async {
        receivedPaths.add('${req.method} ${req.uri.path}?${req.uri.query}');
        if (req.method == 'POST') {
          receivedBodies.add(await utf8.decoder.bind(req).join());
          req.response.statusCode =
              req.uri.path == '/remote/command' ? commandStatus : 204;
          await req.response.close();
          return;
        }
        req.response.headers.contentType =
            ContentType('text', 'event-stream');
        // Dart's HttpResponse buffers small writes by default and won't
        // push them to the socket until enough data accumulates or the
        // response closes — flush() alone doesn't override that. Disable
        // buffering so this fake SSE server streams like a real one.
        req.response.bufferOutput = false;
        req.response.write('data: {"type":"next"}\n\n');
        await req.response.flush();
        req.response.write(': ping\n\n');
        await req.response.flush();
        req.response.write('data: {"type":"prev"}\n\n');
        await req.response.flush();
      });
    });

    tearDown(() async => server.close(force: true));

    test('events() yields decoded frames and skips comments', () async {
      final session = RemoteSession(baseUrl: baseUrl);
      addTearDown(session.dispose);
      final got = await session.events('reader').take(2).toList();
      expect(got[0]['type'], 'next');
      expect(got[1]['type'], 'prev');
      expect(receivedPaths.first, 'GET /remote/events?role=reader');
    });

    test('sendCommand returns true on 204', () async {
      final session = RemoteSession(baseUrl: baseUrl);
      addTearDown(session.dispose);
      expect(await session.sendCommand('goto', page: 11), isTrue);
      expect(receivedBodies.single, contains('"page":11'));
    });

    test('a disabled session sends nothing', () async {
      final session = RemoteSession(baseUrl: baseUrl, enabled: false);
      addTearDown(session.dispose);
      await session.publishState(const RemoteSnapshot(comicId: 'c', series: 's', page: 1, totalPages: 2, bookmarked: false, hasNextIssue: false, readingMode: 'page'));
      expect(await session.sendCommand('next'), isFalse);
      expect(await session.events('reader').toList(), isEmpty);
      expect(receivedPaths, isEmpty);
    });

    test('sendCommand returns false on 409', () async {
      commandStatus = 409;
      final session = RemoteSession(baseUrl: baseUrl);
      addTearDown(session.dispose);
      expect(await session.sendCommand('next'), isFalse);
    });

    test('publishState posts the snapshot', () async {
      final session = RemoteSession(baseUrl: baseUrl);
      addTearDown(session.dispose);
      await session.publishState(const RemoteSnapshot(
        comicId: 'abc',
        series: 'Saga',
        page: 4,
        totalPages: 20,
        bookmarked: false,
        hasNextIssue: true,
        readingMode: 'page',
      ));
      expect(receivedPaths.last, 'POST /remote/state?');
      expect(receivedBodies.single, contains('"comicId":"abc"'));
    });

    test('events() reconnects after the connection drops mid-stream',
        () async {
      var attempt = 0;
      final localServer =
          await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final localBaseUrl = 'http://127.0.0.1:${localServer.port}';
      localServer.listen((req) async {
        attempt++;
        req.response.headers.contentType =
            ContentType('text', 'event-stream');
        req.response.bufferOutput = false;
        if (attempt == 1) {
          // First connection: one frame, then the server drops it.
          req.response.write('data: {"type":"next"}\n\n');
          await req.response.flush();
          await req.response.close();
          return;
        }
        // Reconnect attempt: a normal, still-open stream.
        req.response.write('data: {"type":"next"}\n\n');
        await req.response.flush();
        req.response.write('data: {"type":"prev"}\n\n');
        await req.response.flush();
      });
      addTearDown(() => localServer.close(force: true));

      final session = RemoteSession(
        baseUrl: localBaseUrl,
        sleep: (_) async {}, // don't actually wait between reconnects
      );
      addTearDown(session.dispose);

      final got = await session.events('reader').take(3).toList();
      expect(got.map((e) => e['type']).toList(), ['next', 'next', 'prev']);
      expect(attempt, greaterThanOrEqualTo(2));
    });

    test(
        'events() backoff escalates on repeated failures, resets after a '
        'success, and caps at 30s', () async {
      final delays = <Duration>[];
      final gotEightDelays = Completer<void>();
      var attempt = 0;
      final localServer =
          await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final localBaseUrl = 'http://127.0.0.1:${localServer.port}';
      localServer.listen((req) async {
        attempt++;
        if (attempt == 3) {
          // One success in the middle of a run of failures: connects, sends
          // one event, then drops — this should reset backoff to 1s.
          req.response.headers.contentType =
              ContentType('text', 'event-stream');
          req.response.bufferOutput = false;
          req.response.write('data: {"type":"next"}\n\n');
          await req.response.flush();
          await req.response.close();
          return;
        }
        req.response.statusCode = 500;
        await req.response.close();
      });
      addTearDown(() => localServer.close(force: true));

      final session = RemoteSession(
        baseUrl: localBaseUrl,
        sleep: (d) async {
          delays.add(d);
          if (delays.length == 8 && !gotEightDelays.isCompleted) {
            gotEightDelays.complete();
          }
        },
      );
      addTearDown(session.dispose);

      final sub = session.events('reader').listen((_) {});
      await gotEightDelays.future.timeout(const Duration(seconds: 5));
      // The fake sleep never waits, so the loop would hammer the local
      // server indefinitely if it could not be stopped. Cancelling is
      // enough now; dispose() closes the shared client as well.
      await sub.cancel();
      session.dispose();

      // Escalates 1s -> 2s across the first two failures, resets to 1s after
      // the attempt-3 success, then escalates again from that reset baseline.
      expect(delays.sublist(0, 4), [
        const Duration(seconds: 1),
        const Duration(seconds: 2),
        const Duration(seconds: 1),
        const Duration(seconds: 2),
      ]);
      expect(delays[7], const Duration(seconds: 30));
      expect(
        delays.every((d) => d <= const Duration(seconds: 30)),
        isTrue,
      );
    });

    // The backend decides "which iPad is reading" purely by who holds an
    // open role=reader stream. If cancelling the subscription leaves the
    // socket open, the relay counts a reader forever: POST /remote/command
    // answers 204 while nothing is listening. This pins that lifecycle.
    test('cancelling a subscription closes the connection and a fresh '
        'events() call reconnects', () async {
      var open = 0;
      var connects = 0;
      // Spoken over a raw ServerSocket, not HttpServer, on purpose: dart:io's
      // HttpResponse.flush() to a peer that has gone away blocks forever
      // instead of throwing, so an HttpServer literally cannot observe a
      // client disconnect. The socket's own onDone can.
      final raw = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      raw.listen((sock) {
        connects++;
        open++;
        Timer? ping;
        void gone() {
          if (ping == null) return;
          ping!.cancel();
          ping = null;
          open--;
          sock.destroy();
        }

        sock.listen((_) {}, onDone: gone, onError: (_) => gone());
        unawaited(sock.done.catchError((_) => sock));
        sock.write('HTTP/1.1 200 OK\r\n'
            'Content-Type: text/event-stream\r\n\r\n');
        sock.write('data: {"type":"next"}\n\n');
        // Keepalive comments only from here. They carry no `data:` payload,
        // so an async* generator parked in `await for` never reaches a yield
        // and never observes the cancel — the old implementation held this
        // connection open forever, which is exactly finding C1.
        ping = Timer.periodic(const Duration(milliseconds: 20), (_) {
          try {
            sock.write(': ping\n\n');
          } catch (_) {
            gone();
          }
        });
      });
      addTearDown(raw.close);

      final session = RemoteSession(
        baseUrl: 'http://127.0.0.1:${raw.port}',
        sleep: (_) async {},
      );
      addTearDown(session.dispose);

      Future<void> waitFor(bool Function() cond, String what) async {
        final deadline = DateTime.now().add(const Duration(seconds: 3));
        while (!cond() && DateTime.now().isBefore(deadline)) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
        expect(cond(), isTrue, reason: what);
      }

      final first = <Map<String, dynamic>>[];
      final sub = session.events('reader').listen(first.add);
      await waitFor(() => first.isNotEmpty, 'first stream never got a frame');
      expect(open, 1);

      await sub.cancel();
      await waitFor(() => open == 0, 'connection outlived its subscription');
      // No reconnect loop left running behind the cancel.
      final connectsAfterCancel = connects;
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(connects, connectsAfterCancel);

      // The session is still usable: reopening the reader must work.
      final second = <Map<String, dynamic>>[];
      final sub2 = session.events('reader').listen(second.add);
      await waitFor(() => second.isNotEmpty, 'reopened stream got no frames');
      expect(open, 1);
      expect(connects, connectsAfterCancel + 1);
      await sub2.cancel();
      await waitFor(() => open == 0, 'second connection outlived its cancel');
    });

    test('events() drains a non-200 body and does not reset backoff until '
        'bytes arrive', () async {
      final delays = <Duration>[];
      final gotFour = Completer<void>();
      var attempt = 0;
      final localServer =
          await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      localServer.listen((req) async {
        attempt++;
        if (attempt == 3) {
          // Accept-then-drop: 200 with zero bytes. Resetting backoff on the
          // status line alone would hot-loop at 1s against such a server.
          req.response.headers.contentType =
              ContentType('text', 'event-stream');
          req.response.bufferOutput = false;
          await req.response.close();
          return;
        }
        req.response.statusCode = 500;
        req.response.write('nope');
        await req.response.close();
      });
      addTearDown(() => localServer.close(force: true));

      final session = RemoteSession(
        baseUrl: 'http://127.0.0.1:${localServer.port}',
        sleep: (d) async {
          delays.add(d);
          if (delays.length == 4 && !gotFour.isCompleted) gotFour.complete();
        },
      );
      final sub = session.events('reader').listen((_) {});
      await gotFour.future.timeout(const Duration(seconds: 5));
      await sub.cancel();
      session.dispose();

      expect(delays.sublist(0, 4), [
        const Duration(seconds: 1),
        const Duration(seconds: 2),
        const Duration(seconds: 4), // the empty 200 did NOT reset it
        const Duration(seconds: 8),
      ]);
    });

    // The iPad publishes from build(), and build() only runs when reader
    // state changes. Without a resend on reconnect, a Wi-Fi blip means: hub
    // sees the last reader leave, clears state, fires reader_gone, the phone
    // empties — and stays empty until the next page turn. The session is the
    // only object that knows both the last snapshot and that it reconnected.
    test('a reader reconnect re-posts the last snapshot', () async {
      var attempt = 0;
      final localServer =
          await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final posts = <String>[];
      localServer.listen((req) async {
        if (req.method == 'POST') {
          posts.add(await utf8.decoder.bind(req).join());
          req.response.statusCode = 204;
          await req.response.close();
          return;
        }
        attempt++;
        req.response.headers.contentType =
            ContentType('text', 'event-stream');
        req.response.bufferOutput = false;
        req.response.write('data: {"type":"next"}\n\n');
        await req.response.flush();
        if (attempt == 1) await req.response.close(); // drop, forcing a retry
      });
      addTearDown(() => localServer.close(force: true));

      final session = RemoteSession(
        baseUrl: 'http://127.0.0.1:${localServer.port}',
        sleep: (_) async {},
      );
      addTearDown(session.dispose);

      const snap = RemoteSnapshot(
        comicId: 'abc',
        series: 'Saga',
        page: 4,
        totalPages: 20,
        bookmarked: false,
        hasNextIssue: false,
        readingMode: 'page',
      );

      final sub = session.events('reader').listen((_) {});
      addTearDown(sub.cancel);
      await session.publishState(snap);
      expect(posts.length, 1, reason: 'first publish did not post');

      // Identical snapshot: deduped, no second POST.
      await session.publishState(snap);
      expect(posts.length, 1, reason: 'identical snapshot was re-posted');

      // The drop on attempt 1 forces a reconnect, which must resend.
      final deadline = DateTime.now().add(const Duration(seconds: 3));
      while (posts.length < 2 && DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(posts.length, greaterThanOrEqualTo(2),
          reason: 'reconnect did not resend the snapshot');
      expect(posts.last, contains('"comicId":"abc"'));
    });

    test('connectionChanges seeds the current state for a late listener',
        () async {
      final session = RemoteSession(baseUrl: baseUrl);
      addTearDown(session.dispose);
      // Nothing connected yet: a listener must be told false, not left
      // hanging until the next flap.
      expect(await session.connectionChanges.first, isFalse);
    });

    test('connectionChanges reports true on bytes and false on a drop',
        () async {
      var attempt = 0;
      final localServer =
          await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      localServer.listen((req) async {
        attempt++;
        req.response.headers.contentType =
            ContentType('text', 'event-stream');
        req.response.bufferOutput = false;
        req.response.write('data: {"type":"next"}\n\n');
        await req.response.flush();
        if (attempt == 1) await req.response.close();
      });
      addTearDown(() => localServer.close(force: true));

      final session = RemoteSession(
        baseUrl: 'http://127.0.0.1:${localServer.port}',
        sleep: (_) async {},
      );
      addTearDown(session.dispose);

      final seen = <bool>[];
      final sub0 = session.connectionChanges.listen(seen.add);
      addTearDown(sub0.cancel);
      final sub = session.events('reader').listen((_) {});
      addTearDown(sub.cancel);

      final deadline = DateTime.now().add(const Duration(seconds: 3));
      while (seen.length < 3 && DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      // seeded false -> connected -> dropped
      expect(seen.take(3).toList(), [false, true, false]);
    });

    // Without this, a blackholed TCP connection reports connected forever and
    // the phone's banner lies about exactly the failure it exists to show.
    test('an idle stream past the timeout is dropped and reconnected',
        () async {
      var connects = 0;
      final raw = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      raw.listen((sock) {
        connects++;
        sock.listen((_) {}, onDone: () {}, onError: (_) {});
        unawaited(sock.done.catchError((_) => sock));
        sock.write('HTTP/1.1 200 OK\r\n'
            'Content-Type: text/event-stream\r\n\r\n');
        sock.write('data: {"type":"next"}\n\n');
        // Then silence forever: no data, no keepalive, socket still open.
      });
      addTearDown(raw.close);

      final session = RemoteSession(
        baseUrl: 'http://127.0.0.1:${raw.port}',
        sleep: (_) async {},
        idleTimeout: const Duration(milliseconds: 80),
      );
      addTearDown(session.dispose);

      final sub = session.events('reader').listen((_) {});
      addTearDown(sub.cancel);

      final deadline = DateTime.now().add(const Duration(seconds: 3));
      while (connects < 2 && DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(connects, greaterThanOrEqualTo(2),
          reason: 'a silent connection was never timed out');
    });

    test('dispose() terminates the connection and stops the event loop',
        () async {
      final session = RemoteSession(baseUrl: baseUrl);
      final events = <Map<String, dynamic>>[];
      final done = Completer<void>();
      session.events('reader').listen(events.add, onDone: done.complete);

      // Let it connect and receive data over a connection the fake server
      // never closes on its own.
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(events, isNotEmpty);

      session.dispose();

      // dispose() must actually abort the in-flight read and end the async*
      // loop — proven by the stream reporting done, not just by no longer
      // listening to it.
      await done.future.timeout(const Duration(seconds: 2));
      final countAtDone = events.length;
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(events.length, countAtDone);
    });
  });
}
