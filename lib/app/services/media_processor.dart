import 'dart:convert';
import 'dart:io';

import 'package:ffmpeg_kit_16kb/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_16kb/return_code.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../../src/rust/api/video_processor.dart' as rust_vp;

/// Cross-platform media processing facade.
///
/// FFmpeg is invoked differently per platform:
///   * Desktop (Windows / Linux / macOS): a bundled FFmpeg **binary** driven
///     through the Rust subprocess layer (`rust_vp`). This is the path that is
///     already validated on Windows and stays untouched.
///   * Mobile (Android / iOS): the in-process `ffmpeg_kit_flutter_new` library
///     (Full-GPL: libmp3lame / libx264 / libvpx). No external binary exists on
///     these platforms, so every FFmpeg operation is routed here.
///
/// The argument builders below mirror the Rust logic in
/// `rust/src/api/video_processor.rs` one-for-one so behaviour (copy → transcode
/// fallbacks, container-aware codecs, id3v2 tags, embedded cover art) is
/// identical across platforms.
class MediaProcessor {
  MediaProcessor._();

  /// True when FFmpeg must be executed in-process via ffmpeg_kit (mobile).
  static bool get _useKit => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  static bool _isWebmContainer(String path) {
    final ext = p.extension(path).replaceFirst('.', '').toLowerCase();
    return ext == 'webm' || ext == 'mkv';
  }

  static String _audioExt(String path) =>
      p.extension(path).replaceFirst('.', '').toLowerCase();

  /// Runs an FFmpeg argument list on mobile and returns whether it succeeded.
  static Future<bool> _run(List<String> args) async {
    final session = await FFmpegKit.executeWithArguments(args);
    final rc = await session.getReturnCode();
    return ReturnCode.isSuccess(rc);
  }

  static Future<bool> _runWithProgress(
    List<String> args,
    String ffmpegPath,
    int? totalDurationSec,
    void Function(double)? onProgress,
  ) async {
    if (_useKit) {
      if (onProgress == null || totalDurationSec == null || totalDurationSec <= 0) {
        return await _run(args);
      }
      final session = await FFmpegKit.executeAsync(
        args.join(' '),
        (session) async {},
        (log) {},
        (statistics) {
          final timeMs = statistics.getTime();
          final percentage = timeMs / (totalDurationSec * 1000);
          onProgress(percentage.clamp(0.0, 1.0));
        },
      );
      final rc = await session.getReturnCode();
      return ReturnCode.isSuccess(rc);
    } else {
      final process = await Process.start(ffmpegPath, args);
      final durationRegex = RegExp(r'Duration: (\d{2}):(\d{2}):(\d{2})\.(\d{2})');
      final timeRegex = RegExp(r'time=(\d{2}):(\d{2}):(\d{2})\.(\d{2})');
      int? parsedDurationSec = totalDurationSec;

      process.stderr.transform(utf8.decoder).listen((line) {
        if (onProgress != null) {
          if (parsedDurationSec == null || parsedDurationSec! <= 0) {
            final durMatch = durationRegex.firstMatch(line);
            if (durMatch != null) {
              final h = int.parse(durMatch.group(1)!);
              final m = int.parse(durMatch.group(2)!);
              final s = int.parse(durMatch.group(3)!);
              parsedDurationSec = h * 3600 + m * 60 + s;
            }
          }
          final timeMatch = timeRegex.firstMatch(line);
          if (timeMatch != null && parsedDurationSec != null && parsedDurationSec! > 0) {
            final h = int.parse(timeMatch.group(1)!);
            final m = int.parse(timeMatch.group(2)!);
            final s = int.parse(timeMatch.group(3)!);
            final currentSec = h * 3600 + m * 60 + s;
            final percentage = currentSec / parsedDurationSec!;
            onProgress(percentage.clamp(0.0, 1.0));
          }
        }
      });

      final exitCode = await process.exitCode;
      return exitCode == 0;
    }
  }

