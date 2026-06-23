import 'package:flutter/material.dart';

import '../../config/localization.dart';
import '../../providers/extractor_provider.dart';
import '../../utils/stream_utils.dart';

/// Hero header for the selected stream quality.
/// Shows: thumbnail, title, quality pill, codec, size, etc.
class SelectedStreamHeader extends StatelessWidget {
  const SelectedStreamHeader({
    super.key,
    this.stream,
    required this.locale,
    this.thumbnailUrl,
    required this.title,
    required this.selectedLabel,
    required this.downloadLabel,
    this.onDownload,
    this.isDownloading = false,
  });

  final StreamInfo? stream;
  final Locale locale;
  final String? thumbnailUrl;
  final String title;
  final String selectedLabel;
  final String downloadLabel;
  final VoidCallback? onDownload;
  final bool isDownloading;

  String _qualityBadge(StreamInfo s) {
    if (s.kind == StreamKind.audioOnly) return 'AUDIO';
    return s.quality;
  }

  String _formatBytes(BigInt bytes) {
    final b = bytes.toDouble();
    if (b < 1024) return '$b B';
    if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(1)} KB';
    if (b < 1024 * 1024 * 1024) {
      return '${(b / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(b / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final s = stream;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 120,
              height: 68,
              decoration: BoxDecoration(
                color: colors.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
                image: thumbnailUrl != null
                    ? DecorationImage(
                        image: NetworkImage(thumbnailUrl!),
                        fit: BoxFit.cover,
                      )
                    : null,
              ),
              child: thumbnailUrl == null
                  ? const Icon(Icons.video_library_rounded, color: Colors.grey)
                  : null,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      height: 1.2,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    selectedLabel,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        if (s != null)
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _Pill(
                label: _qualityBadge(s),
                icon: s.kind == StreamKind.audioOnly
                    ? Icons.graphic_eq_rounded
                    : Icons.hd_rounded,
                primary: true,
              ),
              _Pill(
                label: localizedCodecLabel(s, locale),
                icon: Icons.memory_rounded,
              ),
              _Pill(
                label: (s.container ?? s.format).toUpperCase(),
                icon: Icons.inventory_2_outlined,
              ),
              if (s.bitrateKbps != null)
                _Pill(
                  label: localizedBitrateKbps(s.bitrateKbps!, locale),
                  icon: Icons.speed_rounded,
                ),
              if (s.fileSizeBytes != null && s.fileSizeBytes! > BigInt.zero)
                _Pill(
                  label: _formatBytes(s.fileSizeBytes!),
                  icon: Icons.sd_storage_outlined,
                ),
            ],
          )
        else
          Text(
            AppLocalization.translate('stream_codec_unknown', locale),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: (onDownload == null || isDownloading) ? null : onDownload,
            icon: isDownloading
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.download_rounded),
            label: Text(downloadLabel),
          ),
        ),
      ],
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({
    required this.label,
    required this.icon,
    this.primary = false,
  });

  final String label;
  final IconData icon;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: primary
            ? colors.primary.withValues(alpha: 0.1)
            : colors.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: primary ? colors.primary.withValues(alpha: 0.2) : Colors.transparent,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 14,
            color: primary ? colors.primary : colors.onSurfaceVariant,
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: primary ? FontWeight.bold : FontWeight.w500,
              color: primary ? colors.primary : colors.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
