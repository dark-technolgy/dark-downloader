import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../config/supabase_config.dart';

class UpdateService {
  static Future<Map<String, dynamic>?> checkForUpdate() async {
    try {
      final info = await PackageInfo.fromPlatform();
      final currentVersion = info.version;

      // Query Supabase app_config
      final response = await supabase
          .from('app_config')
          .select('value')
          .eq('key', 'latest_version')
          .maybeSingle();

      if (response != null) {
        final data = response['value'] as Map<String, dynamic>;
        final latestVersion = data['version'] as String;
        
        if (_isNewer(latestVersion, currentVersion)) {
          return data;
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