  // ---------------------------------------------------------------------------
  // Mux video + audio
  // ---------------------------------------------------------------------------
  static Future<void> muxVideoAudio({
    required String videoPath,
    required String audioPath,
    required String outputPath,
    required String ffmpegPath,
    int? durationSeconds,
    void Function(double)? onProgress,
  }) async {
    final isWebm = _isWebmContainer(outputPath);
    final audioCodec = isWebm ? 'libopus' : 'aac';

    // Attempt 1: copy video and audio (fast, lossless).
    final copyOk = await _runWithProgress([
      '-y',
      '-i',
      videoPath,
      '-i',
      audioPath,
      '-c',
      'copy',
      '-map',
      '0:v:0',
      '-map',
      '1:a:0',
      '-shortest',
      outputPath,
    ], ffmpegPath, durationSeconds, null,); // Copy is fast, no progress needed
    if (copyOk) return;

    // Attempt 2: full transcode into a codec the container accepts.
    final videoCodec = isWebm ? 'libvpx-vp9' : 'libx264';
    final args = <String>[
      '-y',
      '-i',
      videoPath,
      '-i',
      audioPath,
      '-c:v',
      videoCodec,
      '-c:a',
      audioCodec,
      '-map',
      '0:v:0',
      '-map',
      '1:a:0',
      '-shortest',
    ];
    if (!isWebm) {
      args.addAll([
        '-preset',
        'veryfast',
        '-crf',
        '20',
        '-pix_fmt',
        'yuv420p',
        '-movflags',
        '+faststart',
      ]);
    } else {
      args.addAll(['-b:v', '0', '-crf', '32']);
    }
    args.add(outputPath);

    final transcodeOk = await _runWithProgress(args, ffmpegPath, durationSeconds, onProgress);
    if (!transcodeOk) {
      throw Exception('FFmpeg mux failed (copy and transcode both failed)');
    }
  }

