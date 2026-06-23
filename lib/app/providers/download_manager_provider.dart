import 'dart:async';
import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../../src/rust/api/downloader.dart' as rust_downloader;
import '../models/video_model.dart';
import '../providers/extractor_provider.dart';
import '../../src/rust/api/video_processor.dart' as rust_video_processor;
import '../services/bundled_ffmpeg_path.dart';
import '../services/notification_service.dart';
import '../services/permission_service.dart';
import '../utils/download_error_utils.dart';
import 'locale_provider.dart';
import 'dart:io';
import 'package:ffmpeg_kit_flutter_new_min_gpl/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_min_gpl/return_code.dart';

enum DownloadStatus { queued, downloading, paused, completed, failed, cancelled }

class DownloadItem {
  final String id;
  final String title;
  final String url;
  final String filePath;
  final String thumbnailUrl;
  final String quality;
  final String platform;
  final double progress;
  final DownloadStatus status;
  final DateTime createdAt;
  final DateTime? scheduledAt;
  final String? audioOutputFormat;
  final String? error;
  final String pageUrl;
  final String? audioStreamUrl;
  final int connections;
  final int retryCount;
  final String? phase;

  DownloadItem({
    required this.id,
    required this.title,
    required this.url,
    required this.filePath,
    required this.thumbnailUrl,
    required this.quality,
    required this.platform,
    this.progress = 0.0,
    this.status = DownloadStatus.queued,
    required this.createdAt,
    this.scheduledAt,
    this.audioOutputFormat,
    this.error,
    this.pageUrl = '',
    this.audioStreamUrl,
    this.connections = 8,
    this.retryCount = 0,
    this.phase,
  });

  DownloadItem copyWith({
    double? progress,
    DownloadStatus? status,
    String? filePath,
    String? error,
    bool clearError = false,
    int? retryCount,
    String? phase,
    bool clearPhase = false,
  }) {
    return DownloadItem(
      id: id,
      title: title,
      url: url,
      filePath: filePath ?? this.filePath,
      thumbnailUrl: thumbnailUrl,
      quality: quality,
      platform: platform,
      progress: progress ?? this.progress,
      status: status ?? this.status,
      createdAt: createdAt,
      scheduledAt: scheduledAt,
      audioOutputFormat: audioOutputFormat,
      error: clearError ? null : (error ?? this.error),
      pageUrl: pageUrl,
      audioStreamUrl: audioStreamUrl,
      connections: connections,
      retryCount: retryCount ?? this.retryCount,
      phase: clearPhase ? null : (phase ?? this.phase),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'url': url,
        'filePath': filePath,
        'thumbnailUrl': thumbnailUrl,
        'quality': quality,
        'platform': platform,
        'progress': progress,
        'status': status.index,
        'createdAt': createdAt.toIso8601String(),
        'scheduledAt': scheduledAt?.toIso8601String(),
        'audioOutputFormat': audioOutputFormat,
        'error': error,
        'pageUrl': pageUrl,
        'audioStreamUrl': audioStreamUrl,
        'connections': connections,
        'retryCount': retryCount,
        'phase': phase,
      };

  factory DownloadItem.fromJson(Map<String, dynamic> json) => DownloadItem(
        id: json['id'] as String,
        title: json['title'] as String,
        url: json['url'] as String,
        filePath: json['filePath'] as String,
        thumbnailUrl: json['thumbnailUrl'] as String? ?? '',
        quality: json['quality'] as String? ?? '',
        platform: json['platform'] as String? ?? '',
        progress: (json['progress'] as num?)?.toDouble() ?? 0,
        status: DownloadStatus.values[json['status'] as int? ?? 0],
        createdAt: DateTime.parse(json['createdAt'] as String),
        scheduledAt: json['scheduledAt'] != null
            ? DateTime.parse(json['scheduledAt'] as String)
            : null,
        audioOutputFormat: json['audioOutputFormat'] as String?,
        error: json['error'] as String?,
        pageUrl: json['pageUrl'] as String? ?? json['url'] as String? ?? '',
        audioStreamUrl: json['audioStreamUrl'] as String?,
        connections: json['connections'] as int? ?? 8,
        retryCount: json['retryCount'] as int? ?? 0,
        phase: json['phase'] as String?,
      );
}

class DownloadManagerState {
  final List<DownloadItem> items;
  final bool queuePaused;

  DownloadManagerState({this.items = const [], this.queuePaused = false});

  int get activeCount =>
      items.where((i) => i.status == DownloadStatus.downloading).length;

