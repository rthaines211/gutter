// test/providers/scan_controller_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:comic_reader_app/models/chapter_candidate.dart';
import 'package:comic_reader_app/providers/providers.dart';
import 'package:comic_reader_app/providers/scan_provider.dart';
import 'package:comic_reader_app/providers/scan_state.dart';
import 'package:comic_reader_app/services/api_client.dart';

class _FakeApi extends ApiClient {
  _FakeApi() : super(baseUrl: 'http://t', deviceId: 'd');

  bool ocrPending = true;
  int statusCalls = 0;
  // Scripted status results, consumed in order.
  List<({String state, int scanned, int total, List<ChapterCandidate> candidates})> script = const [];
  Object? postError;
  // If set, every status poll reports state 'running' with scanned = gen(call) —
  // used to drive the progress watchdog over many polls.
  int Function(int call)? progressGen;

  @override
  Future<({List<ChapterCandidate> candidates, bool ocrPending, String? jobId})>
      detectChapters(String comicId, {int? exemplarPage}) async {
    if (postError != null) throw postError!;
    return (candidates: const <ChapterCandidate>[], ocrPending: ocrPending, jobId: ocrPending ? 'job1' : null);
  }

  @override
  Future<({String state, int scanned, int total, List<ChapterCandidate> candidates})>
      detectChaptersStatus(String comicId, String jobId) async {
    if (progressGen != null) {
      final s = progressGen!(statusCalls);
      statusCalls++;
      return (state: 'running', scanned: s, total: 2000, candidates: const <ChapterCandidate>[]);
    }
    final r = script[statusCalls.clamp(0, script.length - 1)];
    statusCalls++;
    return r;
  }
}

ProviderContainer _containerWith(_FakeApi api) =>
    ProviderContainer(overrides: [apiClientProvider.overrideWithValue(api)]);

void main() {
  test('immediate done when OCR not pending', () async {
    final api = _FakeApi()..ocrPending = false;
    final c = _containerWith(api);
    addTearDown(c.dispose);
    await c.read(scanProvider.notifier).start(comicId: 'x', title: 'X');
    expect(c.read(scanProvider).phase, ScanPhase.done);
  });

  test('running → progress → done across polls', () async {
    final api = _FakeApi()
      ..ocrPending = true
      ..script = [
        (state: 'running', scanned: 100, total: 435, candidates: const []),
        (state: 'done', scanned: 435, total: 435, candidates: const [
          ChapterCandidate(page: 0, title: 'Ch1', source: 'ocr', confidence: 'medium'),
        ]),
      ];
    final c = _containerWith(api);
    addTearDown(c.dispose);
    final ctrl = c.read(scanProvider.notifier);
    await ctrl.start(comicId: 'x', title: 'X');
    expect(c.read(scanProvider).phase, ScanPhase.running);

    await ctrl.pollOnce();
    expect(c.read(scanProvider).scanned, 100);
    expect(c.read(scanProvider).progress, closeTo(100 / 435, 0.001));

    await ctrl.pollOnce();
    expect(c.read(scanProvider).phase, ScanPhase.done);
    expect(c.read(scanProvider).candidates.single.title, 'Ch1');
  });

  test('unknown status → failed (interrupted)', () async {
    final api = _FakeApi()
      ..ocrPending = true
      ..script = [(state: 'unknown', scanned: 0, total: 0, candidates: const [])];
    final c = _containerWith(api);
    addTearDown(c.dispose);
    final ctrl = c.read(scanProvider.notifier);
    await ctrl.start(comicId: 'x', title: 'X');
    await ctrl.pollOnce();
    expect(c.read(scanProvider).phase, ScanPhase.failed);
  });

  test('409 on start → failed already-running', () async {
    final api = _FakeApi()..postError = ApiException(409, 'busy');
    final c = _containerWith(api);
    addTearDown(c.dispose);
    await c.read(scanProvider.notifier).start(comicId: 'x', title: 'X');
    final s = c.read(scanProvider);
    expect(s.phase, ScanPhase.failed);
    expect(s.error, contains('already running'));
  });

  test('steady progress never times out (past the old 240-poll cap)', () async {
    // scanned advances every poll → the stall watchdog keeps resetting.
    final api = _FakeApi()
      ..ocrPending = true
      ..progressGen = (call) => (call + 1) * 5;
    final c = _containerWith(api);
    addTearDown(c.dispose);
    final ctrl = c.read(scanProvider.notifier);
    await ctrl.start(comicId: 'x', title: 'X');
    for (var i = 0; i < 300; i++) {
      await ctrl.pollOnce();
    }
    expect(c.read(scanProvider).phase, ScanPhase.running);
    expect(c.read(scanProvider).scanned, greaterThan(1000));
  });

  test('stalled progress → failed after the watchdog window', () async {
    // scanned never advances past the first poll → stall watchdog fires.
    final api = _FakeApi()
      ..ocrPending = true
      ..progressGen = (call) => 50; // constant
    final c = _containerWith(api);
    addTearDown(c.dispose);
    final ctrl = c.read(scanProvider.notifier);
    await ctrl.start(comicId: 'x', title: 'X');
    for (var i = 0; i < 60; i++) {
      await ctrl.pollOnce();
    }
    final s = c.read(scanProvider);
    expect(s.phase, ScanPhase.failed);
    expect(s.error, contains('stalled'));
  });
}
