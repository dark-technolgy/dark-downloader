import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/incoming_link_provider.dart';

/// Local HTTP server to communicate with the browser extension.
/// Listens on http://localhost:3030
class BrowserBridgeService {
  final ProviderContainer _container;
  HttpServer? _server;

  BrowserBridgeService(this._container);

  Future<void> start() async {
    if (_server != null) return;

    try {
      _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 3030);
      debugPrint('BrowserBridge: Listening on http://localhost:3030');

      _server!.listen((HttpRequest request) async {
        // CORS Headers
        request.response.headers.add('Access-Control-Allow-Origin', '*');
        request.response.headers.add('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
        request.response.headers.add('Access-Control-Allow-Headers', 'Content-Type');

        if (request.method == 'OPTIONS') {
          request.response.statusCode = HttpStatus.ok;
          await request.response.close();
          return;
        }

        final path = request.uri.path;

        if (path == '/ping') {
          _handlePing(request);
        } else if (path == '/download' && request.method == 'POST') {
          await _handleDownload(request);
        } else if (path == '/sniff' && request.method == 'POST') {
          await _handleSniff(request);
        } else {
          request.response.statusCode = HttpStatus.notFound;
          await request.response.close();
        }
      });
    } catch (e) {
      debugPrint('BrowserBridge: Failed to start server: $e');
    }
  }

  void _handlePing(HttpRequest request) {
    request.response
      ..statusCode = HttpStatus.ok
      ..write(jsonEncode({'status': 'online', 'app': 'Dark Downloader'}))
      ..close();
  }

  Future<void> _handleDownload(HttpRequest request) async {
    try {
      final content = await utf8.decoder.bind(request).join();
      final data = jsonDecode(content) as Map<String, dynamic>;
      final url = data['url'] as String?;

      if (url != null && url.isNotEmpty) {
        debugPrint('BrowserBridge: Received download request for $url');
        _container.read(incomingRawLinkProvider.notifier).offer(url);

        request.response
          ..statusCode = HttpStatus.ok
          ..write(jsonEncode({'success': true}))
          ..close();
      } else {
        request.response
          ..statusCode = HttpStatus.badRequest
          ..write(jsonEncode({'error': 'URL missing'}))
          ..close();
      }
    } catch (e) {
      request.response
        ..statusCode = HttpStatus.internalServerError
        ..write(jsonEncode({'error': e.toString()}))
        ..close();
    }
  }

  Future<void> _handleSniff(HttpRequest request) async {
     try {
      final content = await utf8.decoder.bind(request).join();
      final data = jsonDecode(content) as Map<String, dynamic>;
      final url = data['url'] as String?;

      if (url != null && url.isNotEmpty) {
        debugPrint('BrowserBridge: Sniffed media at $url');
        // For now, we treat sniffs like direct download offers
        _container.read(incomingRawLinkProvider.notifier).offer(url);

        request.response
          ..statusCode = HttpStatus.ok
          ..write(jsonEncode({'success': true}))
          ..close();
      } else {
        request.response
          ..statusCode = HttpStatus.badRequest
          ..write(jsonEncode({'error': 'URL missing'}))
          ..close();
      }
    } catch (e) {
      request.response
        ..statusCode = HttpStatus.internalServerError
        ..write(jsonEncode({'error': e.toString()}))
        ..close();
    }
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
  }
}

final browserBridgeProvider = Provider<BrowserBridgeService>((ref) {
  throw UnimplementedError('Initialize this provider with ProviderContainer in main()');
});
