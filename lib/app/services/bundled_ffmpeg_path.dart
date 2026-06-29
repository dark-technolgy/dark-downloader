import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Resolves the FFmpeg binary for all platforms.
///
/// Order:
/// 1) Android: nativeLibDir (libffmpeg.so in jniLibs)
/// 2) Android/iOS: extracted binary under application support
/// 3) Next to [Platform.resolvedExecutable] (CMake copies [bundled_ffmpeg/] here)
/// 4) [embed_*.zip] inside [assets/bundled_ffmpeg] — فك أوفلاين (من دون إنترنت)
/// 5) نسخة سابقة تحت application support (أدوات من جلسة سابقة)
/// 6) ملفات ثنائية مفردة في assets (ffmpeg.exe / ffmpeg)
/// 7) `ffmpeg` on PATH
/// 8) Fallback: `"ffmpeg"`
Future<String> resolveDesktopFfmpegPath() async {
  final c = _cachedFfmpegPath;
  if (c != null) {
    if (c == 'ffmpeg') return c;
    try {
      if (await File(c).exists()) return c;
    } catch (_) {}
    _cachedFfmpegPath = null;
  }

  // --- Mobile: Android / iOS ---
  if (Platform.isAndroid || Platform.isIOS) {
    final mobilePath = await _resolveMobileFfmpegPath();
    if (mobilePath != null) {
      _cachedFfmpegPath = mobilePath;
      return mobilePath;
    }
    // Fallback: 'ffmpeg' (will fail but gives clear error from Rust)
    _cachedFfmpegPath = 'ffmpeg';
    return 'ffmpeg';
  }

  // --- Desktop: Windows / Linux / macOS ---

  // 1) Side-by-side with the app (release installs / CMake install)
  final fromInstall = _pathBesideExecutable();
  if (fromInstall != null) {
    if (Platform.isWindows) {
      if (await File(fromInstall).exists()) {
        _cachedFfmpegPath = fromInstall;
        return fromInstall;
      }
    } else if (Platform.isLinux) {
      final f = File(fromInstall);
      if (await f.exists()) {
        await _ensureExecutable(f.path);
        _cachedFfmpegPath = fromInstall;
        return fromInstall;
      }
    }
  }

  // 2) اختياري: أرشيف BtbN كامل داخل الـ assets (وضع أوفلاين 100٪)
  final fromEmbZip = await _materializeFromEmbeddedZip();
  if (fromEmbZip != null) {
    if (Platform.isLinux) {
      await _ensureExecutable(fromEmbZip);
    }
    _cachedFfmpegPath = fromEmbZip;
    return fromEmbZip;
  }

  // 3) نسخ مُفكوكة مسبقاً (أو باتش قديم) في مجلد الدعم
  final fromFirstRun = await _pathFirstRunTools();
  if (fromFirstRun != null) {
    if (Platform.isLinux) {
      await _ensureExecutable(fromFirstRun);
    }
    _cachedFfmpegPath = fromFirstRun;
    return fromFirstRun;
  }

  // 4) أصول مفردة
  final fromBundle = await _materializeFromAssetBundle();
  if (fromBundle != null) {
    _cachedFfmpegPath = fromBundle;
    return fromBundle;
  }

  // 5) أي ffmpeg على PATH — الإنتاج أيضاً (يقلّل WinError 2 إذا غاب مجلد ffmpeg بجانب exe)
  final w = await _whichSystemFfmpeg();
  if (w != null) {
    _cachedFfmpegPath = w;
    return w;
  }

  _cachedFfmpegPath = 'ffmpeg';
  return 'ffmpeg';
}

