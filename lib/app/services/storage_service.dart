import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart' as path_provider;

/// Centralized service to manage application paths across different platforms.
class StorageService {
  StorageService._();

  static const String _rootFolderName = 'DarkDownloader';

  /// When [path_provider] cannot resolve the OS Downloads folder (rare on Windows),
  /// use the conventional user profile path so files still land in **Downloads**
  /// instead of silently falling back to Documents (where users rarely look).
  static Directory? _desktopDownloadsFallback() {
    if (Platform.isWindows) {
      final profile = Platform.environment['USERPROFILE'];
      if (profile != null && profile.isNotEmpty) {
        return Directory(p.join(profile, 'Downloads'));
      }
    } else if (Platform.isLinux || Platform.isMacOS) {
      final home = Platform.environment['HOME'];
      if (home != null && home.isNotEmpty) {
        return Directory(p.join(home, 'Downloads'));
      }
    }
    return null;
  }

  /// Returns the default downloads directory.
  /// - Android: prefers app-scoped external Downloads (always writable on
  ///   modern Android with scoped storage); public /storage/emulated/0/Download
  ///   only when a legacy-storage manifest allows it.
  /// - iOS: Documents/DarkDownloader
  /// - Windows/Linux/MacOS: Downloads/DarkDownloader
  static Future<Directory> getDownloadsDirectory() async {
    Directory? baseDir;

    if (Platform.isAndroid) {
      // On Android 10+ (SDK 29+) apps cannot freely write to
      // /storage/emulated/0/Download unless they hold MANAGE_EXTERNAL_STORAGE.
      // Using getExternalStorageDirectories(downloads) returns an
      // app-scoped path (e.g. /storage/emulated/0/Android/data/<pkg>/files/Download)
      // which is always writable without any runtime permission.
      try {
        final externalDirs = await path_provider.getExternalStorageDirectories(
          type: path_provider.StorageDirectory.downloads,
        );
        if (externalDirs != null && externalDirs.isNotEmpty) {
          baseDir = externalDirs.first;
        }
      } catch (_) {
        // Some devices throw here; fall through to legacy path.
      }

      // Legacy fallback (only usable with requestLegacyExternalStorage=true
      // on API <= 29). Try to create it; if that fails we drop back to
      // app-private storage below.
      if (baseDir == null) {
        final legacy = Directory('/storage/emulated/0/Download');
        try {
          if (!await legacy.exists()) {
            await legacy.create(recursive: true);
          }
          // Probe write access before committing.
          final probe = File(p.join(legacy.path, '.dd_write_probe'));
          await probe.writeAsString('ok', flush: true);
          await probe.delete();
          baseDir = legacy;
        } catch (_) {
          baseDir = null;
        }
      }
    } else if (Platform.isIOS) {
      baseDir = await path_provider.getApplicationDocumentsDirectory();
    } else {
      // Desktop platforms
      baseDir = await path_provider.getDownloadsDirectory();
      baseDir ??= _desktopDownloadsFallback();
    }

    // Default fallback to application documents if everything else fails
    baseDir ??= await path_provider.getApplicationDocumentsDirectory();

    final finalDir = Directory(p.join(baseDir.path, _rootFolderName));
    if (!await finalDir.exists()) {
      await finalDir.create(recursive: true);
    }
    return finalDir;
  }

  /// Returns a path for temporary files.
  static Future<String> getTempPath(String fileName) async {
    final tempDir = await path_provider.getTemporaryDirectory();
    return p.join(tempDir.path, fileName);
  }

  /// Safely joins directory and filename based on platform separators.
  static String join(String part1, String part2) => p.join(part1, part2);
}
