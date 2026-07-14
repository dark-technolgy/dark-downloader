import 'dart:async';
import 'dart:convert';
import 'package:gal/gal.dart';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../../src/rust/api/downloader.dart' as rust_downloader;
import '../models/video_model.dart';
import '../providers/extractor_provider.dart';
import '../services/bundled_ffmpeg_path.dart';
import '../services/media_processor.dart';
import '../services/notification_service.dart';
import '../services/permission_service.dart';
import '../services/storage_service.dart';
import '../utils/download_error_utils.dart';
import 'locale_provider.dart';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../services/telemetry_service.dart';

enum DownloadStatus {
  queued,
  downloading,
  paused,
  completed,
  failed,
  cancelled,
}

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
  final DateTime? completedAt;
  final String? audioOutputFormat;
  final String videoOutputFormat;
  final String? error;
  final String pageUrl;
  final String? audioStreamUrl;
  final int connections;
  final int retryCount;
  final String? phase;
  final int downloadedBytes;
  final int totalBytes;
  final int speedBytesSec;
  final int etaSeconds;

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
    this.completedAt,
    this.audioOutputFormat,
    this.videoOutputFormat = 'mp4',
    this.error,
    this.pageUrl = '',
    this.audioStreamUrl,
    this.connections = 8,
    this.retryCount = 0,
    this.phase,
    this.downloadedBytes = 0,
    this.totalBytes = 0,
    this.speedBytesSec = 0,
    this.etaSeconds = 0,
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
    int? downloadedBytes,
    int? totalBytes,
    int? speedBytesSec,
    int? etaSeconds,
    DateTime? completedAt,
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
      completedAt: completedAt ?? this.completedAt,
      audioOutputFormat: audioOutputFormat,
      videoOutputFormat: videoOutputFormat,
      error: clearError ? null : (error ?? this.error),
      pageUrl: pageUrl,
      audioStreamUrl: audioStreamUrl,
      connections: connections,
      retryCount: retryCount ?? this.retryCount,
      phase: clearPhase ? null : (phase ?? this.phase),
      downloadedBytes: downloadedBytes ?? this.downloadedBytes,
      totalBytes: totalBytes ?? this.totalBytes,
      speedBytesSec: speedBytesSec ?? this.speedBytesSec,
      etaSeconds: etaSeconds ?? this.etaSeconds,
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
        'completedAt': completedAt?.toIso8601String(),
        'audioOutputFormat': audioOutputFormat,
        'videoOutputFormat': videoOutputFormat,
        'error': error,
        'pageUrl': pageUrl,
        'audioStreamUrl': audioStreamUrl,
        'connections': connections,
        'retryCount': retryCount,
        'phase': phase,
        'downloadedBytes': downloadedBytes,
        'totalBytes': totalBytes,
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
        completedAt: json['completedAt'] != null
            ? DateTime.parse(json['completedAt'] as String)
            : null,
        audioOutputFormat: json['audioOutputFormat'] as String?,
        videoOutputFormat: json['videoOutputFormat'] as String? ?? 'mp4',
        error: json['error'] as String?,
        pageUrl: json['pageUrl'] as String? ?? json['url'] as String? ?? '',
        audioStreamUrl: json['audioStreamUrl'] as String?,
        connections: json['connections'] as int? ?? 8,
        retryCount: json['retryCount'] as int? ?? 0,
        phase: json['phase'] as String?,
        downloadedBytes: (json['downloadedBytes'] as num?)?.toInt() ?? 0,
        totalBytes: (json['totalBytes'] as num?)?.toInt() ?? 0,
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

  DownloadManagerState copyWith({
    List<DownloadItem>? items,
    bool? queuePaused,
  }) {
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
    _connectivitySub = Connectivity().onConnectivityChanged.listen((
      results,
    ) async {
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
    _progressTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _pollProgress();
      _checkScheduled();
    });
  }

  Future<void> _checkScheduled() async {
    if (state.queuePaused) return;
    final now = DateTime.now();
    for (final item in state.items) {
      if (item.status == DownloadStatus.queued &&
          item.scheduledAt != null &&
          item.scheduledAt!.isBefore(now)) {
        unawaited(_startDownload(item));
      }
    }
  }

  Future<void> _pollProgress() async {
    final active = state.items
        .where((i) => i.status == DownloadStatus.downloading)
        .toList();
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
        downloadedBytes: snap.downloadedBytes.toInt(),
        totalBytes: snap.totalBytes.toInt(),
        speedBytesSec: snap.speedBytesSec.toInt(),
        etaSeconds: snap.etaSeconds.toInt(),
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
        return item.copyWith(
          status: DownloadStatus.paused,
          clearPhase: true,
        );
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
    // Resolve a *writable* downloads directory from the Dart side. Rust's
    // get_downloads_dir() returns the hard-coded public path
    // (/storage/emulated/0/Download/DarkDownloader) which is not writable on
    // Android 10+ without MANAGE_EXTERNAL_STORAGE, so downloads silently fail.
    // StorageService picks the correct app-scoped path on Android and the
    // native Downloads folder on desktop.
    final downloadsDir = (await StorageService.getDownloadsDirectory()).path;
    final ext = stream?.format ?? 'mp4';

    // Final container rules — كل الصيغ عالمية تعمل على كل المنصات:
    //  - الصوت فقط: يُحوّل لاحقاً إلى صيغة الصوت المختارة (mp3 / m4a).
    //  - الفيديو مع صوت منفصل: صيغة الإخراج **تتبع حاوية المصدر** لتجنب
    //    إعادة الترميز البطيئة/الفاشلة — WEBM(VP9) يبقى webm، وأي شيء آخر
    //    (H.264 وغيره) → mp4. هذا يطابق تماماً محرك الدمج في Rust فيتم
    //    النسخ السريع بلا فشل. الصوت يُرمَّز إلى الكودك المناسب للحاوية.
    //  - Progressive (فيديو+صوت مدمج): يحتفظ بامتداده الأصلي.
    final srcIsWebm = ext.toLowerCase() == 'webm';
    final videoOutputFormat = srcIsWebm ? 'webm' : 'mp4';
    final finalExt = audioStream != null ? videoOutputFormat : ext;

    final safeName = await rust_downloader.safeFilename(
      title: video.title,
      format: finalExt,
    );
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
      videoOutputFormat: videoOutputFormat,
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
      // On all platforms, we skip Rust's internal muxing so that we can handle
      // it in Dart via MediaProcessor, which allows us to parse stderr and show a progress bar.
      const rustMuxFfmpeg = '';

      var finalUrl = item.url;
      var finalAudioUrl = item.audioStreamUrl;

      final result = await rust_downloader.downloadFileV2(
        url: finalUrl,
        outputPath: item.filePath,
        audioUrl: finalAudioUrl,
        jobId: item.id,
        connections: item.connections,
        muxFfmpeg: rustMuxFfmpeg,
      );

      String finalPath = result.filePath;

      // Merge sidecar audio via Rust if Rust downloader left it un-muxed
      if (item.audioStreamUrl != null) {
        final dir = Directory(p.dirname(finalPath));
        final stem = p.basenameWithoutExtension(finalPath);
        final entities = dir.listSync();
        File? sidecarAudio;
        for (final entity in entities) {
          if (entity is File &&
              p.basename(entity.path).startsWith('$stem.audio.')) {
            sidecarAudio = entity;
            break;
          }
        }

        if (sidecarAudio != null) {
          state = state.copyWith(
            items: state.items
                .map((i) =>
                    i.id == item.id ? i.copyWith(phase: 'converting') : i,)
                .toList(),
          );

          // امتداد ملف الدمج المؤقت يتبع امتداد الملف النهائي الفعلي
          // (webm أو mp4) لضمان تطابق الحاوية مع الكودك وتفادي الفشل.
          final outExt = p.extension(finalPath).replaceFirst('.', '');
          final mergedTmp = p.join(
            dir.path,
            '$stem.ffmpeg.muxing.${outExt.isEmpty ? 'mp4' : outExt}',
          );
          await MediaProcessor.muxVideoAudio(
            videoPath: finalPath,
            audioPath: sidecarAudio.path,
            outputPath: mergedTmp,
            ffmpegPath: ffmpegPath,
            onProgress: (percentage) {
              state = state.copyWith(
                items: state.items
                    .map(
                      (i) => i.id == item.id
                          ? i.copyWith(
                              progress: percentage * 100.0,
                              downloadedBytes: (percentage * 1000).toInt(),
                              totalBytes: 1000,
                            )
                          : i,
                    )
                    .toList(),
              );
            },
          );
          // Robust delete & rename with retry loop for Windows file locking
          bool renameSuccess = false;
          for (var i = 0; i < 5; i++) {
            try {
              if (await File(finalPath).exists()) {
                await File(finalPath).delete();
              }
              await File(mergedTmp).rename(finalPath);
              await sidecarAudio.delete();
              renameSuccess = true;
              break;
            } catch (e) {
              await Future.delayed(const Duration(milliseconds: 500));
            }
          }
          if (!renameSuccess) {
            throw Exception(
                'Failed to rename muxed file. File might be locked.',);
          }
        }
      }

      // Perform FFmpeg post-processing for audio-only extraction if needed
      if (item.audioStreamUrl == null && item.audioOutputFormat != null) {
        state = state.copyWith(
          items: state.items
              .map(
                (i) =>
                    i.id == item.id ? i.copyWith(phase: 'extracting_audio') : i,
              )
              .toList(),
        );

        final audioExt = item.audioOutputFormat!;
        final baseName = p.basenameWithoutExtension(result.filePath);
        final dirName = p.dirname(result.filePath);
        final finalAudioPath = p.join(dirName, '$baseName.$audioExt');

        // If the source file happens to already carry the target extension
        // (e.g. we downloaded a raw .mp3), use a scratch output path so
        // FFmpeg never has input == output.
        final sameAsSource = p.equals(result.filePath, finalAudioPath);
        final scratchOut = sameAsSource
            ? p.join(dirName, '$baseName.__tmp__.$audioExt')
            : finalAudioPath;

        if (audioExt == 'mp3') {
          String? coverTmpPath;
          if (item.thumbnailUrl.isNotEmpty) {
            try {
              coverTmpPath = await _downloadThumbnailToTemp(
                item.thumbnailUrl,
                p.join(dirName, '.$baseName.cover.jpg'),
              );
            } catch (_) {
              coverTmpPath = null;
            }
          }

          // Attempt 1: rich MP3 (metadata + embedded cover). Cover embed can
          // fail on odd source thumbnails (e.g. animated WebP); fall through
          // silently.
          var richOk = false;
          try {
            await MediaProcessor.convertToMp3Rich(
              inputPath: result.filePath,
              outputPath: scratchOut,
              ffmpegPath: ffmpegPath,
              title: item.title.isNotEmpty ? item.title : null,
              artist: item.platform.isNotEmpty ? item.platform : null,
              album: item.platform.isNotEmpty ? item.platform : null,
              comment: item.pageUrl.isNotEmpty ? item.pageUrl : null,
              coverPath: coverTmpPath,
            );
            richOk = await File(scratchOut).exists();
          } catch (_) {
            richOk = false;
          }

          // Attempt 2: rich without cover (metadata only). Handles the
          // "cover format not supported" branch without dropping tags.
          if (!richOk && coverTmpPath != null) {
            try {
              await MediaProcessor.convertToMp3Rich(
                inputPath: result.filePath,
                outputPath: scratchOut,
                ffmpegPath: ffmpegPath,
                title: item.title.isNotEmpty ? item.title : null,
                artist: item.platform.isNotEmpty ? item.platform : null,
                album: item.platform.isNotEmpty ? item.platform : null,
                comment: item.pageUrl.isNotEmpty ? item.pageUrl : null,
                coverPath: null,
              );
              richOk = await File(scratchOut).exists();
            } catch (_) {
              richOk = false;
            }
          }

          // Attempt 3: plain conversion — the safety net.
          if (!richOk) {
            try {
              await MediaProcessor.convertToMp3(
                inputPath: result.filePath,
                outputPath: scratchOut,
                ffmpegPath: ffmpegPath,
              );
            } catch (e) {
              if (!await File(scratchOut).exists()) {
                throw Exception('MP3 conversion failed: $e');
              }
            }
          }

          if (coverTmpPath != null) {
            try {
              await File(coverTmpPath).delete();
            } catch (e, st) {
              debugPrint('Error deleting cover temp file: $e');
              Telemetry.instance.recordError('exception', e, stackTrace: st);
            }
          }
        } else {
          try {
            await MediaProcessor.extractAudio(
              videoPath: result.filePath,
              outputPath: scratchOut,
              ffmpegPath: ffmpegPath,
            );
          } catch (e) {
            if (!await File(scratchOut).exists()) {
              throw Exception('Audio extraction failed: $e');
            }
          }
        }

        // Ground truth: did we actually produce an audio file?
        if (!await File(scratchOut).exists()) {
          throw Exception('Audio conversion produced no output file.');
        }

        if (sameAsSource) {
          try {
            await File(result.filePath).delete();
          } catch (e, st) {
            debugPrint('Error deleting source file during rename: $e');
            Telemetry.instance.recordError('exception', e, stackTrace: st);
          }
          await File(scratchOut).rename(finalAudioPath);
        } else {
          try {
            await File(result.filePath).delete();
          } catch (e, st) {
            debugPrint('Error deleting source file after audio extraction: $e');
            Telemetry.instance.recordError('exception', e, stackTrace: st);
          }
        }
        finalPath = finalAudioPath;
      }

      await _onComplete(item.id, finalPath);
    } catch (e) {
      _onFailed(item.id, e.toString());
    }
  }

  /// Download a thumbnail to a local temp path (JPG/PNG accepted by FFmpeg mjpeg).
  /// Returns the local path on success; throws on failure.
  Future<String> _downloadThumbnailToTemp(String url, String targetPath) async {
    final uri = Uri.parse(url);
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15);
    try {
      final req = await client.getUrl(uri);
      req.headers.set(
        'user-agent',
        'Mozilla/5.0 (dark_downloader/thumb-fetch)',
      );
      final resp = await req.close();
      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        throw Exception('HTTP ${resp.statusCode}');
      }
      final file = File(targetPath);
      final sink = file.openWrite();
      await resp.pipe(sink);
      return targetPath;
    } finally {
      client.close(force: true);
    }
  }

  Future<void> _onComplete(String id, String finalPath) async {
    final index = state.items.indexWhere((i) => i.id == id);
    if (index == -1) return;

    // Ground truth: the file must exist on disk and have non-zero size before
    // we declare the download "complete". Prevents the "says done while
    // background work is still running" class of bugs.
    int finalSize = 0;
    try {
      final f = File(finalPath);
      if (!await f.exists()) {
        _onFailed(id, 'Output file missing at completion: $finalPath');
        return;
      }
      finalSize = await f.length();
      if (finalSize <= 0) {
        _onFailed(id, 'Output file is empty at completion: $finalPath');
        return;
      }
    } catch (e) {
      _onFailed(id, 'Completion check failed: $e');
      return;
    }

    if (Platform.isAndroid || Platform.isIOS) {
      final ext = p.extension(finalPath).toLowerCase();
      if (ext == '.mp4' || ext == '.webm' || ext == '.mov' || ext == '.mkv') {
        try {
          final hasAccess = await Gal.hasAccess(toAlbum: true);
          if (!hasAccess) await Gal.requestAccess(toAlbum: true);
          await Gal.putVideo(finalPath);
        } catch (e) {
          // Non-fatal, just skips saving to gallery
        }
      }
    }

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
                    downloadedBytes: finalSize,
                    totalBytes: finalSize,
                    speedBytesSec: 0,
                    etaSeconds: 0,
                    completedAt: DateTime.now(),
                  )
                : i,
          )
          .toList(),
    );
    await _save();

    unawaited(NotificationService.showComplete(
      id: id.hashCode,
      title: state.items[index].title,
      filePath: finalPath,
      locale: ref.read(localeProvider),
    ),);
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
      if (isRetryableDownloadError(error) &&
          item.retryCount < _maxAutoRetries) {
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
    for (final item in state.items.where(
      (i) => i.status == DownloadStatus.queued,
    )) {
      unawaited(_startDownload(item));
    }
  }

  void _pauseAll() {
    for (final item in state.items.where(
      (i) => i.status == DownloadStatus.downloading,
    )) {
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
    for (final item in state.items.where(
      (i) => i.status == DownloadStatus.failed,
    )) {
      if (isRetryableDownloadError(item.error)) {
        await retryDownload(item.id);
      }
    }
  }

  Future<void> cancelDownload(String id) async {
    _retryScheduled.remove(id);
    await rust_downloader.cancelJob(jobId: id);
    state = state.copyWith(
      items: state.items.where((i) => i.id != id).toList(),
    );
    await _save();
  }

  Future<void> removeCompleted() async {
    state = state.copyWith(
      items: state.items
          .where((i) => i.status != DownloadStatus.completed)
          .toList(),
    );
    await _save();
  }
}

final downloadManagerProvider =
    NotifierProvider<DownloadManagerNotifier, DownloadManagerState>(
  DownloadManagerNotifier.new,
);
