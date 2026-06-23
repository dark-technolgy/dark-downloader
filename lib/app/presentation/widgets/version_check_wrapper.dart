import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../providers/remote_config_provider.dart';

class VersionCheckWrapper extends StatefulWidget {
  final RemoteConfigState config;
  final Widget child;

  const VersionCheckWrapper({
    super.key,
    required this.config,
    required this.child,
  });

  @override
  State<VersionCheckWrapper> createState() => _VersionCheckWrapperState();
}

class _VersionCheckWrapperState extends State<VersionCheckWrapper> {
  bool _checked = false;

  @override
  void initState() {
    super.initState();
    _checkVersion();
  }

  Future<void> _checkVersion() async {
    if (_checked) return;
    final packageInfo = await PackageInfo.fromPlatform();
    final currentVersion = packageInfo.version;
    _currentVersion = currentVersion;

    if (_isVersionLower(currentVersion, widget.config.minAppVersion)) {
      _showUpdateDialog(force: true);
    } else if (_isVersionLower(currentVersion, widget.config.latestVersion)) {
      _showUpdateDialog(force: false);
    }
    _checked = true;
  }

  bool _isVersionLower(String current, String target) {
    try {
      final currentParts = current.split('.').map(int.parse).toList();
      final targetParts = target.split('.').map(int.parse).toList();

      for (var i = 0; i < 3; i++) {
        final c = currentParts.length > i ? currentParts[i] : 0;
        final t = targetParts.length > i ? targetParts[i] : 0;
        if (c < t) return true;
        if (c > t) return false;
      }
    } catch (_) {}
    return false;
  }

  void _showUpdateDialog({required bool force}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      showDialog(
        context: context,
        barrierDismissible: !force,
        builder: (context) => PopScope(
          canPop: !force,
          child: AlertDialog(
            title: Row(
              children: [
                const Icon(Icons.update, color: Color(0xFF00A3FF)),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(force ? "تحديث إجباري" : "تحديث جديد متاح"),
                ),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  force
                      ? "يجب تحديث التطبيق للمتابعة لضمان الأمان والاستقرار."
                      : "يتوفر إصدار جديد من التطبيق مع ميزات وتحسينات جديدة.",
                ),
                if (widget.config.releaseNotes != null) ...[
                  const SizedBox(height: 16),
                  const Text(
                    "ما الجديد:",
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Text(widget.config.releaseNotes!),
                ],
                const SizedBox(height: 16),
                Text(
                  "الإصدار الحالي: ${_currentVersion ?? '...'}  →  ${widget.config.latestVersion}",
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
            actions: [
              if (!force)
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text("لاحقاً"),
                ),
              ElevatedButton.icon(
                onPressed: () {
                  final url =
                      widget.config.downloadUrl ?? 'https://keenx.net/#apps';
                  launchUrl(
                    Uri.parse(url),
                    mode: LaunchMode.externalApplication,
                  );
                },
                icon: const Icon(Icons.download, size: 18),
                label: const Text("تحديث الآن"),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00A3FF),
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
        ),
      );
    });
  }

  String? _currentVersion;

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}