  List<DownloadItem> get downloadQueue =>
      items.where((i) => i.status != DownloadStatus.completed).toList();

  DownloadManagerState copyWith({List<DownloadItem>? items, bool? queuePaused}) {
    return DownloadManagerState(
      items: items ?? this.items,
      queuePaused: queuePaused ?? this.queuePaused,
    );
  }
}

class DownloadManagerNotifier extends Notifier<DownloadManagerState> {
  Timer? _progressTimer;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  final Set<String> _retryScheduled = {};

  static const _maxAutoRetries = 3;
  static const _autoRetryDelaysSec = [5, 15, 45];

  @override
  DownloadManagerState build() {
    ref.onDispose(() {
      _progressTimer?.cancel();
      _connectivitySub?.cancel();
    });
    _load();
    _startProgressTimer();
    _listenConnectivity();
    return DownloadManagerState();
  }

  void _listenConnectivity() {
    _connectivitySub?.cancel();
    _connectivitySub =
        Connectivity().onConnectivityChanged.listen((results) async {
      if (results.every((r) => r == ConnectivityResult.none)) return;
      await _retryFailedOnReconnect();
    });
  }

  Future<void> _retryFailedOnReconnect() async {
    if (state.queuePaused) return;
    for (final item in state.items) {
      if (item.status != DownloadStatus.failed) continue;
      if (!isRetryableDownloadError(item.error)) continue;
      if (item.retryCount >= _maxAutoRetries) continue;
      if (_retryScheduled.contains(item.id)) continue;
      unawaited(retryDownload(item.id, automatic: true));
    }
  }

  void _startProgressTimer() {
    _progressTimer?.cancel();
    _progressTimer =
        Timer.periodic(const Duration(milliseconds: 500), (_) => _pollProgress());
  }

  Future<void> _pollProgress() async {
    final active =
        state.items.where((i) => i.status == DownloadStatus.downloading).toList();
    if (active.isEmpty) return;

    var updated = false;
    final newItems = List<DownloadItem>.from(state.items);

    for (var i = 0; i < newItems.length; i++) {
      final item = newItems[i];
      if (item.status != DownloadStatus.downloading) continue;
      final snap = await rust_downloader.getJobProgress(jobId: item.id);
      if (snap == null) continue;
      newItems[i] = item.copyWith(
        progress: snap.percent / 100.0,
        phase: snap.phase,
      );
      updated = true;
    }

    if (updated) {
      state = state.copyWith(items: newItems);
    }
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('download_items');
    if (raw == null) return;
    final list = jsonDecode(raw) as List<dynamic>;
    final items = list
        .map((e) => DownloadItem.fromJson(e as Map<String, dynamic>))
        .map((item) {
      if (item.status == DownloadStatus.downloading) {
        return item.copyWith(status: DownloadStatus.paused, clearPhase: true);
      }
      return item;
    }).toList();
    state = state.copyWith(items: items);
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'download_items',
      jsonEncode(state.items.map((e) => e.toJson()).toList()),
    );
  }

  Future<void> addToQueue(
    VideoModel video, {
    StreamInfo? stream,
    StreamInfo? audioStream,
    int connections = 8,
    DateTime? scheduledAt,
    String? audioOutputFormat,
  }) async {
    final hasPermission = await PermissionService.requestStoragePermission();
    if (!hasPermission) {
      _onFailed(video.id, 'Storage permission denied');
      return;
    }

    final id = const Uuid().v4();
    final downloadsDir = await rust_downloader.getDownloadsDir();
    final ext = stream?.format ?? 'mp4';
    
    // When merging video+audio, the final format is always mp4
    // (FFmpeg muxes into mp4 container unless both streams are webm)
    final finalExt = (audioStream != null && ext != 'webm') ? 'mp4' : ext;
    
    final safeName =
        await rust_downloader.safeFilename(title: video.title, format: finalExt);
    final outputPath = p.join(downloadsDir, safeName);

    final item = DownloadItem(
      id: id,
      title: video.title,
      url: stream?.url ?? video.url,
      filePath: outputPath,
      thumbnailUrl: video.thumbnailUrl ?? '',
      quality: stream?.quality ?? 'Best',
      platform: video.platform,
      createdAt: DateTime.now(),
      scheduledAt: scheduledAt,
      audioOutputFormat: audioOutputFormat,
      pageUrl: video.url,
      audioStreamUrl: audioStream?.url,
      connections: connections,
    );

    state = state.copyWith(items: [...state.items, item]);
    await _save();

    if (!state.queuePaused && scheduledAt == null) {
      unawaited(_startDownload(item));
    }
  }

