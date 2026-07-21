import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../src/rust/api/extractor.dart' as rust_extractor;
import '../../src/rust/api/models.dart' as rust_models;
import '../models/video_model.dart';
import '../services/telemetry_service.dart';

enum ExtractStatus { initial, loading, success, error }

enum StreamKind { muxed, videoOnly, audioOnly }

class StreamInfo {
  final String url;
  final String quality;
  final String format;
  final BigInt? fileSizeBytes;
  final String? videoCodec;
  final String? audioCodec;
  final StreamKind kind;
  final int? bitrateKbps;
  final String? container;
  final int? width;
  final int? height;
  final double? fps;
  final bool isHdr;

  StreamInfo({
    required this.url,
    required this.quality,
    required this.format,
    this.fileSizeBytes,
    this.videoCodec,
    this.audioCodec,
    required this.kind,
    this.bitrateKbps,
    this.container,
    this.width,
    this.height,
    this.fps,
    this.isHdr = false,
  });

  bool get hasAudio => kind == StreamKind.muxed || kind == StreamKind.audioOnly;
  bool get hasVideo => kind == StreamKind.muxed || kind == StreamKind.videoOnly;
  bool get isAudioOnly => kind == StreamKind.audioOnly;
  bool get is8K => (height ?? 0) >= 4320;
  bool get is4K => (height ?? 0) >= 2160;

  String get codecLabel =>
      [videoCodec, audioCodec].where((c) => c != null).join(' + ');

  String get resolutionBucket {
    if (height == null) return 'SD';
    if (height! >= 4320) return '8K';
    if (height! >= 2160) return '4K';
    if (height! >= 1440) return '2K';
    if (height! >= 1080) return '1080p';
    if (height! >= 720) return '720p';
    if (height! >= 480) return '480p';
    if (height! >= 360) return '360p';
    return 'SD';
  }

  double get sortScore {
    double score = (height ?? 0).toDouble();
    if (kind == StreamKind.muxed) score += 1000;
    if (bitrateKbps != null) score += (bitrateKbps! / 1000.0);
    if (isHdr) score += 500;
    return score;
  }

  factory StreamInfo.fromRust(rust_models.StreamResult r) {
    StreamKind kind = StreamKind.videoOnly;
    if (r.isAudioOnly) kind = StreamKind.audioOnly;
    if (r.hasVideo && r.hasAudio) kind = StreamKind.muxed;

    return StreamInfo(
      url: r.url,
      quality: r.quality,
      format: r.format,
      fileSizeBytes: r.fileSizeBytes,
      videoCodec: r.videoCodec,
      audioCodec: r.audioCodec,
      kind: kind,
      bitrateKbps: r.bitrateKbps,
      container: r.container,
      width: r.width,
      height: r.height,
      fps: r.fps,
      isHdr: r.isHdr,
    );
  }
}

class ExtractorState {
  final ExtractStatus status;
  final VideoModel? video;
  final List<StreamInfo> streams;
  final String? errorMessage;
  final rust_models.PlaylistResult? playlist; 

  ExtractorState({
    this.status = ExtractStatus.initial,
    this.video,
    this.streams = const [],
    this.errorMessage,
    this.playlist,
  });

  bool get isLoading => status == ExtractStatus.loading;

  ExtractorState copyWith({
    ExtractStatus? status,
    VideoModel? video,
    List<StreamInfo>? streams,
    String? errorMessage,
    rust_models.PlaylistResult? playlist,
  }) {
    return ExtractorState(
      status: status ?? this.status,
      video: video ?? this.video,
      streams: streams ?? this.streams,
      errorMessage: errorMessage ?? this.errorMessage,
      playlist: playlist ?? this.playlist,
    );
  }
}

class ExtractorNotifier extends Notifier<ExtractorState> {
  @override
  ExtractorState build() => ExtractorState();

  Future<void> extractVideo(String url, {bool bypassBlocks = false}) async {
    state = state.copyWith(status: ExtractStatus.loading, errorMessage: null);

    String cleanUrl = url.trim();
    
    // 1. الذكاء الاصطناعي البسيط: إذا لم يكن الرابط يبدأ بـ http، وكان مجرد كلمات، نقوم بالبحث في يوتيوب
    if (!cleanUrl.startsWith('http://') && !cleanUrl.startsWith('https://')) {
      if (cleanUrl.contains('.') && !cleanUrl.contains(' ')) {
        // مثلاً: youtube.com
        cleanUrl = 'https://$cleanUrl';
      } else {
        // كلمات بحث عادية مثل "pornhub" أو "maroon 5" -> يجلب أول نتيجة فيديو من يوتيوب
        cleanUrl = 'ytsearch1:$cleanUrl';
      }
    }

    // 2. معالجة روابط يوتيوب التي تحتوي على قائمة وفيديو معاً
    try {
      if (cleanUrl.startsWith('http')) {
        final uri = Uri.parse(cleanUrl);
        if (uri.host.contains('youtube.com') || uri.host.contains('youtu.be')) {
          // إذا كان الرابط يحتوي على (v) و (list) معاً، المستخدم عادة يريد الفيديو فقط
          // لكن لنجعله أذكى: سنتركه كما هو ليتعرف عليه yt-dlp كـ قائمة، أو نحذف الـ list إذا أردنا الفيديو فقط.
          // سنترك الـ yt-dlp يتعامل معه بذكاء (لأنه قد يجلب القائمة كاملة).
          // إذا كان فقط فيديو بدون قائمة لن يتأثر.
        }
      }
    } catch (_) {}

    await timeAsync('video_extraction', () async {
      try {
        final result = await rust_extractor.extract(url: cleanUrl);
        
        result.when(
          video: (v) {
            state = state.copyWith(
              status: ExtractStatus.success,
              video: VideoModel(
                id: url.hashCode.toString(), // Generating ID from URL as placeholder
                title: v.title,
                url: url,
                platform: v.platform,
                createdAt: DateTime.now(),
                quality: 'Best',
                thumbnailUrl: v.thumbnailUrl,
                description: null, // description missing in rust VideoInfoResult
                duration: v.durationSeconds,
              ),
              streams: v.streams.map((s) => StreamInfo.fromRust(s)).toList(),
              playlist: null,
            );
          },
          playlist: (p) {
            state = state.copyWith(
              status: ExtractStatus.success,
              playlist: p,
              video: null,
              streams: [],
            );
          },
        );
      } catch (e) {
        state = state.copyWith(status: ExtractStatus.error, errorMessage: e.toString());
        Telemetry.instance.recordError('extractor', e);
      }
    });
  }
}

final extractorProvider = NotifierProvider<ExtractorNotifier, ExtractorState>(ExtractorNotifier.new);
