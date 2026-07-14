import 'package:flutter/material.dart' show Locale;

import '../config/localization.dart';
import '../providers/extractor_provider.dart';

const List<String> kResolutionOrder = <String>[
  '4K',
  '2K',
  '1080p',
  '720p',
  '480p',
  '360p',
  'SD',
];

const List<String> kContainerOrder = <String>[
  'MP4',
  'WEBM',
  'M4A',
  'MP3',
  'OPUS',
  'AAC',
  '3GP',
];

class StreamClassification {
  const StreamClassification({
    required this.muxed,
    required this.videoOnly,
    required this.audioOnly,
  });

  final List<StreamInfo> muxed;
  final List<StreamInfo> videoOnly;
  final List<StreamInfo> audioOnly;
}

StreamClassification classifyStreams(List<StreamInfo> streams) {
  final muxed = <StreamInfo>[];
  final videoOnly = <StreamInfo>[];
  final audioOnly = <StreamInfo>[];

  for (final s in streams) {
    switch (s.kind) {
      case StreamKind.muxed:
        muxed.add(s);
        break;
      case StreamKind.videoOnly:
        videoOnly.add(s);
        break;
      case StreamKind.audioOnly:
        audioOnly.add(s);
        break;
    }
  }

  muxed.sort((a, b) => b.sortScore.compareTo(a.sortScore));
  videoOnly.sort((a, b) => b.sortScore.compareTo(a.sortScore));
  audioOnly.sort((a, b) => b.sortScore.compareTo(a.sortScore));

  return StreamClassification(
    muxed: muxed,
    videoOnly: videoOnly,
    audioOnly: audioOnly,
  );
}

List<String> availableResolutions(List<StreamInfo> streams) {
  final present = <String>{};
  for (final s in streams) {
    if (s.kind == StreamKind.audioOnly) continue;
    present.add(s.resolutionBucket);
  }
  final result = <String>[];
  for (final r in kResolutionOrder) {
    if (present.contains(r)) result.add(r);
  }
  for (final extra in present) {
    if (!kResolutionOrder.contains(extra)) result.add(extra);
  }
  return result;
}

List<String> availableContainers(List<StreamInfo> streams) {
  final present = <String>{};
  for (final s in streams) {
    if (s.container != null) present.add(s.container!.toUpperCase());
  }
  final result = <String>[];
  for (final c in kContainerOrder) {
    if (present.contains(c)) result.add(c);
  }
  for (final extra in present) {
    if (!kContainerOrder.contains(extra)) result.add(extra);
  }
  return result;
}

List<StreamInfo> applyFilters(
  List<StreamInfo> streams, {
  Set<StreamKind>? kinds,
  Set<String>? resolutions,
  Set<String>? containers,
}) {
  return streams.where((s) {
    if (kinds != null && !kinds.contains(s.kind)) return false;
    if (resolutions != null && resolutions.isNotEmpty && !resolutions.contains(s.resolutionBucket)) return false;
    if (containers != null && containers.isNotEmpty && s.container != null && !containers.contains(s.container!.toUpperCase())) return false;
    return true;
  }).toList();
}

StreamInfo? pickBestDefault(List<StreamInfo> streams) {
  if (streams.isEmpty) return null;
  final c = classifyStreams(streams);

  final muxed1080 = c.muxed.firstWhere(
    (s) => s.resolutionBucket == '1080p',
    orElse: () => streams.first,
  );
  if (muxed1080.resolutionBucket == '1080p') return muxed1080;

  if (c.muxed.isNotEmpty) return c.muxed.first;
  if (c.videoOnly.isNotEmpty) return c.videoOnly.first;
  if (c.audioOnly.isNotEmpty) return c.audioOnly.first;
  return streams.first;
}

String localizedCodecLabel(StreamInfo stream, Locale locale) {
  final raw = stream.codecLabel;
  const t = AppLocalization.translate;
  if (raw == 'Audio') return t('stream_codec_audio', locale);
  if (raw == 'Video') return t('stream_codec_video', locale);
  if (raw.isEmpty || raw == '—') return t('stream_codec_unknown', locale);
  return raw;
}

String localizedBitrateKbps(int kbps, Locale locale) =>
    AppLocalization.translate('stream_bitrate_kbps', locale)
        .replaceAll('{n}', kbps.toString());

String localizedStreamTitleLine(StreamInfo stream, Locale locale) {
  if (stream.kind == StreamKind.audioOnly) {
    final format = stream.container?.toUpperCase() ?? 'AUDIO';
    final base = AppLocalization.translate('kind_audio_only', locale).split(' ').first;
    return '$base ($format)';
  }
  return stream.quality;
}
