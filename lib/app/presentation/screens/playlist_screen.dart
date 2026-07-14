import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/localization.dart';
import '../../providers/download_manager_provider.dart';
import '../../providers/extractor_provider.dart';
import '../../providers/locale_provider.dart';
import '../../utils/download_streams_resolver.dart';
import '../../utils/stream_utils.dart';
import '../../../src/rust/api/models.dart' as rust_models;

class PlaylistScreen extends ConsumerStatefulWidget {
  final rust_models.PlaylistResult playlist;
  const PlaylistScreen({required this.playlist, super.key});

  @override
  ConsumerState<PlaylistScreen> createState() => _PlaylistScreenState();
}

class _PlaylistScreenState extends ConsumerState<PlaylistScreen> {
  final Set<int> _selectedIndices = {};

  @override
  void initState() {
    super.initState();
    // Select all by default
    for (int i = 0; i < widget.playlist.items.length; i++) {
      _selectedIndices.add(i);
    }
  }

  Future<void> _startBatchDownload() async {
    final manager = ref.read(downloadManagerProvider.notifier);
    final extractor = ref.read(extractorProvider.notifier);
    final locale = ref.read(localeProvider);
    const t = AppLocalization.translate;

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(t('playlist_preparing', locale)),
          ],
        ),
      ),
    );

    var enqueued = 0;
    for (final index in _selectedIndices) {
      final item = widget.playlist.items[index];
      try {
        await extractor.extractVideo(item.url);
        final state = ref.read(extractorProvider);
        if (state.video != null && state.streams.isNotEmpty) {
          final video = state.video!;
          final pair = resolveDownloadStreams(
            video,
            state.streams,
            selected: pickBestDefault(state.streams),
            allowMuxedFallback: true,
          );
          await manager.addToQueue(
            video,
            stream: pair.primary,
            audioStream: pair.audioCompanion,
          );
          enqueued++;
        }
      } catch (e) {
        debugPrint('Failed to enqueue playlist item: ${item.url}');
      }
    }

    if (!mounted) return;
    Navigator.pop(context); // Close dialog
    Navigator.pop(context); // Go back home
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          enqueued > 0
              ? t('playlist_added_batch', locale).replaceAll('{n}', '$enqueued')
              : t('playlist_nothing_enqueued', locale),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final locale = ref.watch(localeProvider);
    const t = AppLocalization.translate;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.playlist.title),
        actions: [
          Checkbox(
            value: _selectedIndices.length == widget.playlist.items.length,
            onChanged: (v) {
              setState(() {
                if (v == true) {
                  for (int i = 0; i < widget.playlist.items.length; i++) {
                    _selectedIndices.add(i);
                  }
                } else {
                  _selectedIndices.clear();
                }
              });
            },
          ),
        ],
      ),
      body: ListView.builder(
        itemCount: widget.playlist.items.length,
        itemBuilder: (context, index) {
          final item = widget.playlist.items[index];
          final isSelected = _selectedIndices.contains(index);
          return ListTile(
            leading: Image.network(item.thumbnailUrl ?? '', width: 80, errorBuilder: (context, error, stackTrace) => const Icon(Icons.movie)),
            title: Text(item.title, maxLines: 2, overflow: TextOverflow.ellipsis),
            trailing: Checkbox(
              value: isSelected,
              onChanged: (v) {
                setState(() {
                  if (v == true) {
                    _selectedIndices.add(index);
                  } else {
                    _selectedIndices.remove(index);
                  }
                });
              },
            ),
          );
        },
      ),
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.all(16.0),
        child: ElevatedButton.icon(
          onPressed: _selectedIndices.isEmpty ? null : _startBatchDownload,
          icon: const Icon(Icons.download_rounded),
          label: Text(
            t('playlist_download_selected', locale).replaceAll('{n}', '${_selectedIndices.length}'),
          ),
          style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 50)),
        ),
      ),
    );
  }
}
