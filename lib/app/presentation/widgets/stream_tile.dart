import 'package:flutter/material.dart';

import '../../config/localization.dart';
import '../../providers/extractor_provider.dart';
import '../../utils/stream_utils.dart';

/// Single selectable row inside the quality list.
/// Shows: kind icon • resolution/quality • codec • container • bitrate • size
/// with a trailing radio indicator.
class StreamTile extends StatelessWidget {
  const StreamTile({
    super.key,
    required this.stream,
    required this.selected,
    required this.onSelected,
    required this.locale,
  });

  final StreamInfo stream;
  final bool selected;
  final VoidCallback onSelected;
  final Locale locale;

  IconData get _kindIcon {
    switch (stream.kind) {
      case StreamKind.audioOnly:
        return Icons.music_note_rounded;
      case StreamKind.videoOnly:
        return Icons.movie_filter_rounded;
      case StreamKind.muxed:
        return Icons.hd_rounded;
    }
  }

  String _subtitleLine() {
    final parts = <String>[];
    parts.add(localizedCodecLabel(stream, locale));
    final container = stream.container?.toUpperCase() ?? stream.format;
    if (container.isNotEmpty) parts.add(container);
    if (stream.bitrateKbps != null && stream.kind != StreamKind.audioOnly) {
      parts.add(localizedBitrateKbps(stream.bitrateKbps!, locale));
    }
    if (stream.fileSizeBytes != null && stream.fileSizeBytes! > BigInt.zero) {
      parts.add(_formatBytes(stream.fileSizeBytes!));
    }
    final dash = AppLocalization.translate('stream_codec_unknown', locale);
    return parts
        .where((p) => p.isNotEmpty && p != '—' && p != dash)
        .join('  •  ');
  }

  String get _titleLine => localizedStreamTitleLine(stream, locale);

  String _formatBytes(BigInt bytes) {
    final b = bytes.toDouble();
    if (b < 1024) return '$b B';
    if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(1)} KB';
    if (b < 1024 * 1024 * 1024) {
      return '${(b / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(b / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  Widget _buildBadge(BuildContext context, String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.4), width: 0.5),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 9,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final bg = selected
        ? colors.primaryContainer.withValues(alpha: 0.55)
        : colors.surfaceContainerHighest.withValues(alpha: 0.35);

    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onSelected,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: colors.primary.withValues(alpha: 0.15),
                child: Icon(_kindIcon, size: 20, color: colors.primary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          _titleLine,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (stream.isHdr) ...[
                          const SizedBox(width: 8),
                          _buildBadge(context, 'HDR', Colors.orange),
                        ],
                        if (stream.is8K) ...[
                          const SizedBox(width: 8),
                          _buildBadge(context, '8K', Colors.purple),
                        ] else if (stream.is4K) ...[
                          const SizedBox(width: 8),
                          _buildBadge(context, '4K', Colors.red),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _subtitleLine(),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                selected
                    ? Icons.radio_button_checked_rounded
                    : Icons.radio_button_unchecked_rounded,
                color: selected ? colors.primary : colors.outline,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
