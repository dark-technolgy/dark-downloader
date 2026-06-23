import '../models/video_model.dart';
import '../providers/extractor_provider.dart';
import 'stream_utils.dart';

/// Picks the best audio-only stream to merge with [videoStream] (codec/container affinity).
StreamInfo? pickBestAudioCompanion(
  StreamInfo videoStream,
  List<StreamInfo> streams,
) {
  final audioStreams =
      streams.where((x) => x.kind == StreamKind.audioOnly).toList();
  if (audioStreams.isEmpty) return null;
  final videoFmt = (videoStream.container ?? videoStream.format).toLowerCase();

  StreamInfo? bestMatching;
  StreamInfo? bestAny;
  var bestMatchingBitrate = -1;
  var bestAnyBitrate = -1;

  for (final s in audioStreams) {
    final bitrate = s.bitrateKbps ?? 0;
    if (bitrate > bestAnyBitrate) {
      bestAnyBitrate = bitrate;
      bestAny = s;
    }
    final container = (s.container ?? s.format).toLowerCase();
    final sameContainer = (videoFmt == 'mp4' && container == 'm4a') ||
        (videoFmt == 'webm' && (container == 'webm' || container == 'opus'));
    if (sameContainer && bitrate > bestMatchingBitrate) {
      bestMatchingBitrate = bitrate;
      bestMatching = s;
    }
  }
  return bestMatching ?? bestAny;
}

bool _isYoutubeScope(String platform, String pageUrl) {
  final p = platform.toLowerCase();
  if (p.contains('youtube') || p.contains('youtu')) return true;
  final u = pageUrl.toLowerCase();
  return u.contains('youtube.com') || u.contains('youtu.be');
}

/// True when we should download a separate audio URL and mux (DASH-style).
///
/// Matches [AdvancedDownloadScreen] logic for «video + audio» mode.
/// Pass [allStreams] so YouTube can detect «separate audio exists → always mux».
bool needsAudioCompanion(
  StreamInfo s,
  String platform, {
  String pageUrl = '',
  List<StreamInfo>? allStreams,
}) {
  if (s.kind == StreamKind.audioOnly) return false;

  final isYt = _isYoutubeScope(platform, pageUrl);
  if (isYt && allStreams != null && pickBestAudioCompanion(s, allStreams) != null) {
    // DASH manifests list separate audio; many video rows are video-only or mis-tagged muxed.
    return true;
  }

  if (!s.hasAudio) return true;
  if (isYt) {
    final h = s.height ?? 0;
    // Without separate audio entries, still treat low rungs as suspicious (Piped / bad tags).
    return h == 0 || h >= 144;
  }
  return s.kind == StreamKind.videoOnly;
}

/// Highest-score muxed stream that already includes audio (progressive fallback).
///
/// [classify] sorts muxed by [StreamInfo.sortScore] descending.
StreamInfo? bestMuxedWithAudio(List<StreamInfo> streams) {
  for (final s in classifyStreams(streams).muxed) {
    if (s.hasAudio) return s;
  }
  return null;
}

/// Resolved primary stream + optional separate audio for the download engine.
class DownloadStreamPair {
  final StreamInfo primary;
  final StreamInfo? audioCompanion;

  const DownloadStreamPair({
    required this.primary,
    this.audioCompanion,
  });
}

/// Computes [DownloadStreamPair] for [addToQueue].
///
/// When [allowMuxedFallback] is true (batch / playlist), if a separate audio
/// track is required but missing, falls back to the best progressive muxed
/// stream that already contains audio.
DownloadStreamPair resolveDownloadStreams(
  VideoModel video,
  List<StreamInfo> streams, {
  StreamInfo? selected,
  bool allowMuxedFallback = false,
}) {
  if (streams.isEmpty) {
    throw ArgumentError.value(streams, 'streams', 'must not be empty');
  }
  var primary = selected ?? pickBestDefault(streams);
  primary ??= streams.first;

  if (primary.kind == StreamKind.audioOnly) {
    return DownloadStreamPair(primary: primary, audioCompanion: null);
  }

  if (!needsAudioCompanion(
    primary,
    video.platform,
    pageUrl: video.url,
    allStreams: streams,
  )) {
    return DownloadStreamPair(primary: primary, audioCompanion: null);
  }

  final audio = pickBestAudioCompanion(primary, streams);
  if (audio != null) {
    return DownloadStreamPair(primary: primary, audioCompanion: audio);
  }

  if (allowMuxedFallback) {
    final muxed = bestMuxedWithAudio(streams);
    if (muxed != null) {
      return DownloadStreamPair(primary: muxed, audioCompanion: null);
    }
  }

  return DownloadStreamPair(primary: primary, audioCompanion: null);
}
