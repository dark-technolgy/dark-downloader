import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../config/breakpoints.dart';
import '../../config/localization.dart';
import '../../models/video_model.dart';
import '../../providers/download_manager_provider.dart';
import '../../providers/extractor_provider.dart';
import '../../providers/locale_provider.dart';
import '../../utils/download_streams_resolver.dart';
import '../../utils/stream_utils.dart';
import '../widgets/filter_chip_row.dart';
import '../widgets/responsive_scaffold.dart';
import '../widgets/selected_stream_header.dart';
import '../widgets/stream_tile.dart';

class AdvancedDownloadScreen extends ConsumerStatefulWidget {
  final VideoModel video;
  final List<StreamInfo> streams;

  const AdvancedDownloadScreen({
    required this.video,
    this.streams = const [],
    super.key,
  });

  @override
  ConsumerState<AdvancedDownloadScreen> createState() =>
      _AdvancedDownloadScreenState();
}

class _AdvancedDownloadScreenState
    extends ConsumerState<AdvancedDownloadScreen> {
  StreamInfo? _selected;

  _StreamKindFilter _streamKindFilter = _StreamKindFilter.videoWithAudio;
  String _resolutionFilter = '';
  String _containerFilter = '';

  int _connections = 8;
  String _audioFormat = 'm4a';
  DateTime? _scheduledAt;

  @override
  void initState() {
    super.initState();
    _selected = pickBestDefault(widget.streams);
  }

  List<StreamInfo> get _filteredStreams => applyFilters(
        widget.streams,
        kinds: _streamKindFilter.kinds,
        resolutions: _resolutionFilter.isEmpty
            ? const {}
            : {_resolutionFilter},
        containers: _containerFilter.isEmpty
            ? const {}
            : {_containerFilter},
      );

  void _setStreamKindFilter(_StreamKindFilter f) {
    setState(() {
      _streamKindFilter = f;
      if (f == _StreamKindFilter.audioOnly) _resolutionFilter = '';
      _repickIfNeeded();
    });
  }

  void _setResolution(String r) {
    setState(() {
      _resolutionFilter = r;
      _repickIfNeeded();
    });
  }

  void _setContainer(String c) {
    setState(() {
      _containerFilter = c;
      _repickIfNeeded();
    });
  }

  void _repickIfNeeded() {
    final visible = _filteredStreams;
    if (_selected == null || !visible.contains(_selected)) {
      _selected = pickBestDefault(visible) ?? _selected;
    }
  }

  bool get _needsAudioMerge {
    final s = _selected;
    if (s == null) return false;
    if (_streamKindFilter == _StreamKindFilter.audioOnly ||
        s.kind == StreamKind.audioOnly) {
      return false;
    }
    return needsAudioCompanion(
      s,
      widget.video.platform,
      pageUrl: widget.video.url,
      allStreams: widget.streams,
    );
  }

  StreamInfo? get _bestAudioForMerge =>
      _selected == null ? null : pickBestAudioCompanion(_selected!, widget.streams);

  @override
  Widget build(BuildContext context) {
    final locale = ref.watch(localeProvider);
    final t = AppLocalization.translate;

    return Scaffold(
      appBar: AppBar(title: Text(t('download_options', locale))),
      body: SafeArea(
        child: ReadableWidthContainer(
          padding: context.pageInsets,
          child: ResponsiveTwoColumn(
            primary: _buildHeaderColumn(locale, t),
            secondary: _buildListColumn(locale, t),
          ),
        ),
      ),
    );
  }

  Widget _buildHeaderColumn(Locale locale, String Function(String, Locale) t) {
    final filtered = _filteredStreams;
    final resolutions = availableResolutions(widget.streams);
    final containers = availableContainers(widget.streams);
    final kindIsAudio = _streamKindFilter == _StreamKindFilter.audioOnly;

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
        SelectedStreamHeader(
          stream: _selected,
          locale: locale,
          thumbnailUrl: widget.video.thumbnailUrl,
          title: widget.video.title,
          selectedLabel: t('selected_quality', locale),
          downloadLabel: t('start_download', locale),
          onDownload: filtered.isEmpty ? null : _startDownload,
        ),
        const SizedBox(height: 16),
        FilterChipRow(
          title: t('filter_kind', locale),
          options: const ['video_with_audio', 'audio_only'],
          value: switch (_streamKindFilter) {
            _StreamKindFilter.all => '',
            _StreamKindFilter.videoWithAudio => 'video_with_audio',
            _StreamKindFilter.audioOnly => 'audio_only',
          },
          allLabel: t('filter_all', locale),
          labelFor: (o) => switch (o) {
            'video_with_audio' => t('filter_video_with_audio', locale),
            'audio_only' => t('kind_audio_only', locale),
            _ => o,
          },
          onChanged: (v) => _setStreamKindFilter(switch (v) {
            '' => _StreamKindFilter.all,
            'video_with_audio' => _StreamKindFilter.videoWithAudio,
            'audio_only' => _StreamKindFilter.audioOnly,
            _ => _StreamKindFilter.all,
          }),
        ),
        const SizedBox(height: 14),
        if (!kindIsAudio)
          FilterChipRow(
            title: t('filter_resolution', locale),
            options: resolutions,
            value: _resolutionFilter,
            allLabel: t('filter_all', locale),
            onChanged: _setResolution,
          ),
        if (!kindIsAudio) const SizedBox(height: 14),
        FilterChipRow(
          title: t('filter_format', locale),
          options: containers,
          value: _containerFilter,
          allLabel: t('filter_all', locale),
          onChanged: _setContainer,
        ),
        const SizedBox(height: 16),

        _buildSchedulingSettings(locale),
        _buildAdvancedSettings(locale),
        ],
      ),
    );
  }

  Widget _buildSchedulingSettings(Locale locale) {
    final t = AppLocalization.translate;

    return ExpansionTile(
      title: Text(
        t('dm_schedule_section_title', locale),
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
      ),
      leading: const Icon(Icons.schedule_rounded, size: 18, color: Colors.orange),
      subtitle: Text(
        _scheduledAt == null
            ? t('dm_schedule_subtitle_now', locale)
            : t('dm_schedule_subtitle_at', locale).replaceAll('{time}', DateFormat.Hm(locale.languageCode).format(_scheduledAt!)),
        style: TextStyle(fontSize: 11, color: _scheduledAt == null ? Colors.grey : Colors.orange),
      ),
      tilePadding: EdgeInsets.zero,
      childrenPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
      children: [
        ListTile(
          title: Text(t('dm_schedule_toggle', locale), style: const TextStyle(fontSize: 13)),
          trailing: Switch(
            value: _scheduledAt != null,
            onChanged: (v) async {
              if (v) {
                final time = await showTimePicker(
                  context: context,
                  initialTime: const TimeOfDay(hour: 2, minute: 0),
                  helpText: t('dm_schedule_picker_help', locale),
                );
                if (time != null) {
                  final now = DateTime.now();
                  var scheduled = DateTime(now.year, now.month, now.day, time.hour, time.minute);
                  if (scheduled.isBefore(now)) {
                    scheduled = scheduled.add(const Duration(days: 1));
                  }
                  setState(() => _scheduledAt = scheduled);
                }
              } else {
                setState(() => _scheduledAt = null);
              }
            },
          ),
        ),
      ],
    );
  }

  Widget _buildAdvancedSettings(Locale locale) {
    final t = AppLocalization.translate;
    final isAudio = _streamKindFilter == _StreamKindFilter.audioOnly ||
        _selected?.kind == StreamKind.audioOnly;
    final colorScheme = Theme.of(context).colorScheme;

    return ExpansionTile(
      title: Text(
        t('adv_settings_title', locale),
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
      ),
      leading: Icon(Icons.tune_rounded, size: 18, color: colorScheme.primary),
      tilePadding: EdgeInsets.zero,
      childrenPadding:
          const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
      children: [
        Row(
          children: [
            Icon(Icons.speed_rounded, size: 18, color: Colors.grey.shade600),
            const SizedBox(width: 10),
            Text(t('adv_parallel_connections', locale),
                style: const TextStyle(fontSize: 13)),
            const Spacer(),
            DropdownButton<int>(
              value: _connections,
              items: const [1, 2, 4, 6, 8, 12, 16]
                  .map((n) => DropdownMenuItem(value: n, child: Text('$n')))
                  .toList(),
              onChanged: (v) => setState(() => _connections = v ?? 8),
              isDense: true,
            ),
          ],
        ),
        if (isAudio) ...[
          const SizedBox(height: 14),
          Row(
            children: [
              Icon(Icons.audio_file_rounded,
                  size: 18, color: Colors.grey.shade600),
              const SizedBox(width: 10),
              Text(
                t('adv_audio_format', locale),
                style: const TextStyle(fontSize: 13),
              ),
              const Spacer(),
              DropdownButton<String>(
                value: _audioFormat,
                items: [
                  DropdownMenuItem(
                    value: 'm4a',
                    child: Text(t('adv_codec_m4a', locale)),
                  ),
                  DropdownMenuItem(
                    value: 'mp3',
                    child: Text(t('adv_codec_mp3', locale)),
                  ),
                  DropdownMenuItem(
                    value: 'opus',
                    child: Text(t('adv_codec_opus', locale)),
                  ),
                  DropdownMenuItem(
                    value: 'wav',
                    child: Text(t('adv_codec_wav', locale)),
                  ),
                  DropdownMenuItem(
                    value: 'flac',
                    child: Text(t('adv_codec_flac', locale)),
                  ),
                ],
                onChanged: (v) =>
                    setState(() => _audioFormat = v ?? 'm4a'),
                isDense: true,
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildListColumn(Locale locale, String Function(String, Locale) t) {
    final filtered = _filteredStreams;
    final theme = Theme.of(context);

    if (filtered.isEmpty) {
      return Container(
        height: 240,
        alignment: Alignment.center,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.filter_list_off_rounded,
                size: 40, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(height: 12),
            Text(
              t('no_streams_for_filter', locale),
              style: theme.textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    if (context.isMobile) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final s in filtered) ...[
            StreamTile(
              stream: s,
              locale: locale,
              selected: s == _selected,
              onSelected: () => setState(() => _selected = s),
            ),
            const SizedBox(height: 8),
          ],
        ],
      );
    }

    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 640, minHeight: 320),
      child: ListView.separated(
        shrinkWrap: true,
        itemCount: filtered.length,
        separatorBuilder: (_, _) => const SizedBox(height: 8),
        itemBuilder: (ctx, i) {
          final s = filtered[i];
          return StreamTile(
            stream: s,
            locale: locale,
            selected: s == _selected,
            onSelected: () => setState(() => _selected = s),
          );
        },
      ),
    );
  }


  Future<void> _startDownload() async {
    final locale = ref.read(localeProvider);
    final t = AppLocalization.translate;
    final stream = _selected;
    if (stream == null) return;

    if (stream.kind != StreamKind.audioOnly && _needsAudioMerge) {
      if (_bestAudioForMerge == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(t('merge_missing_audio', locale)),
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }
    }

    final StreamInfo? audio = stream.kind == StreamKind.audioOnly
        ? null
        : (_needsAudioMerge ? _bestAudioForMerge : null);

    await ref.read(downloadManagerProvider.notifier).addToQueue(
          widget.video,
          stream: stream,
          audioStream: audio,
          connections: _connections,
          scheduledAt: _scheduledAt,
          audioOutputFormat:
              stream.kind == StreamKind.audioOnly ? _audioFormat : null,
        );

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle_rounded,
                color: Colors.white, size: 18),
            const SizedBox(width: 10),
            Text(t('added_to_queue', locale)),
          ],
        ),
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10)),
      ),
    );
    Navigator.pop(context);
  }
}

enum _StreamKindFilter {
  all,
  videoWithAudio,
  audioOnly;

  Set<StreamKind>? get kinds => switch (this) {
        all => null,
        videoWithAudio => {StreamKind.muxed, StreamKind.videoOnly},
        audioOnly => {StreamKind.audioOnly},
      };
}
