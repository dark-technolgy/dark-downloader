import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/breakpoints.dart';
import '../../config/localization.dart';
import '../../config/platform_home_urls.dart';
import '../../providers/download_manager_provider.dart';
import '../../providers/extractor_provider.dart';
import '../../providers/incoming_link_provider.dart';
import '../../providers/locale_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../utils/incoming_link_utils.dart';
import '../widgets/responsive_scaffold.dart';

import 'advanced_download_screen.dart';
import 'playlist_screen.dart';
import 'browser_screen.dart';

class HomeTab extends ConsumerStatefulWidget {
  const HomeTab({super.key});

  @override
  ConsumerState<HomeTab> createState() => HomeTabState();
}

class HomeTabState extends ConsumerState<HomeTab> with WidgetsBindingObserver {
  final _urlController = TextEditingController();
  final _scrollController = ScrollController();
  String? _suggestedUrl;


  static const _platforms = [
    {
      'key': 'platform_youtube',
      'icon': Icons.play_circle_fill_rounded,
      'color': Color(0xFFFF0000),
    },
    {
      'key': 'platform_tiktok',
      'icon': Icons.music_note_rounded,
      'color': Color(0xFF010101),
    },
    {
      'key': 'platform_instagram',
      'icon': Icons.camera_alt_rounded,
      'color': Color(0xFFE1306C),
    },
    {
      'key': 'platform_twitter',
      'icon': Icons.tag_rounded,
      'color': Color(0xFF1DA1F2),
    },
    {
      'key': 'platform_facebook',
      'icon': Icons.facebook_rounded,
      'color': Color(0xFF1877F2),
    },
    {
      'key': 'platform_vimeo',
      'icon': Icons.videocam_rounded,
      'color': Color(0xFF1AB7EA),
    },
    {
      'key': 'platform_dailymotion',
      'icon': Icons.ondemand_video_rounded,
      'color': Color(0xFF0066FF),
    },
    {
      'key': 'platform_soundcloud',
      'icon': Icons.cloud_rounded,
      'color': Color(0xFFFF5500),
    },
    {
      'key': 'platform_reddit',
      'icon': Icons.reddit_rounded,
      'color': Color(0xFFFF4500),
    },
    {
      'key': 'platform_twitch',
      'icon': Icons.live_tv_rounded,
      'color': Color(0xFF9147FF),
    },
    {
      'key': 'platform_pinterest',
      'icon': Icons.push_pin_rounded,
      'color': Color(0xFFE60023),
    },
    {
      'key': 'platform_rumble',
      'icon': Icons.video_library_rounded,
      'color': Color(0xFF85C742),
    },
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkClipboard();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _urlController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkClipboard();
    }
  }

  Future<void> _checkClipboard() async {
    if (kIsWeb) return;
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      final text = data?.text?.trim();
      if (text != null && text.isNotEmpty) {
        final normalized = extractFirstDownloadTarget(text);
        if (normalized != null && normalized != _urlController.text.trim()) {
          setState(() => _suggestedUrl = normalized);
        }
      }
    } catch (_) {}
  }

  Future<void> _useSuggested() async {
    if (_suggestedUrl != null) {
      _urlController.text = _suggestedUrl!;
      setState(() => _suggestedUrl = null);
      await _analyze();
    }
  }

  Future<void> _analyze() async {
    final url = _urlController.text.trim();
    if (url.isEmpty) return;
    FocusScope.of(context).unfocus();
    await ref
        .read(extractorProvider.notifier)
        .extractVideo(url);

    final state = ref.read(extractorProvider);
    if (state.playlist != null && mounted) {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => PlaylistScreen(playlist: state.playlist!),
        ),
      );
    } else if (state.video != null && mounted) {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => AdvancedDownloadScreen(
            video: state.video!,
            streams: state.streams,
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<String?>(pendingExtractorUrlProvider, (prev, next) {
      if (next == null || next.isEmpty) return;
      ref.read(pendingExtractorUrlProvider.notifier).set(null);
      final url = next;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        _urlController.text = url;
        setState(() {});
        await ref
            .read(extractorProvider.notifier)
            .extractVideo(url);

        if (!context.mounted) return;
        final state = ref.read(extractorProvider);
        if (state.video != null) {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => AdvancedDownloadScreen(
                video: state.video!,
                streams: state.streams,
              ),
            ),
          );
        }
      });
    });

    final locale = ref.watch(localeProvider);
    const t = AppLocalization.translate;
    final extractState = ref.watch(extractorProvider);
    final downloadState = ref.watch(downloadManagerProvider);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      body: CustomScrollView(
        controller: _scrollController,
        slivers: [
          // ─── AppBar ───
          SliverAppBar(
            expandedHeight: 120,
            floating: true,
            snap: true,
            pinned: false,
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      colorScheme.primary,
                      colorScheme.primary.withValues(alpha: 0.7),
                    ],
                  ),
                ),
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 12,
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            Icons.download_rounded,
                            color: Colors.white,
                            size: 22,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Row(
                                children: [
                                  Text(
                                    t('app_name', locale),
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                              Text(
                                t('welcome_back', locale),
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.85),
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                        // زر تغيير اللغة
                        GestureDetector(
                          onTap: () =>
                              ref.read(localeProvider.notifier).toggle(),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              locale.languageCode == 'ar'
                                  ? t('ui_lang_en', locale)
                                  : t('ui_lang_ar', locale),
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),

          SliverToBoxAdapter(
            child: ReadableWidthContainer(
              padding: context.pageInsets,
              child: ResponsiveTwoColumn(
                stackedScrollable: false,
                primaryFlex: 6,
                secondaryFlex: 4,
                primary: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                  // ─── رابط مقترح (Smart Paste) ───
                  if (_suggestedUrl != null)
                    Semantics(
                      label: '${AppLocalization.translate('suggested_link_title', locale)} $_suggestedUrl',
                      child: Padding(

                      padding: const EdgeInsets.only(bottom: 16),
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: colorScheme.primary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: colorScheme.primary.withValues(alpha: 0.2),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.auto_fix_high_rounded,
                              color: colorScheme.primary,
                              size: 20,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    AppLocalization.translate(
                                      'suggested_link_title',
                                      locale,
                                    ),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                    ),
                                  ),
                                  Text(
                                    _suggestedUrl!,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: colorScheme.onSurfaceVariant,
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            TextButton(
                              onPressed: _useSuggested,
                              style: TextButton.styleFrom(
                                backgroundColor: colorScheme.primary,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                              child: Text(
                                AppLocalization.translate('analyze', locale),
                                style: const TextStyle(fontSize: 12),
                              ),
                            ),
                            IconButton(
                              onPressed: () =>
                                  setState(() => _suggestedUrl = null),
                              icon: const Icon(Icons.close_rounded, size: 18),
                              visualDensity: VisualDensity.compact,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  // ─── حقل URL ───
                  Container(
                    decoration: BoxDecoration(
                      color: theme.cardColor,
                      borderRadius: BorderRadius.circular(18),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.07),
                          blurRadius: 16,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          t('quick_download', locale),
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 12),

                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _urlController,
                                textDirection: TextDirection.ltr,
                                decoration: InputDecoration(
                                  hintText: t('paste_url', locale),
                                  hintTextDirection: locale.languageCode == 'ar'
                                      ? TextDirection.rtl
                                      : TextDirection.ltr,
                                  prefixIcon: const Icon(Icons.link_rounded),
                                  suffixIcon: _urlController.text.isNotEmpty
                                      ? IconButton(
                                          icon: const Icon(Icons.clear_rounded),
                                          onPressed: () {
                                            _urlController.clear();
                                            setState(() {});
                                          },
                                        )
                                      : null,
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: BorderSide.none,
                                  ),
                                  filled: true,
                                ),
                                onChanged: (_) => setState(() {}),
                                onSubmitted: (_) => _analyze(),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => const BrowserScreen(),
                                    ),
                                  );
                                },
                                icon: const Icon(
                                  Icons.explore_rounded,
                                  size: 18,
                                ),
                                label: Text(t('browse_web', locale)),
                                style: OutlinedButton.styleFrom(
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: extractState.isLoading
                                    ? null
                                    : _analyze,
                                icon: extractState.isLoading
                                    ? const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white,
                                        ),
                                      )
                                    : const Icon(
                                        Icons.search_rounded,
                                        size: 18,
                                      ),
                                label: Text(
                                  extractState.isLoading
                                      ? t('analyzing', locale)
                                      : t('analyze', locale),
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: colorScheme.primary,
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        // رسالة خطأ
                        if (extractState.errorMessage != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 10),
                            child: Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: Colors.red.shade50,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.red.shade200),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.error_outline,
                                    color: Colors.red.shade600,
                                    size: 16,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      t(extractState.errorMessage!, locale),
                                      style: TextStyle(
                                        color: Colors.red.shade700,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 28),
                  
                  // ─── المنصات المدعومة ───
                  Text(
                    t('supported_platforms', locale),
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 14),
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: switch (context.device) {
                        DeviceKind.desktop => 6,
                        DeviceKind.tablet => 5,
                        DeviceKind.mobile => 4,
                      },
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 12,
                      childAspectRatio: 0.85,
                    ),
                    itemCount: _platforms.length,
                    itemBuilder: (ctx, i) {
                      final p = _platforms[i];
                      final name = t(p['key'] as String, locale);
                      final platformKey = p['key'] as String;
                      final homeUrl = kPlatformHomeUrls[platformKey];
                      return Semantics(
                        button: true,
                        label: name,
                        child: GestureDetector(
                          onTap: homeUrl == null
                              ? null
                              : () => launchUrl(
                                  Uri.parse(homeUrl),
                                  mode: LaunchMode.externalApplication,
                                ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 52,
                                height: 52,
                                decoration: BoxDecoration(
                                  color: (p['color'] as Color).withValues(
                                    alpha: 0.12,
                                  ),
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: Icon(
                                  p['icon'] as IconData,
                                  color: p['color'] as Color,
                                  size: 26,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                name,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  fontSize: 10,
                                ),
                                textAlign: TextAlign.center,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
              secondary: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ─── التحميلات النشطة ───
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        t('downloading', locale),
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (downloadState.downloadQueue.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: colorScheme.primary,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            '${downloadState.items.length}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  
                  if (downloadState.downloadQueue.isEmpty)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: colorScheme.primary.withValues(alpha: 0.04),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: colorScheme.primary.withValues(alpha: 0.1),
                          style: BorderStyle.solid,
                          width: 1,
                        ),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.download_done_rounded,
                            size: 48,
                            color: colorScheme.primary.withValues(alpha: 0.4),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            t('dm_empty_active', locale),
                            style: TextStyle(
                              color: colorScheme.onSurfaceVariant,
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    )
                  else ...[
                    ...downloadState.items.take(3).map((v) {
                      final progress = v.progress;
                      return Semantics(
                        label: 'Download ${v.title}, ${(progress * 100).toStringAsFixed(0)} percent',
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: theme.cardColor,
                            borderRadius: BorderRadius.circular(14),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.05),
                                blurRadius: 8,
                              ),
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    Icons.video_file_rounded,
                                    color: colorScheme.primary,
                                    size: 18,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      v.title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ),
                                  Text(
                                    t('format_percent', locale).replaceAll(
                                      '{p}',
                                      (progress * 100).toStringAsFixed(0),
                                    ),
                                    style: TextStyle(
                                      color: colorScheme.primary,
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                                child: LinearProgressIndicator(
                                  value: progress,
                                  minHeight: 6,
                                  backgroundColor: Colors.grey.shade200,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }),
                  ],
                  const SizedBox(height: 28),

                  // ─── نصائح ───
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          colorScheme.primary.withValues(alpha: 0.08),
                          colorScheme.secondary.withValues(alpha: 0.05),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: colorScheme.primary.withValues(alpha: 0.15),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.lightbulb_outline_rounded,
                              color: colorScheme.primary,
                              size: 18,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              t('tips', locale),
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: colorScheme.primary,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        ...['tip_1', 'tip_2', 'tip_3'].map(
                          (key) => Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(
                                  Icons.check_circle_outline_rounded,
                                  size: 15,
                                  color: colorScheme.primary,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    t(key, locale),
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      height: 1.4,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),
                ],
              ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
