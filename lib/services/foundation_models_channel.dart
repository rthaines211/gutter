import 'dart:async';
import 'package:flutter/services.dart';

class ModelUnavailable implements Exception {
  final String message;
  ModelUnavailable(this.message);
  @override
  String toString() => 'ModelUnavailable: $message';
}

class ModelTimeout implements Exception {
  @override
  String toString() => 'ModelTimeout';
}

class ModelDecodingError implements Exception {
  final String message;
  ModelDecodingError(this.message);
  @override
  String toString() => 'ModelDecodingError: $message';
}

class ModelGenerationError implements Exception {
  final String code;
  final String message;
  ModelGenerationError(this.code, this.message);
  @override
  String toString() => 'ModelGenerationError($code): $message';
}

class FoundationModelsChannel {
  static const MethodChannel _channel =
      MethodChannel('app.comic_reader/ai_recs');
  final Duration timeout;

  FoundationModelsChannel({this.timeout = const Duration(seconds: 60)});

  Future<bool> isAvailable() async {
    try {
      final result = await _channel.invokeMethod<bool>('isAvailable');
      return result ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  Future<void> prewarm() async {
    try {
      await _channel.invokeMethod<void>('prewarm');
    } on PlatformException {
      // Best-effort; failure here just means the first recommend() pays
      // the cold-start cost.
    } on MissingPluginException {
      // ignore
    }
  }

  Future<Map<String, dynamic>> recommend(
      Map<String, dynamic> context) async {
    try {
      final raw = await _channel
          .invokeMethod<Map<dynamic, dynamic>>('recommend', context)
          .timeout(timeout);
      if (raw == null) {
        throw ModelDecodingError('null result from native');
      }
      return raw.map((k, v) => MapEntry(k.toString(), v));
    } on TimeoutException {
      throw ModelTimeout();
    } on PlatformException catch (e) {
      switch (e.code) {
        case 'MODEL_UNAVAILABLE':
          throw ModelUnavailable(e.message ?? '');
        case 'DECODING_FAILURE':
          throw ModelDecodingError(e.message ?? '');
        default:
          throw ModelGenerationError(e.code, e.message ?? '');
      }
    }
  }
}
