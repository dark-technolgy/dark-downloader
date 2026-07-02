import 'dart:io';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../providers/remote_config_provider.dart';
import '../../services/update_service.dart';

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
    double downloadProgress = 0;
    bool isDownloading = false;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      showDialog(
        context: context,
        barrierDismissible: !force,
        builder: (context) => StatefulBuilder(
          builder: (context, setDialogState) => PopScope(
            canPop: !force && !isDownloading,
            child: AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              title: Row(
                children: [
                  Icon(
                    isDownloading ? Icons.cloud_download : Icons.update,
                    color: const Color(0xFF00A3FF),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      isDownloading
                          ? "جاري التحميل..."
                          : (force ? "تحديث إجباري" : "تحديث جديد متاح"),
                    ),
                  ),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (!isDownloading) ...[
                    Text(
                      force
                          ? "يجب تحديث التطبيق للمتابعة لضمان الأمان والاستقرار."
                          : "يتوفر إصدار جديد من التطبيق مع ميزات وتحسينات جديدة.",
                    ),
                    if (widget.config.releaseNotes != null) ...[
                      const SizedBox(height: 16),
                      const Text(
                        "ما الجديد:",
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                      Text(
                        widget.config.releaseNotes!,
                        style: const TextStyle(fontSize: 12),
                      ),
                    ],
                  ] else ...[
                    const Text(
                      "يتم الآن تحميل التحديث الجديد، يرجى الانتظار...",
                    ),
                    const SizedBox(height: 20),
                    LinearProgressIndicator(
                      value: downloadProgress,
                      backgroundColor: Colors.grey.shade200,
                      color: const Color(0xFF00A3FF),
                      minHeight: 8,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    const SizedBox(height: 10),
                    Center(
                      child: Text(
                        "${(downloadProgress * 100).toStringAsFixed(0)}%",
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF00A3FF),
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  Text(
                    "الإصدار: ${_currentVersion ?? '...'}  →  ${widget.config.latestVersion}",
                    style: const TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                ],
              ),
              actions: [
                if (!force && !isDownloading)
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text("لاحقاً"),
                  ),
                if (!isDownloading)
                  ElevatedButton.icon(
                    onPressed: () async {
                      final url = widget.config.downloadUrl;
                      if (url == null) return;

                      setDialogState(() => isDownloading = true);

                      try {
                        final fileName = Platform.isAndroid
                            ? "DarkDownloader_v${widget.config.latestVersion}.apk"
                            : "DarkDownloader_v${widget.config.latestVersion}.exe";

                        await UpdateService.downloadAndInstallUpdate(
                          url: url,
                          fileName: fileName,
                          onProgress: (p) {
                            setDialogState(() => downloadProgress = p);
                          },
                        );
                      } catch (e) {
                        setDialogState(() => isDownloading = false);
                        // Fallback to browser
                        launchUrl(
                          Uri.parse(url),
                          mode: LaunchMode.externalApplication,
                        );
                      }
                    },
                    icon: const Icon(Icons.download, size: 18),
                    label: const Text("تحديث الآن"),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF00A3FF),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
              ],
            ),
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
