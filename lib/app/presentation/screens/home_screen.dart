import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../config/localization.dart';
import '../../providers/incoming_link_provider.dart';
import '../../providers/locale_provider.dart';
import '../../utils/incoming_link_utils.dart';
import '../../services/update_service.dart';
import '../../services/tool_bootstrapper.dart';
import 'download_history_screen.dart';
import 'profile_screen.dart';
import 'toolkit_screen.dart';
import 'vault_screen.dart';
import 'home_tab.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  int _currentIndex = 0;

  /// null = لم يُحمَّل بعد؛ false = يحتاج إعداد FFmpeg (ويندوز/لينكس فقط).
  bool? _desktopEncoderReady;
  bool _desktopEncoderBannerDismissed = false;
  bool _desktopEncoderRetryBusy = false;

  /// [IndexedStack] builds every child — [DownloadHistoryScreen] and
  /// [ProfileScreen] used to mount on cold start (sidebar effects like
  /// [ProfileScreen] used to mount on cold start (sidebar effects). Defer them until the user opens those tabs.

  bool _historyUiEverOpened = false;
  bool _profileUiEverOpened = false;
  bool _toolkitUiEverOpened = false;
  bool _vaultUiEverOpened = false;

  Widget? _historyTab;
  Widget? _profileTab;
  Widget? _toolkitTab;
  Widget? _vaultTab;

  Widget _historySlot() {
    if (!_historyUiEverOpened) return const SizedBox.shrink();
    return _historyTab ??= const DownloadHistoryScreen();
  }

  Widget _toolkitSlot() {
    if (!_toolkitUiEverOpened) return const SizedBox.shrink();
    return _toolkitTab ??= const ToolkitScreen();
  }

  Widget _vaultSlot() {
    if (!_vaultUiEverOpened) return const SizedBox.shrink();
    return _vaultTab ??= const VaultScreen();
  }

  Widget _profileSlot() {
    if (!_profileUiEverOpened) return const SizedBox.shrink();
    return _profileTab ??= const ProfileScreen();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadDesktopEncoderStatus();
      _performUpdateCheck();
    });
  }

  Future<void> _performUpdateCheck() async {
    final update = await UpdateService.checkForUpdate();
    if (update != null && mounted) {
      _showUpdateDialog(update);
    }
  }

  void _showUpdateDialog(Map<String, dynamic> update) {
    double downloadProgress = 0;
    bool isDownloading = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF0A0A0A),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
            side: const BorderSide(color: Color(0xFF00A3FF), width: 0.5),
          ),
          title: Row(
            children: [
              Icon(
                isDownloading
                    ? Icons.downloading_rounded
                    : Icons.system_update_rounded,
                color: const Color(0xFF00A3FF),
              ),
              const SizedBox(width: 12),
              Text(
                isDownloading ? "جارٍ التحديث..." : "تحديث جديد متاح! 🚀",
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "إصدار جديد: ${update['version']}",
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
              if (!isDownloading)
                Text(
                  update['notes'] ?? "",
                  style: const TextStyle(color: Colors.grey, fontSize: 13),
                ),
              if (isDownloading) ...[
                const SizedBox(height: 8),
                LinearProgressIndicator(
                  value: downloadProgress >= 0 ? downloadProgress : null,
                  backgroundColor: Colors.white10,
                  valueColor: const AlwaysStoppedAnimation<Color>(
                    Color(0xFF00A3FF),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  downloadProgress >= 0
                      ? "${(downloadProgress * 100).toStringAsFixed(0)}%"
                      : "جاري التحميل...",
                  style: const TextStyle(
                    color: Color(0xFF00A3FF),
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ],
          ),
          actions: [
            if (!isDownloading)
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text(
                  "لاحقاً",
                  style: TextStyle(color: Colors.grey),
                ),
              ),
            if (!isDownloading)
              ElevatedButton(
                onPressed: () async {
                  setDialogState(() => isDownloading = true);
                  // Windows ships as an Inno Setup .exe installer (no MSIX, no cert).
                  final extension = Platform.isAndroid
                      ? 'apk'
                      : (Platform.isWindows ? 'exe' : 'tar.gz');
                  final fileName =
                      "Dark-Downloader-${update['version']}.$extension";

                  await UpdateService.downloadAndInstallUpdate(
                    url: update['url'],
                    fileName: fileName,
                    onProgress: (p) =>
                        setDialogState(() => downloadProgress = p),
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00A3FF),
                  foregroundColor: Colors.white,
                ),
                child: const Text("تحديث الآن"),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _loadDesktopEncoderStatus() async {
    if (kIsWeb || (!Platform.isWindows && !Platform.isLinux)) return;
    final p = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _desktopEncoderReady =
          p.getBool(ToolBootstrapper.ffmpegReadyPrefsKey) ?? false;
    });
  }

  Future<void> _retryDesktopEncoderBootstrap() async {
    setState(() => _desktopEncoderRetryBusy = true);
    try {
      await ToolBootstrapper.ensure();
    } finally {
      if (mounted) {
        setState(() => _desktopEncoderRetryBusy = false);
        await _loadDesktopEncoderStatus();
      }
    }
  }

  Future<void> _handleIncomingLink(String raw) async {
    final normalized = extractFirstDownloadTarget(raw);
    if (normalized == null) return;

    setState(() => _currentIndex = 0);
    ref.read(pendingExtractorUrlProvider.notifier).set(normalized);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<String?>(incomingRawLinkProvider, (prev, next) {
      if (next == null || next.isEmpty) return;
      ref.read(incomingRawLinkProvider.notifier).clear();
      final payload = next;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _handleIncomingLink(payload);
      });
    });

    final locale = ref.watch(localeProvider);
    final t = AppLocalization.translate;

    return Scaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (kIsWeb)
            ColoredBox(
              color: Theme.of(
                context,
              ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.9),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.info_outline,
                      size: 20,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            t('platform_banner_web_title', locale),
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            t('platform_banner_web_body', locale),
                            style: const TextStyle(fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          if (!kIsWeb &&
              (Platform.isWindows || Platform.isLinux) &&
              _desktopEncoderReady == false &&
              !_desktopEncoderBannerDismissed)
            ColoredBox(
              color: Theme.of(
                context,
              ).colorScheme.errorContainer.withValues(alpha: 0.45),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.warning_amber_rounded,
                      size: 22,
                      color: Theme.of(context).colorScheme.error,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            t('platform_banner_desktop_encoder_title', locale),
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            t('platform_banner_desktop_encoder_body', locale),
                            style: const TextStyle(fontSize: 12),
                          ),
                          const SizedBox(height: 8),
                          TextButton(
                            onPressed: _desktopEncoderRetryBusy
                                ? null
                                : _retryDesktopEncoderBootstrap,
                            child: _desktopEncoderRetryBusy
                                ? SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.primary,
                                    ),
                                  )
                                : Text(
                                    t(
                                      'platform_banner_desktop_encoder_retry',
                                      locale,
                                    ),
                                  ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, size: 20),
                      onPressed: () =>
                          setState(() => _desktopEncoderBannerDismissed = true),
                      tooltip: MaterialLocalizations.of(
                        context,
                      ).closeButtonTooltip,
                    ),
                  ],
                ),
              ),
            ),
          Expanded(
            child: IndexedStack(
              index: _currentIndex,
              children: [
                const HomeTab(),
                _historySlot(),
                _toolkitSlot(),
                _vaultSlot(),
                _profileSlot(),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (i) => setState(() {
          _currentIndex = i;
          if (i == 1) _historyUiEverOpened = true;
          if (i == 2) _toolkitUiEverOpened = true;
          if (i == 3) _vaultUiEverOpened = true;
          if (i == 4) _profileUiEverOpened = true;
        }),
        elevation: 8,
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.home_outlined),
            selectedIcon: const Icon(Icons.home_rounded),
            label: t('home', locale),
          ),
          NavigationDestination(
            icon: const Icon(Icons.history_outlined),
            selectedIcon: const Icon(Icons.history_rounded),
            label: t('history', locale),
          ),

          NavigationDestination(
            icon: const Icon(Icons.build_circle_outlined),
            selectedIcon: const Icon(Icons.build_circle_rounded),
            label: 'الأدوات',
          ),
          NavigationDestination(
            icon: const Icon(Icons.security_outlined),
            selectedIcon: const Icon(Icons.security_rounded),
            label: 'الخزنة',
          ),
          NavigationDestination(
            icon: const Icon(Icons.person_outline_rounded),
            selectedIcon: const Icon(Icons.person_rounded),
            label: t('profile', locale),
          ),
        ],
      ),
    );
  }
}