  Future<void> _startDownload(DownloadItem item) async {
    // Removed mandatory auth check to allow anonymous downloads

    state = state.copyWith(
      items: state.items
          .map(
            (i) => i.id == item.id
                ? i.copyWith(
                    status: DownloadStatus.downloading,
                    clearError: true,
                    clearPhase: true,
                  )
                : i,
          )
          .toList(),
    );
    await _save();

    try {
      final ffmpegPath = await resolveDesktopFfmpegPath();
      
      final result = await rust_downloader.downloadFileV2(
        url: item.url,
        outputPath: item.filePath,
        audioUrl: item.audioStreamUrl,
        jobId: item.id,
        connections: item.connections,
        muxFfmpeg: ffmpegPath,
      );

      String finalPath = result.filePath;

      // Perform FFmpegKit mobile fallback merging if audio sidecar exists and wasn't merged by Rust
      if (item.audioStreamUrl != null) {
        final dir = Directory(p.dirname(finalPath));
        final stem = p.basenameWithoutExtension(finalPath);
        final entities = dir.listSync();
        File? sidecarAudio;
        for (final entity in entities) {
          if (entity is File && p.basename(entity.path).startsWith('$stem.audio.')) {
            sidecarAudio = entity;
            break;
          }
        }

        if (sidecarAudio != null) {
          if (Platform.isAndroid || Platform.isIOS) {
            state = state.copyWith(
              items: state.items
                  .map((i) => i.id == item.id ? i.copyWith(phase: 'merging_mobile') : i)
                  .toList(),
            );

            final mergedTmp = p.join(dir.path, '$stem.ffmpeg.muxing.mp4');
            final session = await FFmpegKit.execute(
                '-y -i "$finalPath" -i "${sidecarAudio.path}" -c copy -map 0:v:0 -map 1:a:0 -shortest "$mergedTmp"');
            final returnCode = await session.getReturnCode();
            if (ReturnCode.isSuccess(returnCode)) {
              await File(mergedTmp).rename(finalPath);
              await sidecarAudio.delete();
            } else {
              final logs = await session.getLogsAsString();
              throw Exception('FFmpegKit failed to merge: $logs');
            }
          } else {
             // On Windows/Linux/macOS, sidecar exists but Rust failed to merge — FFmpeg is missing or broken.
             throw Exception('FFmpeg is required on Desktop to merge high-resolution videos. Please install FFmpeg and add it to your system PATH.');
          }
        }
      }


      // Perform FFmpeg post-processing for audio-only extraction if needed
      if (item.audioStreamUrl == null && item.audioOutputFormat != null) {
        state = state.copyWith(
          items: state.items
              .map((i) => i.id == item.id ? i.copyWith(phase: 'extracting_audio') : i)
              .toList(),
        );

        final audioExt = item.audioOutputFormat!;
        final baseName = p.basenameWithoutExtension(result.filePath);
        final dirName = p.dirname(result.filePath);
        final finalAudioPath = p.join(dirName, '$baseName.$audioExt');

        try {
          if (ffmpegPath == 'ffmpeg' && (Platform.isAndroid || Platform.isIOS)) {
            // Mobile fallback extraction
            final session = await FFmpegKit.execute(
                '-y -i "${result.filePath}" -vn -c:a copy "$finalAudioPath"');
            final returnCode = await session.getReturnCode();
            if (!ReturnCode.isSuccess(returnCode)) {
               final logs = await session.getLogsAsString();
               throw Exception('FFmpegKit failed to extract audio: $logs');
            }
          } else if (ffmpegPath != 'ffmpeg' || Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
            rust_video_processor.extractAudio(
              videoPath: result.filePath,
              outputPath: finalAudioPath,
              ffmpegPath: ffmpegPath,
            );
          }
          finalPath = finalAudioPath;
          try {
            await File(result.filePath).delete(); // Delete the original video/audio stream file
          } catch (_) {}
        } catch (e) {
           throw Exception('Audio extraction failed: $e');
        }
      }

      _onComplete(item.id, finalPath);
    } catch (e) {
      _onFailed(item.id, e.toString());
    }
  }

  void _onComplete(String id, String finalPath) {
    final index = state.items.indexWhere((i) => i.id == id);
    if (index == -1) return;

    _retryScheduled.remove(id);
    state = state.copyWith(
      items: state.items
          .map(
            (i) => i.id == id
                ? i.copyWith(
                    status: DownloadStatus.completed,
                    progress: 1.0,
                    filePath: finalPath,
                    clearPhase: true,
                    clearError: true,
                  )
                : i,
          )
          .toList(),
    );
    _save();

    NotificationService.showComplete(
      id: id.hashCode,
      title: state.items[index].title,
      filePath: finalPath,
      locale: ref.read(localeProvider),
    );
  }

