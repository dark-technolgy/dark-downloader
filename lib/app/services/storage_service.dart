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
  /// - Android: /storage/emulated/0/Download/DarkDownloader
  /// - iOS: Documents/DarkDownloader
  /// - Windows/Linux/MacOS: Downloads/DarkDownloader
  static Future<Directory> getDownloadsDirectory() async {
    Directory? baseDir;

    if (Platform.isAndroid) {
      // Android standard Download folder
      baseDir = Directory('/storage/emulated/0/Download');
      if (!await baseDir.exists()) {
        // Fallback to external storage if standard path fails
        final externalDirs = await path_provider.getExternalStorageDirectories(
          type: path_provider.StorageDirectory.downloads,
        );
        if (externalDirs != null && externalDirs.isNotEmpty) {
          baseDir = externalDirs.first;
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