/// Resolves ffmpeg on Android/iOS.
///
/// Search order:
/// 1) Android: nativeLibDir → libffmpeg.so  (bundled via jniLibs)
/// 2) Previously extracted binary under app support
Future<String?> _resolveMobileFfmpegPath() async {
  if (Platform.isAndroid) {
    // Check application support for previously extracted ffmpeg
    try {
      final sup = await getApplicationSupportDirectory();
      final extracted = p.join(sup.path, 'dark_downloader', 'tools', 'ffmpeg', 'ffmpeg');
      if (await File(extracted).exists()) {
        return extracted;
      }
    } catch (_) {}

    // Try to find ffmpeg in the native libs directory
    // Android apps can load native libs from the app's nativeLibraryDir
    try {
      final sup = await getApplicationSupportDirectory();
      // nativeLibraryDir is typically /data/app/.../lib/<abi>/
      // We can resolve it relative to the app's data directory
      final appDir = sup.parent; // applicationSupportDir parent = app data root
      final nativeLibDirs = [
        p.join(appDir.path, 'lib'),
        '/data/data/com.dark.dark_downloader/lib',
      ];
      for (final libDir in nativeLibDirs) {
        final ffmpegSo = p.join(libDir, 'libffmpeg.so');
        if (await File(ffmpegSo).exists()) {
          await _ensureExecutable(ffmpegSo);
          return ffmpegSo;
        }
      }
    } catch (_) {}
  }

  if (Platform.isIOS) {
    // On iOS, bundled binaries are in the app Frameworks directory
    try {
      final sup = await getApplicationSupportDirectory();
      final extracted = p.join(sup.path, 'dark_downloader', 'tools', 'ffmpeg', 'ffmpeg');
      if (await File(extracted).exists()) {
        return extracted;
      }
    } catch (_) {}
  }

  return null;
}

/// Same layout as [ToolBootstrapper] on Win/Linux.
Future<String> firstRunToolsFfmpegPath() async {
  final sup = await getApplicationSupportDirectory();
  final name = Platform.isWindows ? 'ffmpeg.exe' : 'ffmpeg';
  return p.join(sup.path, 'dark_downloader', 'tools', 'ffmpeg', name);
}

Future<String?> _pathFirstRunTools() async {
  if (!Platform.isWindows && !Platform.isLinux) return null;
  final path = await firstRunToolsFfmpegPath();
  if (await File(path).exists()) return path;
  return null;
}

String? _cachedFfmpegPath;

/// Call after tests or to force re-probe.
void clearFfmpegPathCache() {
  _cachedFfmpegPath = null;
}

String? _pathBesideExecutable() {
  if (!Platform.isWindows && !Platform.isLinux) return null;
  try {
    final dir = p.dirname(Platform.resolvedExecutable);
    if (Platform.isWindows) {
      final a = p.join(dir, 'ffmpeg', 'ffmpeg.exe');
      return a;
    }
    return p.join(dir, 'ffmpeg', 'ffmpeg');
  } catch (_) {
    return null;
  }
}

/// أرشيف جاهز داخل [assets/bundled_ffmpeg]: يفك مرة لمجلد دائم (أوفلاين).
/// ويندوز: أنشئ من مجلد `bin` لبناء BtbN (نفس `scripts/fetch_ffmpeg_bundles`) ثم
/// `Compress-Archive` كـ [embed_windows.zip]. لينُكس: `ffmpeg` داخل `bin/` أو جذر الأرشيف.
Future<String?> _materializeFromEmbeddedZip() async {
  if (!Platform.isWindows && !Platform.isLinux) return null;
  final key = Platform.isWindows
      ? 'assets/bundled_ffmpeg/embed_windows.zip'
      : 'assets/bundled_ffmpeg/embed_linux.zip';
  try {
    final data = await rootBundle.load(key);
    if (data.lengthInBytes < 5000) return null;
    final bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
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
      final base = p.basename(n);
      if (base.isEmpty) continue;
      final inBin = n.contains('/bin/');
      final isDll = base.toLowerCase().endsWith('.dll');
      final isSo = base.contains('.so');
      final isFfmpeg = base == 'ffmpeg' || base == 'ffmpeg.exe';
      if (!inBin && !isDll && !isSo && !isFfmpeg) continue;
      await File(p.join(outDir, base)).writeAsBytes(f.content, flush: true);
    }
    final main = p.join(
      outDir,
      Platform.isWindows ? 'ffmpeg.exe' : 'ffmpeg',
    );
    if (!await File(main).exists()) return null;
    if (Platform.isLinux) {
      await _ensureExecutable(main);
    }
    return main;
  } catch (_) {
    return null;
  }
}