  void _onFailed(String id, String error) {
    final key = downloadErrorL10nKey(error);
    _retryScheduled.remove(id);
    state = state.copyWith(
      items: state.items
          .map(
            (i) => i.id == id
                ? i.copyWith(
                    status: DownloadStatus.failed,
                    error: key,
                    clearPhase: true,
                  )
                : i,
          )
          .toList(),
    );
    _save();

    final idx = state.items.indexWhere((i) => i.id == id);
    if (idx != -1) {
      final item = state.items[idx];
      if (isRetryableDownloadError(error) && item.retryCount < _maxAutoRetries) {
        _scheduleAutoRetry(id);
      }
    }
  }

  Future<void> _scheduleAutoRetry(String id) async {
    if (_retryScheduled.contains(id)) return;
    _retryScheduled.add(id);

    final item = state.items.firstWhere((i) => i.id == id);
    final delayIndex = item.retryCount.clamp(0, _autoRetryDelaysSec.length - 1);
    await Future<void>.delayed(
      Duration(seconds: _autoRetryDelaysSec[delayIndex]),
    );

    _retryScheduled.remove(id);
    if (!ref.mounted) return;

    final idx = state.items.indexWhere((i) => i.id == id);
    if (idx == -1) return;
    final current = state.items[idx];
    if (current.status != DownloadStatus.failed) return;
    if (current.retryCount >= _maxAutoRetries) return;

    final connectivity = await Connectivity().checkConnectivity();
    if (connectivity.every((r) => r == ConnectivityResult.none)) {
      _retryScheduled.remove(id);
      return;
    }

    await retryDownload(id, automatic: true);
  }

  void setQueuePaused(bool paused) {
    state = state.copyWith(queuePaused: paused);
    if (!paused) {
      _processQueue();
    } else {
      _pauseAll();
    }
  }

  void _processQueue() {
    for (final item in state.items.where((i) => i.status == DownloadStatus.queued)) {
      unawaited(_startDownload(item));
    }
  }

  void _pauseAll() {
    for (final item in state.items.where((i) => i.status == DownloadStatus.downloading)) {
      unawaited(pauseDownload(item.id));
    }
  }

  Future<void> pauseDownload(String id) async {
    await rust_downloader.cancelJob(jobId: id);
    state = state.copyWith(
      items: state.items
          .map(
            (i) => i.id == id
                ? i.copyWith(status: DownloadStatus.paused, clearPhase: true)
                : i,
          )
          .toList(),
    );
    await _save();
  }

  Future<void> resumeDownload(String id) async {
    final index = state.items.indexWhere((i) => i.id == id);
    if (index == -1) return;
    await _startDownload(state.items[index]);
  }

  Future<void> retryDownload(String id, {bool automatic = false}) async {
    final index = state.items.indexWhere((i) => i.id == id);
    if (index == -1) return;
    var item = state.items[index];
    if (!automatic && !isRetryableDownloadError(item.error)) {
      await resumeDownload(id);
      return;
    }
    final nextCount = automatic ? item.retryCount + 1 : item.retryCount;
    item = item.copyWith(
      status: DownloadStatus.queued,
      clearError: true,
      clearPhase: true,
      retryCount: nextCount,
    );
    state = state.copyWith(
      items: state.items.map((i) => i.id == id ? item : i).toList(),
    );
    await _save();
    if (!state.queuePaused) {
      await _startDownload(item);
    }
  }

  Future<void> retryAllFailed() async {
    for (final item in state.items.where((i) => i.status == DownloadStatus.failed)) {
      if (isRetryableDownloadError(item.error)) {
        await retryDownload(item.id);
      }
    }
  }

  Future<void> cancelDownload(String id) async {
    _retryScheduled.remove(id);
    await rust_downloader.cancelJob(jobId: id);
    state = state.copyWith(items: state.items.where((i) => i.id != id).toList());
    await _save();
  }

  Future<void> removeCompleted() async {
    state = state.copyWith(
      items: state.items.where((i) => i.status != DownloadStatus.completed).toList(),
    );
    await _save();
  }
}

final downloadManagerProvider =
    NotifierProvider<DownloadManagerNotifier, DownloadManagerState>(
  DownloadManagerNotifier.new,
);
