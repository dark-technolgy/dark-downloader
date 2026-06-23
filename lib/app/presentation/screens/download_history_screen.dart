import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_file/open_file.dart';
import 'package:share_plus/share_plus.dart';

import '../../config/localization.dart';
import '../../providers/download_manager_provider.dart';
import '../../providers/locale_provider.dart';
import '../../utils/download_error_utils.dart';
import '../../utils/open_download_folder.dart';
import '../../providers/ai_assistant_provider.dart';
import '../../providers/vault_provider.dart';
import 'video_player_screen.dart';

class DownloadHistoryScreen extends ConsumerWidget {
  const DownloadHistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(downloadManagerProvider);
    final locale = ref.watch(localeProvider);
    final t = AppLocalization.translate;
    final failedRetryable = state.items
        .where((i) =>
            i.status == DownloadStatus.failed &&
            isRetryableDownloadError(i.error))
        .length;

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text(t('downloads', locale)),
          bottom: TabBar(
            tabs: [
              Tab(text: t('dm_tab_active', locale)),
              Tab(text: t('dm_tab_completed', locale)),
            ],
          ),
          actions: [
            if (failedRetryable > 0)
              TextButton.icon(
                onPressed: () =>
                    ref.read(downloadManagerProvider.notifier).retryAllFailed(),
                icon: const Icon(Icons.refresh_rounded, size: 20),
                label: Text(t('dm_retry_all_failed', locale)),
              ),
            IconButton(
              tooltip: state.queuePaused
                  ? t('dm_resume_queue', locale)
                  : t('dm_pause_queue', locale),
              icon: Icon(state.queuePaused ? Icons.play_arrow : Icons.pause),
              onPressed: () => ref
                  .read(downloadManagerProvider.notifier)
                  .setQueuePaused(!state.queuePaused),
            ),
          ],
        ),
        body: Column(
          children: [
            if (state.queuePaused)
              MaterialBanner(
                content: Text(t('dm_queue_paused_banner', locale)),
                leading: const Icon(Icons.pause_circle_outline),
                actions: [
                  TextButton(
                    onPressed: () => ref
                        .read(downloadManagerProvider.notifier)
                        .setQueuePaused(false),
                    child: Text(t('dm_resume_queue', locale)),
                  ),
                ],
              ),
            Expanded(
              child: TabBarView(
                children: [
                  _DownloadList(
                    emptyMessage: t('dm_empty_active', locale),
                    items: state.items
                        .where((i) => i.status != DownloadStatus.completed)
                        .toList(),
                  ),
                  _DownloadList(
                    emptyMessage: t('dm_empty_completed', locale),
                    items: state.items
                        .where((i) => i.status == DownloadStatus.completed)
                        .toList(),
                    completedTab: true,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DownloadList extends ConsumerWidget {
  const _DownloadList({
    required this.items,
    required this.emptyMessage,
    this.completedTab = false,
  });

  final List<DownloadItem> items;
  final String emptyMessage;
  final bool completedTab;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (items.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              completedTab
                  ? Icons.download_done_outlined
                  : Icons.download_outlined,
              size: 64,
              color: Colors.grey,
            ),
            const SizedBox(height: 12),
            Text(emptyMessage, style: const TextStyle(color: Colors.grey)),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: items.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, index) => _DownloadTile(item: items[index]),
    );
  }
}

class _DownloadTile extends ConsumerWidget {
  const _DownloadTile({required this.item});

  final DownloadItem item;

  Future<void> _preview(BuildContext context) async {
    final file = File(item.filePath);
    if (!await file.exists()) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLocalization.translate('dm_file_missing', Localizations.localeOf(context)),
          ),
        ),
      );
      return;
    }
    if (!context.mounted) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => VideoPlayerScreen(
          source: item.filePath,
          title: item.title,
        ),
      ),
    );
  }

  Future<void> _share(BuildContext context, Locale locale) async {
    final t = AppLocalization.translate;
    final file = File(item.filePath);
    if (!await file.exists()) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t('dm_file_missing', locale))),
      );
      return;
    }
    // ignore: deprecated_member_use
    await Share.shareXFiles(
      [XFile(item.filePath)],
      text: item.title,
    );
  }

  Future<void> _openFolder(BuildContext context, Locale locale) async {
    final t = AppLocalization.translate;
    final ok = await openDownloadFolder(item.filePath);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t('dm_open_folder_failed', locale))),
      );
    }
  }

  void _showAiSummary(BuildContext context, DownloadItem item) {
    showDialog(
      context: context,
      builder: (context) {
        return Consumer(
          builder: (context, ref, _) {
            final aiState = ref.watch(aiAssistantProvider);
            return AlertDialog(
              backgroundColor: const Color(0xFF0A0A0A),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24), side: const BorderSide(color: Colors.amber, width: 0.5)),
              title: const Row(
                children: [
                  Icon(Icons.auto_awesome_rounded, color: Colors.amber),
                  SizedBox(width: 12),
                  Text("ملخص ذكاء دارك", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (aiState.status == AiTaskStatus.idle)
                    const Text("هل تريد استخدام الذكاء الاصطناعي لتلخيص محتوى هذا الفيديو؟", style: TextStyle(color: Colors.grey))
                  else if (aiState.status == AiTaskStatus.processing)
                    const Column(
                      children: [
                        CircularProgressIndicator(color: Colors.amber),
                        SizedBox(height: 20),
                        Text("جاري قراءة الفيديو وتحليله...", style: TextStyle(color: Colors.grey)),
                      ],
                    )
                  else if (aiState.status == AiTaskStatus.completed)
                    Text(aiState.result ?? "لا يتوفر ملخص لهذا الفيديو.", style: const TextStyle(color: Colors.white70))
                  else
                    Text(aiState.errorMessage ?? "حدث خطأ أثناء المعالجة.", style: const TextStyle(color: Colors.redAccent)),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    ref.read(aiAssistantProvider.notifier).reset();
                    Navigator.pop(context);
                  }, 
                  child: const Text("إغلاق", style: TextStyle(color: Colors.grey))
                ),
                if (aiState.status == AiTaskStatus.idle)
                  ElevatedButton(
                    onPressed: () => ref.read(aiAssistantProvider.notifier).summarizeVideo(item.title, ""),
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.amber, foregroundColor: Colors.black),
                    child: const Text("ابدأ التلخيص الآن"),
                  ),
              ],
            );
          }
        );
      },
    );
  }

  void _showAiTranscribe(BuildContext context, DownloadItem item) {
    showDialog(
      context: context,
      builder: (context) {
        return Consumer(
          builder: (context, ref, _) {
            final aiState = ref.watch(aiAssistantProvider);
            return AlertDialog(
              backgroundColor: const Color(0xFF0A0A0A),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24), side: const BorderSide(color: Colors.blueAccent, width: 0.5)),
              title: const Row(
                children: [
                  Icon(Icons.closed_caption_rounded, color: Colors.blueAccent),
                  SizedBox(width: 12),
                  Text("ترجمة ذكاء دارك", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (aiState.status == AiTaskStatus.idle)
                    const Text("هل تريد تحويل الكلام في هذا الفيديو إلى نص (ترجمة تلقائية)؟", style: TextStyle(color: Colors.grey))
                  else if (aiState.status == AiTaskStatus.processing)
                    const Column(
                      children: [
                        CircularProgressIndicator(color: Colors.blueAccent),
                        SizedBox(height: 20),
                        Text("جاري استخراج الكلام وتحليله...", style: TextStyle(color: Colors.grey)),
                      ],
                    )
                  else if (aiState.status == AiTaskStatus.completed)
                    SingleChildScrollView(child: Text(aiState.result ?? "لا يتوفر نص لهذا الفيديو.", style: const TextStyle(color: Colors.white70)))
                  else
                    Text(aiState.errorMessage ?? "حدث خطأ أثناء المعالجة.", style: const TextStyle(color: Colors.redAccent)),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    ref.read(aiAssistantProvider.notifier).reset();
                    Navigator.pop(context);
                  }, 
                  child: const Text("إغلاق", style: TextStyle(color: Colors.grey))
                ),
                if (aiState.status == AiTaskStatus.idle)
                  ElevatedButton(
                    onPressed: () => ref.read(aiAssistantProvider.notifier).transcribeVideo(item.filePath),
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent, foregroundColor: Colors.white),
                    child: const Text("ابدأ الترجمة الآن"),
                  ),
              ],
            );
          }
        );
      },
    );
  }

  String _statusLabel(String Function(String, Locale) t, Locale locale) {
    if (item.phase != null && item.phase!.contains('mux')) {
      return t('dm_merging', locale);
    }
    switch (item.status) {
      case DownloadStatus.downloading:
        return t('dm_downloading_label', locale)
            .replaceAll('{size}', '${(item.progress * 100).toStringAsFixed(0)}%');
      case DownloadStatus.paused:
        return t('dm_paused', locale);
      case DownloadStatus.queued:
        return t('dm_queued', locale);
      case DownloadStatus.failed:
        return t(item.error ?? 'dm_fallback_failed', locale);
      case DownloadStatus.completed:
        return t('success', locale);
      case DownloadStatus.cancelled:
        return t('dm_err_cancelled', locale);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(localeProvider);
    final t = AppLocalization.translate;
    final notifier = ref.read(downloadManagerProvider.notifier);
    final theme = Theme.of(context);
    final canPreview = item.status == DownloadStatus.completed;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: canPreview ? () => _preview(context) : null,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: SizedBox(
                      width: 72,
                      height: 72,
                      child: item.thumbnailUrl.isNotEmpty
                          ? Image.network(
                              item.thumbnailUrl,
                              fit: BoxFit.cover,
                              errorBuilder: (_, _, _) => ColoredBox(
                                color: theme.colorScheme.surfaceContainerHighest,
                                child: Icon(
                                  Icons.video_library_rounded,
                                  color: theme.colorScheme.primary,
                                ),
                              ),
                            )
                          : ColoredBox(
                              color: theme.colorScheme.surfaceContainerHighest,
                              child: Icon(
                                Icons.video_library_rounded,
                                color: theme.colorScheme.primary,
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${item.quality} · ${item.platform}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _statusLabel(t, locale),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: item.status == DownloadStatus.failed
                                ? theme.colorScheme.error
                                : theme.colorScheme.primary,
                          ),
                        ),
                        if (item.retryCount > 0 &&
                            item.status == DownloadStatus.failed)
                          Text(
                            t('dm_auto_retrying', locale)
                                .replaceAll('{s}', '—')
                                .replaceAll('{n}', '${item.retryCount}/3'),
                            style: theme.textTheme.labelSmall,
                          ),
                      ],
                    ),
                  ),
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert),
                    onSelected: (value) async {
                      switch (value) {
                        case 'preview':
                          await _preview(context);
                        case 'share':
                          await _share(context, locale);
                        case 'folder':
                          await _openFolder(context, locale);
                        case 'open':
                          await OpenFile.open(item.filePath);
                        case 'vault':
                          await ref.read(vaultProvider.notifier).encryptFile(File(item.filePath));
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('تم تشفير الملف ونقله للخزنة بنجاح 🔒')),
                            );
                          }
                        case 'ai_summary':
                          _showAiSummary(context, item);
                        case 'ai_transcribe':
                          _showAiTranscribe(context, item);
                        case 'retry':
                          await notifier.retryDownload(item.id);
                        case 'pause':
                          await notifier.pauseDownload(item.id);
                        case 'resume':
                          await notifier.resumeDownload(item.id);
                        case 'cancel':
                          await notifier.cancelDownload(item.id);
                      }
                    },
                    itemBuilder: (ctx) => [
                      if (canPreview)
                        PopupMenuItem(
                          value: 'preview',
                          child: ListTile(
                            leading: const Icon(Icons.play_circle_outline),
                            title: Text(t('dm_preview', locale)),
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                      if (canPreview)
                        PopupMenuItem(
                          value: 'share',
                          child: ListTile(
                            leading: const Icon(Icons.share_outlined),
                            title: Text(t('dm_share', locale)),
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                      if (canPreview)
                        PopupMenuItem(
                          value: 'open',
                          child: ListTile(
                            leading: const Icon(Icons.open_in_new_rounded),
                            title: Text(t('dm_open_file', locale)),
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                      if (canPreview)
                        PopupMenuItem(
                          value: 'folder',
                          child: ListTile(
                            leading: const Icon(Icons.folder_open_rounded),
                            title: Text(t('dm_open_folder', locale)),
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                      if (canPreview)
                        PopupMenuItem(
                          value: 'ai_summary',
                          child: ListTile(
                            leading: const Icon(Icons.auto_awesome_rounded, color: Colors.amber),
                            title: const Text('ملخص ذكي (AI)', style: TextStyle(color: Colors.amber)),
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                      if (canPreview)
                        PopupMenuItem(
                          value: 'ai_transcribe',
                          child: ListTile(
                            leading: const Icon(Icons.closed_caption_rounded, color: Colors.blueAccent),
                            title: const Text('ترجمة تلقائية (AI)', style: TextStyle(color: Colors.blueAccent)),
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                      if (canPreview)
                        PopupMenuItem(
                          value: 'vault',
                          child: ListTile(
                            leading: const Icon(Icons.security_rounded, color: Color(0xFF00A3FF)),
                            title: const Text('تشفير ونقل للخزنة 🔒', style: TextStyle(color: Color(0xFF00A3FF))),
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                      if (item.status == DownloadStatus.failed &&
                          isRetryableDownloadError(item.error))
                        PopupMenuItem(
                          value: 'retry',
                          child: ListTile(
                            leading: const Icon(Icons.refresh_rounded),
                            title: Text(t('dm_retry', locale)),
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                      if (item.status == DownloadStatus.downloading)
                        PopupMenuItem(
                          value: 'pause',
                          child: ListTile(
                            leading: const Icon(Icons.pause_rounded),
                            title: Text(t('dm_pause', locale)),
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                      if (item.status == DownloadStatus.paused)
                        PopupMenuItem(
                          value: 'resume',
                          child: ListTile(
                            leading: const Icon(Icons.play_arrow_rounded),
                            title: Text(t('dm_resume', locale)),
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                      PopupMenuItem(
                        value: 'cancel',
                        child: ListTile(
                          leading: Icon(Icons.delete_outline,
                              color: theme.colorScheme.error),
                          title: Text(
                            t('delete', locale),
                            style: TextStyle(color: theme.colorScheme.error),
                          ),
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              if (item.status != DownloadStatus.completed) ...[
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: item.progress > 0 ? item.progress : null,
                    minHeight: 6,
                  ),
                ),
              ],
              if (item.status == DownloadStatus.completed) ...[
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _preview(context),
                        icon: const Icon(Icons.play_arrow_rounded, size: 18),
                        label: Text(t('dm_preview', locale)),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      tooltip: t('dm_share', locale),
                      onPressed: () => _share(context, locale),
                      icon: const Icon(Icons.share_outlined),
                    ),
                    IconButton(
                      tooltip: t('dm_open_folder', locale),
                      onPressed: () => _openFolder(context, locale),
                      icon: const Icon(Icons.folder_open_rounded),
                    ),
                  ],
                ),
              ] else if (item.status == DownloadStatus.failed &&
                  isRetryableDownloadError(item.error)) ...[
                const SizedBox(height: 8),
                Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: FilledButton.tonalIcon(
                    onPressed: () => notifier.retryDownload(item.id),
                    icon: const Icon(Icons.refresh_rounded, size: 18),
                    label: Text(t('dm_retry', locale)),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
