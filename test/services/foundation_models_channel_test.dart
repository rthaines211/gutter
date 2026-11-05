import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:comic_reader_app/services/foundation_models_channel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('app.comic_reader/ai_recs');
  final messenger = TestDefaultBinaryMessengerBinding
      .instance.defaultBinaryMessenger;

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
  });

  group('FoundationModelsChannel', () {
    test('isAvailable returns true when native says available', () async {
      messenger.setMockMethodCallHandler(channel, (call) async {
        expect(call.method, 'isAvailable');
        return true;
      });
      final result = await FoundationModelsChannel().isAvailable();
      expect(result, true);
    });

    test('prewarm invokes the native prewarm method', () async {
      var called = false;
      messenger.setMockMethodCallHandler(channel, (call) async {
        expect(call.method, 'prewarm');
        called = true;
        return null;
      });
      await FoundationModelsChannel().prewarm();
      expect(called, true);
    });

    test('prewarm swallows PlatformException', () async {
      messenger.setMockMethodCallHandler(channel, (call) async {
        throw PlatformException(code: 'BAD', message: 'whoops');
      });
      await FoundationModelsChannel().prewarm();
    });

    test('recommend returns the parsed Map', () async {
      messenger.setMockMethodCallHandler(channel, (call) async {
        expect(call.method, 'recommend');
        expect(call.arguments, isA<Map>());
        return {
          'series_id': 'abc',
          'title': 'Saga',
          'creator': 'BKV',
          'reasoning': 'You binge BKV.',
        };
      });
      final result = await FoundationModelsChannel()
          .recommend(const {'top_genres': ['Sci-Fi']});
      expect(result['title'], 'Saga');
    });

    test('recommend maps MODEL_UNAVAILABLE to ModelUnavailable', () async {
      messenger.setMockMethodCallHandler(channel, (call) async {
        throw PlatformException(
            code: 'MODEL_UNAVAILABLE', message: 'not eligible');
      });
      expect(
        () => FoundationModelsChannel().recommend(const {}),
        throwsA(isA<ModelUnavailable>()),
      );
    });

    test('recommend maps DECODING_FAILURE to ModelDecodingError', () async {
      messenger.setMockMethodCallHandler(channel, (call) async {
        throw PlatformException(
            code: 'DECODING_FAILURE', message: 'bad output');
      });
      expect(
        () => FoundationModelsChannel().recommend(const {}),
        throwsA(isA<ModelDecodingError>()),
      );
    });

    test('recommend times out after the configured duration', () async {
      messenger.setMockMethodCallHandler(channel, (call) async {
        await Future<void>.delayed(const Duration(seconds: 2));
        return {};
      });
      expect(
        () => FoundationModelsChannel(
                timeout: const Duration(milliseconds: 100))
            .recommend(const {}),
        throwsA(isA<ModelTimeout>()),
      );
    });

    test('isAvailable returns false on MissingPluginException', () async {
      messenger.setMockMethodCallHandler(channel, (call) async {
        throw MissingPluginException('no plugin');
      });
      final result = await FoundationModelsChannel().isAvailable();
      expect(result, false);
    });

    test('recommend maps unknown error code to ModelGenerationError', () async {
      messenger.setMockMethodCallHandler(channel, (call) async {
        throw PlatformException(code: 'NETWORK_ERROR', message: 'oops');
      });
      expect(
        () => FoundationModelsChannel().recommend(const {}),
        throwsA(isA<ModelGenerationError>()),
      );
    });
  });
}
