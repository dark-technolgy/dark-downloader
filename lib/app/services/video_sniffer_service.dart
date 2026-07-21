import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

/// Detected video entry from network interception or JS injection.
class SniffedVideo {
  final String url;
  final String? mimeType;
  final DateTime detectedAt;

  SniffedVideo({
    required this.url,
    this.mimeType,
    DateTime? detectedAt,
  }) : detectedAt = detectedAt ?? DateTime.now();

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SniffedVideo && url == other.url;

  @override
  int get hashCode => url.hashCode;
}

class VideoSnifferService {
  static final VideoSnifferService _instance = VideoSnifferService._internal();
  factory VideoSnifferService() => _instance;
  VideoSnifferService._internal();

  static const _videoExtensions = [
    '.m3u8',
    '.mpd',
    '.mp4',
    '.webm',
    '.mkv',
    '.flv',
    '.vob',
    '.ogg',
    '.ogv',
    '.avi',
    '.mov',
    '.wmv',
    '.m4v',
    '.f4v',
  ];

  static const _videoMimePatterns = [
    'video/mp4',
    'video/webm',
    'video/x-flv',
    'video/x-matroska',
    'application/x-mpegurl',
    'application/vnd.apple.mpegurl',
    'application/dash+xml',
  ];

  static const _videoUrlPatterns = [
    '/manifest/dash/',
    '/hls/manifest/',
    'mime=video',
    '/progressive/',
  ];

  /// Patterns to exclude (ads, tracking, tiny segments)
  static const _excludePatterns = [
    'googlesyndication',
    'doubleclick.net',
    'googleadservices',
    'analytics',
    'googlevideo.com', // YouTube chunks
    'videoplayback', // YouTube chunks
    'itag=', // YouTube chunks
    'segment', // HLS/DASH chunk
    'frag', // chunk
    'chunk', // chunk
    '.ts', // chunk
    '.m4s', // chunk
    '.gif',
    '.png',
    '.jpg',
    '.jpeg',
    '.svg',
    '.css',
    '.js',
    'favicon',
  ];

  /// All sniffed videos for the current page (deduplicated by URL).
  final ValueNotifier<List<SniffedVideo>> sniffedVideos = ValueNotifier([]);

  /// Legacy single-video notifier for backward compatibility.
  final ValueNotifier<String?> sniffedVideoUrl = ValueNotifier(null);

  /// Clear all sniffed videos (call on page navigation).
  void clearSniffedVideos() {
    sniffedVideos.value = [];
    sniffedVideoUrl.value = null;
  }

  /// @deprecated Use [clearSniffedVideos] instead.
  void clearSniffedVideo() => clearSniffedVideos();

  /// Analyze a network request URL for video content.
  void analyzeRequest(String url, {String? contentType}) {
    if (url.isEmpty || url.length < 10) return;

    final lowerUrl = url.toLowerCase();

    // Skip excluded patterns (ads, images, etc.)
    if (_excludePatterns.any((p) => lowerUrl.contains(p))) return;

    bool isVideo = false;
    String? detectedMime;

    // 1. Check explicit video extensions
    if (_videoExtensions.any((ext) => lowerUrl.contains(ext))) {
      isVideo = true;
    }

    // 2. Check MIME type from Content-Type header
    if (!isVideo && contentType != null) {
      final lowerMime = contentType.toLowerCase();
      if (_videoMimePatterns.any((m) => lowerMime.contains(m))) {
        isVideo = true;
        detectedMime = contentType;
      }
    }

    // 3. Check URL patterns specific to video platforms
    if (!isVideo && _videoUrlPatterns.any((p) => lowerUrl.contains(p))) {
      isVideo = true;
    }

    if (isVideo) {
      final video = SniffedVideo(url: url, mimeType: detectedMime);

      // Deduplicate
      final current = List<SniffedVideo>.from(sniffedVideos.value);
      if (!current.any((v) => v.url == url)) {
        current.add(video);
        sniffedVideos.value = current;
        // Keep legacy notifier pointing to the latest
        sniffedVideoUrl.value = url;
        debugPrint('🎥 [Sniffer] Video #${current.length}: $url');
      }
    }
  }

  /// InAppWebView interceptor — analyzes each network request.
  Future<WebResourceResponse?> shouldInterceptRequest(
    WebResourceRequest request,
  ) async {
    final url = request.url.toString();
    // Try to get content type from request headers
    final contentType = request.headers?['Content-Type'] ??
        request.headers?['content-type'];
    analyzeRequest(url, contentType: contentType);
    return null; // Let the request continue normally
  }
}