  // ---------------------------------------------------------------------------
  // Extract audio
  // ---------------------------------------------------------------------------
  static Future<void> extractAudio({
    required String videoPath,
    required String outputPath,
    required String ffmpegPath,
  }) async {
    if (!_useKit) {
      await rust_vp.extractAudio(
        videoPath: videoPath,
        outputPath: outputPath,
        ffmpegPath: ffmpegPath,
      );
      return;
    }

    // Attempt 1: stream-copy — fastest, lossless, keeps original codec.
    final copyOk = await _run([
      '-y',
      '-i',
      videoPath,
      '-vn',
      '-c:a',
      'copy',
      outputPath,
    ]);
    if (copyOk) return;

    // Attempt 2: transcode to a codec that matches the target container.
    final ext = _audioExt(outputPath);
    final String codec;
    final List<String> extra;
    switch (ext) {
      case 'm4a':
      case 'mp4':
      case 'aac':
        codec = 'aac';
        extra = ['-b:a', '192k'];
        break;
      case 'opus':
      case 'webm':
        codec = 'libopus';
        extra = ['-b:a', '160k'];
        break;
      case 'ogg':
        codec = 'libvorbis';
        extra = ['-q:a', '5'];
        break;
      case 'mp3':
        codec = 'libmp3lame';
        extra = ['-q:a', '2'];
        break;
      case 'wav':
        codec = 'pcm_s16le';
        extra = const [];
        break;
      case 'flac':
        codec = 'flac';
        extra = const [];
        break;
      default:
        codec = 'aac';
        extra = ['-b:a', '192k'];
    }

    final args = <String>[
      '-y',
      '-i',
      videoPath,
      '-vn',
      '-c:a',
      codec,
      ...extra,
      outputPath,
    ];
    final transcodeOk = await _run(args);
    if (!transcodeOk) {
      throw Exception(
        'FFmpeg audio extraction failed (copy and transcode both failed)',
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Convert to MP3 (plain)
  // ---------------------------------------------------------------------------
  static Future<void> convertToMp3({
    required String inputPath,
    required String outputPath,
    required String ffmpegPath,
  }) async {
    if (!_useKit) {
      await rust_vp.convertToMp3(
        inputPath: inputPath,
        outputPath: outputPath,
        ffmpegPath: ffmpegPath,
      );
      return;
    }

    final ok = await _run([
      '-y',
      '-i',
      inputPath,
      '-vn',
      '-c:a',
      'libmp3lame',
      '-q:a',
      '0',
      '-write_xing',
      '1',
      '-id3v2_version',
      '3',
      '-map_metadata',
      '0',
      outputPath,
    ]);
    if (!ok) {
      throw Exception('FFmpeg MP3 conversion failed');
    }
  }

  // ---------------------------------------------------------------------------
  // Convert to MP3 (rich: metadata + optional embedded cover art)
  // ---------------------------------------------------------------------------
  static Future<void> convertToMp3Rich({
    required String inputPath,
    required String outputPath,
    required String ffmpegPath,
    String? title,
    String? artist,
    String? album,
    String? date,
    String? comment,
    String? coverPath,
  }) async {
    if (!_useKit) {
      await rust_vp.convertToMp3Rich(
        inputPath: inputPath,
        outputPath: outputPath,
        ffmpegPath: ffmpegPath,
        title: title,
        artist: artist,
        album: album,
        date: date,
        comment: comment,
        coverPath: coverPath,
      );
      return;
    }

    final hasCover =
        coverPath != null &&
        coverPath.isNotEmpty &&
        File(coverPath).existsSync();

    final args = <String>['-y', '-i', inputPath];
    if (hasCover) {
      args.addAll([
        '-i',
        coverPath,
        '-map',
        '0:a',
        '-map',
        '1:v',
        '-c:v',
        'mjpeg',
        '-disposition:v:0',
        'attached_pic',
        '-metadata:s:v:0',
        'title=Album cover',
        '-metadata:s:v:0',
        'comment=Cover (front)',
      ]);
    } else {
      args.add('-vn');
    }

    args.addAll([
      '-c:a',
      'libmp3lame',
      '-q:a',
      '0',
      '-write_xing',
      '1',
      '-id3v2_version',
      '3',
      '-map_metadata',
      '0',
    ]);

    void addMeta(String key, String? value) {
      final trimmed = value?.trim();
      if (trimmed != null && trimmed.isNotEmpty) {
        args.addAll(['-metadata', '$key=$trimmed']);
      }
    }

    addMeta('title', title);
    addMeta('artist', artist);
    addMeta('album', album);
    addMeta('date', date);
    addMeta('comment', comment);

    args.add(outputPath);

    final ok = await _run(args);
    if (!ok) {
      throw Exception('FFmpeg rich MP3 conversion failed');
    }
  }

  // ---------------------------------------------------------------------------
  // Embed album art into an existing MP3 (in place, via temp intermediate)
  // ---------------------------------------------------------------------------
  static Future<void> embedAlbumArt({
    required String mp3Path,
    required String coverPath,
    required String ffmpegPath,
  }) async {
    if (!_useKit) {
      await rust_vp.embedAlbumArt(
        mp3Path: mp3Path,
        coverPath: coverPath,
        ffmpegPath: ffmpegPath,
      );
      return;
    }

    if (!File(coverPath).existsSync()) {
      throw Exception('Cover file not found: $coverPath');
    }

    final tmpPath = '$mp3Path.cover.tmp.mp3';
    final ok = await _run([
      '-y',
      '-i',
      mp3Path,
      '-i',
      coverPath,
      '-map',
      '0:a',
      '-map',
      '1:v',
      '-c:a',
      'copy',
      '-c:v',
      'mjpeg',
      '-disposition:v:0',
      'attached_pic',
      '-id3v2_version',
      '3',
      '-metadata:s:v:0',
      'title=Album cover',
      '-metadata:s:v:0',
      'comment=Cover (front)',
      tmpPath,
    ]);
    if (!ok) {
      try {
        await File(tmpPath).delete();
      } catch (_) {}
      throw Exception('FFmpeg album-art embed failed');
    }
    await File(tmpPath).rename(mp3Path);
  }

  // ---------------------------------------------------------------------------
  // Compress video
  // ---------------------------------------------------------------------------
  static Future<void> compressVideo({
    required String inputPath,
    required String outputPath,
    required String ffmpegPath,
  }) async {
    if (!_useKit) {
      await rust_vp.compressVideo(
        inputPath: inputPath,
        outputPath: outputPath,
        ffmpegPath: ffmpegPath,
      );
      return;
    }

    final ok = await _run([
      '-y',
      '-i',
      inputPath,
      '-vcodec',
      'libx264',
      '-crf',
      '26',
      outputPath,
    ]);
    if (!ok) {
      throw Exception('FFmpeg video compression failed');
    }
  }
}
