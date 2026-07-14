import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

class Telemetry {
  static final Telemetry instance = Telemetry._();
  Telemetry._();

  Map<String, String>? _tags;
  String? _ingestUrl;
  String? _ingestToken;
  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 5),
    receiveTimeout: const Duration(seconds: 5),
  ),);

  /// Queue for offline buffering (send when possible)
  final List<Map<String, dynamic>> _pendingQueue = [];
  static const _maxQueueSize = 50;

  Future<void> init({
    Map<String, String>? tags,
    String? ingestUrl,
    String? ingestToken,
  }) async {
    _tags = tags;
    _ingestUrl = ingestUrl;
    _ingestToken = ingestToken;
    debugPrint('Telemetry initialized with URL: $_ingestUrl');
  }

  void recordError(String category, Object error, {StackTrace? stackTrace, Map<String, String>? context}) {
    debugPrint('[$category] Error: $error');
    if (stackTrace != null && kDebugMode) debugPrint(stackTrace.toString());
    
    // Send to Sentry if initialized
    if (Sentry.isEnabled) {
      Sentry.captureException(
        error,
        stackTrace: stackTrace,
        withScope: (scope) {
          scope.setTag('category', category);
          if (context != null) {
            scope.setContexts('custom_context', context);
          }
        },
      );
    }

    _enqueue({
      'type': 'error',
      'category': category,
      'error': error.toString(),
      'stackTrace': stackTrace != null ? (stackTrace.toString().length > 2000 ? stackTrace.toString().substring(0, 2000) : stackTrace.toString()) : null, // Truncate to save bandwidth
      'context': context,
      'tags': _tags,
      'timestamp': DateTime.now().toUtc().toIso8601String(),
    });
  }

  void recordEvent(String name, {Map<String, String>? properties}) {
    debugPrint('[Event] $name: $properties');
    _enqueue({
      'type': 'event',
      'event': name,
      'properties': properties,
      'tags': _tags,
      'timestamp': DateTime.now().toUtc().toIso8601String(),
    });
  }

  void recordTiming(String name, int ms, {Map<String, String>? properties}) {
    debugPrint('[Timing] $name: ${ms}ms');
    _enqueue({
      'type': 'timing',
      'timing': name,
      'value': ms,
      'properties': properties,
      'tags': _tags,
      'timestamp': DateTime.now().toUtc().toIso8601String(),
    });
  }

  void _enqueue(Map<String, dynamic> data) {
    if (_ingestUrl == null || _ingestToken == null) {
      // Buffer locally when no endpoint configured
      if (_pendingQueue.length < _maxQueueSize) {
        _pendingQueue.add(data);
      }
      return;
    }
    _sendToServer(data);
  }

  Future<void> _sendToServer(Map<String, dynamic> data) async {
    if (_ingestUrl == null || _ingestUrl!.isEmpty) return;
    
    try {
      await _dio.post(
        _ingestUrl!,
        data: jsonEncode(data),
        options: Options(
          headers: {
            'Content-Type': 'application/json',
            if (_ingestToken != null) 'Authorization': 'Bearer $_ingestToken',
          },
        ),
      );
    } catch (e) {
      // Telemetry failures should never crash the app
      if (kDebugMode) debugPrint('Telemetry send failed: $e');
    }
  }

  /// Flush pending events (call when endpoint becomes available)
  Future<void> flush() async {
    if (_ingestUrl == null || _ingestToken == null) return;
    
    final batch = List<Map<String, dynamic>>.from(_pendingQueue);
    _pendingQueue.clear();
    
    for (final data in batch) {
      await _sendToServer(data);
    }
  }

  Future<void> setupSentry(String dsn) async {
    if (dsn.isEmpty || Sentry.isEnabled) return;
    try {
      await SentryFlutter.init(
        (options) {
          options.dsn = dsn;
          options.tracesSampleRate = 1.0;
        },
        appRunner: null,
      );
      debugPrint('Sentry initialized successfully from RemoteConfig!');
    } catch (e) {
      debugPrint('Failed to initialize Sentry: $e');
    }
  }
}

Future<T> timeAsync<T>(String name, Future<T> Function() fn, {Map<String, String>? properties}) async {
  final sw = Stopwatch()..start();
  try {
    return await fn();
  } finally {
    Telemetry.instance.recordTiming(name, sw.elapsedMilliseconds, properties: properties);
  }
}
