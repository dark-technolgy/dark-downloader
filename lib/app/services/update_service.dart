import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../config/supabase_config.dart';

class UpdateService {
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
      // Non-fatal, just log
      debugPrint('Update check failed: $e');
    }
    return null;
  }

  static bool _isNewer(String latest, String current) {
    List<int> v1 = latest.split('.').map(int.parse).toList();
    List<int> v2 = current.split('.').map(int.parse).toList();
    
    for (int i = 0; i < 3; i++) {
      if (v1[i] > v2[i]) return true;
      if (v1[i] < v2[i]) return false;
    }
    return false;
  }

  static Future<void> launchUpdateUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }
}
