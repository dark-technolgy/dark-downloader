import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../src/rust/api/ytdlp_wrapper.dart' as rust_ytdlp;

/// Resolves and configures the yt-dlp fallback binary for the native
/// extractor cascade (Rust → yt-dlp).
///
/// Android is intentionally skipped: yt-dlp is a Python-frozen binary that
/// requires an interpreter (Termux). The native Rust extractors + rule packs
/// keep Android fully functional without it.
///
/// Search order on desktop:
/// 1) Next to `Platform.resolvedExecutable` in `bundled_ytdlp/{windows,linux}/`
///    (CMake bootstrap on clean builds, or manual placement).
/// 2) A copy previously extracted from the Flutter asset bundle under
///    the application-support directory.
/// 3) The Flutter asset bundle itself (`assets/bundled_ytdlp/...`).
/// 4) The system `yt-dlp` on PATH.
///
/// Call [ensure] once during app bootstrap. It is safe to call more than once
/// (subsequent calls become no-ops once configured).
class YtdlpBootstrap {
  YtdlpBootstrap._();

  static bool _initialized = false;

  /// Resolves the yt-dlp binary and registers it with the Rust side.
  /// Never throws; failures leave the Rust cascade in "native-only" mode.
  static Future<void> ensure() async {
    if (_initialized) return;
    _initialized = true;

    try {
      // Android has no yt-dlp story that is worth the APK bloat; the native
      // extractors + optional rule packs cover it entirely.
      if (Platform.isAndroid || Platform.isIOS) return;

      final resolved = await _resolveDesktopPath();
      if (resolved == null || resolved.isEmpty) return;

      rust_ytdlp.setYtdlpBinaryPath(path: resolved);
    } catch (_) {
      // Silent — this is a *fallback* installer; a failure here must never
      // block the app.
    }
  }

  /// Test hook — forces a re-probe on the next [ensure] call.
  static void resetForTests() {
    _initialized = false;
  }

  // ------------------------------------------------------------------
  // Resolution helpers
  // ------------------------------------------------------------------

  static Future<String?> _resolveDesktopPath() async {
    if (!Platform.isWindows && !Platform.isLinux && !Platform.isMacOS) {
      return null;
    }

    final binName = Platform.isWindows ? 'yt-dlp.exe' : 'yt-dlp';

    // 1) Beside the installed executable (Inno Setup drops CMake outputs here)
    try {
      final dir = p.dirname(Platform.resolvedExecutable);
      final subdir = Platform.isWindows
          ? 'windows'
          : (Platform.isLinux ? 'linux' : 'macos');
      final candidate = p.join(dir, 'bundled_ytdlp', subdir, binName);
      if (await File(candidate).exists()) {
        await _ensureExecutable(candidate);
        return candidate;
      }
    } catch (_) {}

    // 2) Previously extracted from asset bundle
    try {
      final sup = await getApplicationSupportDirectory();
      final cached = p.join(
        sup.path,
        'dark_downloader',
        'tools',
        'ytdlp',
        binName,
      );
      if (await File(cached).exists()) {
        await _ensureExecutable(cached);
        return cached;
      }
    } catch (_) {}

    // 3) Materialize from asset bundle (offline install)
    final fromAssets = await _materializeFromAssets();
    if (fromAssets != null) {
      await _ensureExecutable(fromAssets);
      return fromAssets;
    }

    // 4) System yt-dlp on PATH
    final onPath = await _whichSystemYtdlp();
    if (onPath != null) return onPath;

    return null;
  }

  static Future<String?> _materializeFromAssets() async {
    if (!Platform.isWindows && !Platform.isLinux && !Platform.isMacOS) {
      return null;
    }

    final assetKey = Platform.isWindows
        ? 'assets/bundled_ytdlp/windows/yt-dlp.exe'
        : Platform.isLinux
        ? 'assets/bundled_ytdlp/linux/yt-dlp'
        : 'assets/bundled_ytdlp/macos/yt-dlp';

    try {
      final data = await rootBundle.load(assetKey);
      // yt-dlp is a substantial binary; anything under ~500 KB is a placeholder.
      if (data.lengthInBytes < 500 * 1024) return null;

      final bytes = data.buffer.asUint8List(
        data.offsetInBytes,
        data.lengthInBytes,
      );
      final outDir = p.join(
        (await getApplicationSupportDirectory()).path,
        'dark_downloader',
        'tools',
        'ytdlp',
      );
      await Directory(outDir).create(recursive: true);
      final binName = Platform.isWindows ? 'yt-dlp.exe' : 'yt-dlp';
      final outPath = p.join(outDir, binName);
      await File(outPath).writeAsBytes(bytes, flush: true);
      return outPath;
    } catch (_) {
      return null;
    }
  }

  static Future<String?> _whichSystemYtdlp() async {
    try {
      if (Platform.isWindows) {
        final r = await Process.run('where', ['yt-dlp']);
        if (r.exitCode == 0) {
          final line = (r.stdout as String)
              .split(RegExp(r'\r?\n'))
              .firstWhere((l) => l.trim().isNotEmpty, orElse: () => '');
          if (line.isNotEmpty && await File(line.trim()).exists()) {
            return line.trim();
          }
        }
      } else {
        final r = await Process.run('which', ['yt-dlp']);
        if (r.exitCode == 0) {
          final line = (r.stdout as String).trim();
          if (line.isNotEmpty && await File(line).exists()) return line;
        }
      }
    } catch (_) {}
    return null;
  }

  static Future<void> _ensureExecutable(String path) async {
    if (Platform.isWindows) return;
    try {
      await Process.run('chmod', ['+x', path]);
    } catch (_) {}
  }
}
