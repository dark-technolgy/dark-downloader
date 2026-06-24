import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_file/open_file.dart';
import 'package:url_launcher/url_launcher.dart';
import '../config/supabase_config.dart';

class UpdateService {
  static final Dio _dio = Dio();

  static Future<Map<String, dynamic>?> checkForUpdate() async {
    try {
      final info = await PackageInfo.fromPlatform();
      final currentVersion = info.version;

      // Query Supabase remote_config (updated by CI)
      final response = await supabase
          .from('remote_config')
          .select('latest_version, download_url, release_notes')
          .eq('id', 1)
          .maybeSingle();

      if (response != null) {
        final latestVersion = response['latest_version'] as String;
        
        if (_isNewer(latestVersion, currentVersion)) {
          return {
            'version': latestVersion,
            'url': response['download_url'],
            'notes': response['release_notes'],
          };
        }
      }
    } catch (e) {
      debugPrint('Update check failed: $e');
    }
    return null;
  }

  static bool _isNewer(String latest, String current) {
    try {
      List<int> v1 = latest.split('.').map(int.parse).toList();
      List<int> v2 = current.split('.').map(int.parse).toList();
      for (int i = 0; i < 3; i++) {
        if (v1[i] > v2[i]) return true;
        if (v1[i] < v2[i]) return false;
      }
    } catch (_) {}
    return false;
  }

  /// Downloads and installs the update in-app
  static Future<void> downloadAndInstallUpdate({
    required String url,
    required String fileName,
    required Function(double progress) onProgress,
  }) async {
    try {
      final tempDir = await getTemporaryDirectory();
      final savePath = '${tempDir.path}/$fileName';

      await _dio.download(
        url,
        savePath,
        onReceiveProgress: (received, total) {
          if (total != -1) {
            onProgress(received / total);
          }
        },
      );

      // Open the file to start installation
      await OpenFile.open(savePath);
    } catch (e) {
      debugPrint('In-app update failed: $e');
      // Fallback to browser if internal fails
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
      }
    }
  }

  static Future<void> launchUpdateUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }
}
