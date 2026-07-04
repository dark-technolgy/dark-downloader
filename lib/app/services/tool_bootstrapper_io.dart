import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'bundled_ffmpeg_path.dart';
import 'telemetry_service.dart';

/// سطح المكتب (ويندوز/لينكس): يتحقق من FFmpeg المضمّن مع المثبّت (CMake → مجلد ffmpeg/)
/// أو من أصول Flutter. الإصدار الافتراضي للموقع **بدون تنزيل من الإنترنت** للمستخدم.
/// [use_remote_bootstrap] في manifest يبقى خياراً احتياطياً فقط.
class ToolBootstrapper {
  ToolBootstrapper._();

  /// يُحدَّد بعد [ensure]: ما إذا كان مسار FFmpeg يعمل (دمج DASH على ويندوز/لينكس).
  static const ffmpegReadyPrefsKey = 'desktop_ffmpeg_ready_v1';

  static final _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(minutes: 2),
      receiveTimeout: const Duration(minutes: 30),
      sendTimeout: const Duration(minutes: 2),
    ),
  );

  /// ينفَّذ عند أول إقلاع بعد التثبيت (أو عند فقد الملفات)، ويحدّث [ffmpegReadyPrefsKey].
  static Future<void> ensure() async {
    if (kIsWeb) return;
    if (!Platform.isWindows && !Platform.isLinux) return;

    final prefs = await SharedPreferences.getInstance();

    if (await _ffmpegWorksAfterProbe()) {
      await prefs.setBool(ffmpegReadyPrefsKey, true);
      return;
    }

    clearFfmpegPathCache();
    if (await _toolsDirFfmpegWorks() && await _ffmpegWorksAfterProbe()) {
      await prefs.setBool(ffmpegReadyPrefsKey, true);
      return;
    }

    Map<String, dynamic> map;
    try {
      final raw = await rootBundle
          .loadString('assets/bootstrap/desktop_tools_manifest.json');
      map = json.decode(raw) as Map<String, dynamic>;
    } catch (e, st) {
      Telemetry.instance.recordError(
        'tool_bootstrap.manifest',
        e,
        stackTrace: st,
        context: const {'step': 'load'},
      );
      await prefs.setBool(ffmpegReadyPrefsKey, false);
      return;
    }

    // إصدار مكتفي: لا تنزيل من الإنترنت — الاعتماد على bundled_ffmpeg/ مع CMake أو أصول Flutter.
    if (map['use_remote_bootstrap'] != true) {
      clearFfmpegPathCache();
      final ok = await _ffmpegWorksAfterProbe();
      await prefs.setBool(ffmpegReadyPrefsKey, ok);
      return;
    }

    final key = Platform.isWindows ? 'windows' : 'linux';
    final block = map[key] as Map<String, dynamic>?;
    final url = block?['url'] as String?;
    if (url == null || url.isEmpty) {
      await prefs.setBool(ffmpegReadyPrefsKey, false);
      return;
    }

    final shaRaw = block?['sha256'];
    final wantSha = shaRaw is String && shaRaw.trim().isNotEmpty
        ? shaRaw.trim()
        : null;

    try {
      if (Platform.isWindows) {
        await _installWindowsGplBundle(url, wantSha);
      } else {
        await _installLinuxGplBundle(url, wantSha);
      }
      clearFfmpegPathCache();
      final ok = await _ffmpegWorksAfterProbe();
      await prefs.setBool(ffmpegReadyPrefsKey, ok);
    } catch (e, st) {
      Telemetry.instance.recordError(
        'tool_bootstrap.install',
        e,
        stackTrace: st,
        context: {'url': url},
      );
      await prefs.setBool(ffmpegReadyPrefsKey, false);
    }
  }

  static Future<String> _toolsFfmpegPath() => firstRunToolsFfmpegPath();

  static Future<void> _installWindowsGplBundle(String url, String? wantSha) async {
    final tmp = await getTemporaryDirectory();
    final zipPath = p.join(
      tmp.path,
      'dd_ffmpeg_bootstrap_${DateTime.now().microsecondsSinceEpoch}.zip',
    );
    await _dio.download(url, zipPath);
    if (wantSha != null && wantSha.isNotEmpty) {
      final ok = await _fileMatchesSha256(zipPath, wantSha);
      if (!ok) {
        throw StateError('SHA256 mismatch for downloaded Windows bundle');
      }
    }
    final bytes = await File(zipPath).readAsBytes();
    try {
      await File(zipPath).delete();
    } catch (e, st) {
      debugPrint('Failed to delete temp zip: $e');
      Telemetry.instance.recordError(e, st);
    }

    final outDir = p.join(
      (await getApplicationSupportDirectory()).path,
      'dark_downloader',
      'tools',
      'ffmpeg',
    );
    await Directory(outDir).create(recursive: true);
    final arch = ZipDecoder().decodeBytes(bytes);
    for (final f in arch) {
      if (!f.isFile) continue;
      final n = f.name.replaceAll(r'\', '/');
      if (!n.contains('/bin/')) continue;
      final base = p.basename(n);
      if (base.isEmpty) continue;
      final out = File(p.join(outDir, base));
      await out.writeAsBytes(f.content, flush: true);
    }
    final mainExe = p.join(outDir, 'ffmpeg.exe');
    if (!await File(mainExe).exists()) {
      throw StateError('ffmpeg.exe missing after zip extract');
    }
  }

  static Future<void> _installLinuxGplBundle(String url, String? wantSha) async {
    final tmp = await getTemporaryDirectory();
    final txz = p.join(
      tmp.path,
      'dd_ffmpeg_${DateTime.now().microsecondsSinceEpoch}.tar.xz',
    );
    await _dio.download(url, txz);
    if (wantSha != null && wantSha.isNotEmpty) {
      final ok = await _fileMatchesSha256(txz, wantSha);
      if (!ok) {
        throw StateError('SHA256 mismatch for downloaded Linux bundle');
      }
    }
    final exRoot = p.join(
      tmp.path,
      'dd_ff_extract_${DateTime.now().microsecondsSinceEpoch}',
    );
    await Directory(exRoot).create(recursive: true);
    final tar = await Process.run('tar', ['-xJf', txz, '-C', exRoot]);
    if (tar.exitCode != 0) {
      throw StateError('tar -xJf failed: ${tar.stderr}');
    }
    try {
      await File(txz).delete();
    } catch (e, st) {
      debugPrint('Failed to delete temp tar: $e');
      Telemetry.instance.recordError(e, st);
    }

    String? binPath;
    await for (final e in Directory(exRoot).list(
      recursive: true,
      followLinks: false,
    )) {
      if (e is! File) continue;
      if (p.basename(e.path) != 'ffmpeg') continue;
      if (!e.path.contains('${p.separator}bin${p.separator}') &&
          !e.path.contains('/bin/')) {
        continue;
      }
      binPath = e.path;
      break;
    }
    if (binPath == null) {
      throw StateError('bin/ffmpeg not found in Linux archive');
    }

    final out = await _toolsFfmpegPath();
    await Directory(p.dirname(out)).create(recursive: true);
    await File(binPath).copy(out);
    await Process.run('chmod', ['+x', out]);
    try {
      await Directory(exRoot).delete(recursive: true);
    } catch (e, st) {
      debugPrint('Failed to delete temp extraction root: $e');
      Telemetry.instance.recordError(e, st);
    }
  }

  static Future<bool> _fileMatchesSha256(String filePath, String wantHex) async {
    final digest = await sha256.bind(File(filePath).openRead()).first;
    final got = digest.toString();
    return got.toLowerCase() == wantHex.toLowerCase().trim();
  }

  static Future<bool> _toolsDirFfmpegWorks() async {
    final fp = await _toolsFfmpegPath();
    if (!await File(fp).exists()) return false;
    return _versionOk(fp);
  }

  static Future<bool> _ffmpegWorksAfterProbe() async {
    clearFfmpegPathCache();
    final path = await resolveDesktopFfmpegPath();
    return _versionOk(path);
  }

  static Future<bool> _versionOk(String executable) async {
    try {
      final useShell = Platform.isWindows && p.basename(executable) == executable;
      final r = await Process.run(executable, const ['-version'], runInShell: useShell);
      return r.exitCode == 0;
    } catch (_) {
      return false;
    }
  }
}