Future<String?> _materializeFromAssetBundle() async {
  if (Platform.isWindows) {
    // On Windows, the asset is already on disk in the flutter_assets folder.
    // Loading a 194MB file via rootBundle.load causes OutOfMemory exceptions.
    final exeDir = p.dirname(Platform.resolvedExecutable);
    final directAssetPath = p.join(exeDir, 'data', 'flutter_assets', 'assets', 'bundled_ffmpeg', 'windows', 'ffmpeg.exe');
    if (await File(directAssetPath).exists()) {
      return directAssetPath;
    }
    // Fallback if not found (e.g. running tests)
    return _tryExtract('assets/bundled_ffmpeg/windows/ffmpeg.exe', 'ffmpeg.exe');
  }
  if (Platform.isLinux) {
    final exeDir = p.dirname(Platform.resolvedExecutable);
    final directAssetPath = p.join(exeDir, 'data', 'flutter_assets', 'assets', 'bundled_ffmpeg', 'linux', 'ffmpeg');
    if (await File(directAssetPath).exists()) {
      return directAssetPath;
    }
    return _tryExtract('assets/bundled_ffmpeg/linux/ffmpeg', 'ffmpeg');
  }
  if (Platform.isMacOS) {
    final exeDir = p.dirname(Platform.resolvedExecutable);
    // MacOS structure: Contents/MacOS/App -> Contents/Frameworks/App.framework/Resources/flutter_assets/...
    final directAssetPath = p.join(exeDir, '..', 'Frameworks', 'App.framework', 'Resources', 'flutter_assets', 'assets', 'bundled_ffmpeg', 'macos', 'ffmpeg');
    if (await File(directAssetPath).exists()) {
      return directAssetPath;
    }
    return _tryExtract('assets/bundled_ffmpeg/macos/ffmpeg', 'ffmpeg');
  }
  return null;
}

Future<String?> _tryExtract(String assetKey, String outName) async {
  try {
    final data = await rootBundle.load(assetKey);
    if (data.lengthInBytes < 10000) return null; // not a real binary

    final support = await getApplicationSupportDirectory();
    final outDir = p.join(support.path, 'dark_downloader', 'internal_ffmpeg');
    final out = File(p.join(outDir, outName));
    await outDirRecursive(outDir);
    if (!await out.exists() || await out.length() != data.lengthInBytes) {
      await out.writeAsBytes(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        flush: true,
      );
    }
    if (Platform.isLinux) {
      await _ensureExecutable(out.path);
    }
    return out.path;
  } catch (_) {
    return null;
  }
}

Future<void> outDirRecursive(String path) async {
  final d = Directory(path);
  if (!await d.exists()) {
    await d.create(recursive: true);
  }
}

Future<void> _ensureExecutable(String filePath) async {
  try {
    await Process.run('chmod', ['+x', filePath]);
  } catch (_) {}
}

Future<String?> _whichSystemFfmpeg() async {
  if (Platform.isWindows) {
    try {
      final r = await Process.run('where', ['ffmpeg'], runInShell: true);
      if (r.exitCode == 0) {
        final line = (r.stdout as String).split('\n').first.trim();
        if (line.isNotEmpty) return line;
      }
    } catch (_) {}
  } else {
    try {
      final r = await Process.run('which', const ['ffmpeg']);
      if (r.exitCode == 0) {
        return (r.stdout as String).trim();
      }
    } catch (_) {}
  }
  return null;
}
