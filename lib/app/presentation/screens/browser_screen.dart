import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:ui';
import 'dart:collection';
import '../../services/ad_blocker_service.dart';
import '../../services/video_sniffer_service.dart';
import '../../providers/incoming_link_provider.dart';
import '../../providers/browser_tabs_provider.dart';
import '../../providers/bookmarks_provider.dart';
import '../../providers/browser_history_provider.dart';
import '../../providers/extractor_provider.dart';
import '../../providers/download_manager_provider.dart';
import '../../models/video_model.dart';
import '../../utils/download_streams_resolver.dart';
import '../../utils/stream_utils.dart';
import '../widgets/tab_switcher_sheet.dart';
import '../widgets/bookmarks_sheet.dart';
import '../widgets/browser_history_sheet.dart';
import '../widgets/browser_start_page.dart';

class BrowserScreen extends ConsumerStatefulWidget {
  const BrowserScreen({super.key});

  @override
  ConsumerState<BrowserScreen> createState() => _BrowserScreenState();
}

class _BrowserScreenState extends ConsumerState<BrowserScreen> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  late final AdBlockerService _adBlocker;
  late final VideoSnifferService _videoSniffer;
  bool _isExtracting = false;

  final UserScript _downloadButtonScript = UserScript(
    source: """
      var css = `
        .dark-dl-btn {
          position: absolute !important;
          top: 10px !important;
          right: 10px !important;
          z-index: 2147483647 !important;
          background: linear-gradient(135deg, #00A3FF, #0070CC) !important;
          color: white !important;
          border: none !important;
          border-radius: 12px !important;
          padding: 10px 16px !important;
          font-size: 14px !important;
          font-weight: bold !important;
          cursor: pointer !important;
          box-shadow: 0 4px 12px rgba(0,163,255,0.4) !important;
          font-family: sans-serif !important;
          display: flex !important;
          align-items: center !important;
          gap: 6px !important;
          opacity: 0.85 !important;
          transition: all 0.3s ease !important;
          backdrop-filter: blur(8px) !important;
        }
        .dark-dl-btn:hover {
          opacity: 1.0 !important;
          transform: scale(1.05) !important;
          box-shadow: 0 6px 16px rgba(0,163,255,0.6) !important;
        }
        .dark-dl-wrapper {
          position: relative !important;
        }
        .dark-dl-page-btn {
          position: fixed !important;
          bottom: 20px !important;
          right: 20px !important;
          z-index: 2147483647 !important;
          background: linear-gradient(135deg, #00A3FF, #0070CC) !important;
          color: white !important;
          border: none !important;
          border-radius: 50px !important;
          padding: 14px 24px !important;
          font-size: 15px !important;
          font-weight: bold !important;
          cursor: pointer !important;
          box-shadow: 0 6px 20px rgba(0,163,255,0.5) !important;
          font-family: sans-serif !important;
          display: none !important;
          align-items: center !important;
          gap: 8px !important;
          transition: all 0.3s ease !important;
          animation: dark-dl-pulse 2s infinite !important;
        }
        .dark-dl-page-btn.visible {
          display: flex !important;
        }
        @keyframes dark-dl-pulse {
          0% { box-shadow: 0 6px 20px rgba(0,163,255,0.5) !important; }
          50% { box-shadow: 0 6px 30px rgba(0,163,255,0.8) !important; }
          100% { box-shadow: 0 6px 20px rgba(0,163,255,0.5) !important; }
        }
      `;
      var style = document.createElement('style');
      style.innerHTML = css;
      document.head.appendChild(style);

      // Page-level download button (shown when video platform detected)
      var pageBtn = document.createElement('button');
      pageBtn.className = 'dark-dl-page-btn';
      pageBtn.innerHTML = '⬇ تحميل هذا الفيديو';
      pageBtn.onclick = function(e) {
        e.preventDefault();
        e.stopPropagation();
        window.flutter_inappwebview.callHandler('downloadPage', window.location.href);
      };
      document.body.appendChild(pageBtn);

      // Detect if this is a video platform page
      function detectVideoPlatform() {
        var host = window.location.hostname;
        var path = window.location.pathname;
        var href = window.location.href;
        
        var isVideoPage = false;
        
        // YouTube
        if ((host.includes('youtube.com') && (path.includes('/watch') || path.includes('/shorts'))) ||
            host.includes('youtu.be')) {
          isVideoPage = true;
        }
        // TikTok
        if (host.includes('tiktok.com') && path.includes('/video')) isVideoPage = true;
        // Instagram
        if (host.includes('instagram.com') && (path.includes('/reel') || path.includes('/p/'))) isVideoPage = true;
        // Twitter/X
        if ((host.includes('twitter.com') || host.includes('x.com')) && path.includes('/status')) isVideoPage = true;
        // Facebook
        if (host.includes('facebook.com') && (path.includes('/videos') || path.includes('/watch') || href.includes('video_id'))) isVideoPage = true;
        // Vimeo
        if (host.includes('vimeo.com') && /\\/\\d+/.test(path)) isVideoPage = true;
        // Dailymotion
        if (host.includes('dailymotion.com') && path.includes('/video')) isVideoPage = true;
        // Reddit
        if (host.includes('reddit.com') && path.includes('/comments')) isVideoPage = true;
        // Twitch clips
        if (host.includes('twitch.tv') && (path.includes('/clip') || path.includes('/videos'))) isVideoPage = true;
        // Rumble
        if (host.includes('rumble.com') && path.length > 1) isVideoPage = true;
        // Pinterest
        if (host.includes('pinterest.com') && path.includes('/pin/')) isVideoPage = true;
        
        if (isVideoPage) {
          pageBtn.classList.add('visible');
        } else {
          pageBtn.classList.remove('visible');
        }
      }

      // Inject download buttons on HTML5 <video> elements
      function addDownloadButtons() {
        var videos = document.getElementsByTagName('video');
        for (var i = 0; i < videos.length; i++) {
          var vid = videos[i];
          if (!vid.hasAttribute('data-dark-dl-injected')) {
            vid.setAttribute('data-dark-dl-injected', 'true');
            
            var parent = vid.parentElement;
            if(parent) {
               parent.classList.add('dark-dl-wrapper');
               
               var btn = document.createElement('button');
               btn.className = 'dark-dl-btn';
               btn.innerHTML = '⬇ تحميل';
               
               btn.onclick = function(e) {
                 e.preventDefault();
                 e.stopPropagation();
                 
                 var videoSrc = vid.src;
                 var pageUrl = window.location.href;
                 
                 window.flutter_inappwebview.callHandler('downloadVideo', pageUrl, videoSrc);
               };
               
               parent.appendChild(btn);
            }
          }
        }
      }

      // Also look for <source> elements inside <video>
      function scanSourceElements() {
        var sources = document.querySelectorAll('video source');
        for (var i = 0; i < sources.length; i++) {
          var src = sources[i].src;
          if (src && !src.startsWith('blob:') && src.startsWith('http')) {
            window.flutter_inappwebview.callHandler('sniffedSource', src);
          }
        }
      }

      setInterval(function() {
        addDownloadButtons();
        detectVideoPlatform();
        scanSourceElements();
      }, 1500);
      addDownloadButtons();
      detectVideoPlatform();
    """,
    injectionTime: UserScriptInjectionTime.AT_DOCUMENT_END,
  );

  @override
  void initState() {
    super.initState();
    _adBlocker = AdBlockerService();
    _videoSniffer = VideoSnifferService();

    _videoSniffer.sniffedVideos.addListener(_onVideosChanged);
    _searchFocusNode.addListener(_onFocusChange);
  }

  @override
  void dispose() {
    _videoSniffer.sniffedVideos.removeListener(_onVideosChanged);
    _searchFocusNode.removeListener(_onFocusChange);
    _searchFocusNode.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onFocusChange() {
    if (mounted) setState(() {});
    if (_searchFocusNode.hasFocus) {
      final activeTab = ref.read(browserTabsProvider).activeTab;
      if (activeTab != null && activeTab.url.isNotEmpty) {
        _searchController.text = activeTab.url;
        _searchController.selection = TextSelection(
          baseOffset: 0,
          extentOffset: _searchController.text.length,
        );
      }
    }
  }

  void _onVideosChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _extractAndDownload(String url, {String? fallbackUrl}) async {
    if (_isExtracting) return;
    setState(() => _isExtracting = true);

    try {
      // Try extracting the primary URL (usually the page URL to get all qualities)
      await ref.read(extractorProvider.notifier).extractVideo(url);
      var state = ref.read(extractorProvider);

      // If page extraction fails and we have a raw video URL, fallback to it
      if (state.status == ExtractStatus.error && fallbackUrl != null && fallbackUrl.isNotEmpty && fallbackUrl != url && !fallbackUrl.startsWith('blob:')) {
        await ref.read(extractorProvider.notifier).extractVideo(fallbackUrl);
        state = ref.read(extractorProvider);
      }

      if (!mounted) return;

      if (state.status == ExtractStatus.success && state.video != null) {
        // Show bottom sheet with download options
        _showDownloadSheet(state.video!, state.streams);
      } else if (state.status == ExtractStatus.error) {
        // If both failed, offer direct download of the fallback or url
        _showDirectDownloadOption(fallbackUrl != null && fallbackUrl.isNotEmpty && !fallbackUrl.startsWith('blob:') ? fallbackUrl : url);
      }
    } finally {
      if (mounted) setState(() => _isExtracting = false);
    }
  }

  /// Show a professional bottom sheet with stream options for download.
  void _showDownloadSheet(VideoModel video, List<StreamInfo> streams) {
    final bestStream = pickBestDefault(streams);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _DownloadBottomSheet(
        video: video,
        streams: streams,
        bestStream: bestStream,
        onDownload: (selectedStream, audioStream) {
          Navigator.pop(ctx);
          ref.read(downloadManagerProvider.notifier).addToQueue(
                video,
                stream: selectedStream,
                audioStream: audioStream,
              );
          _showSuccessSnackBar('جاري تحميل: ${video.title} 🚀');
        },
        onDownloadBest: () {
          Navigator.pop(ctx);
          final resolved = resolveDownloadStreams(
            video,
            streams,
          );
          ref.read(downloadManagerProvider.notifier).addToQueue(
                video,
                stream: resolved.primary,
                audioStream: resolved.audioCompanion,
              );
          _showSuccessSnackBar('جاري تحميل أفضل جودة: ${video.title} 🚀');
        },
      ),
    );
  }

  /// Fallback: offer direct file download if extraction fails.
  void _showDirectDownloadOption(String url) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        margin: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A2E),
          borderRadius: BorderRadius.circular(24),
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.warning_amber_rounded, color: Colors.amber, size: 48),
            const SizedBox(height: 16),
            const Text(
              'لم يتم التعرف على الفيديو تلقائياً',
              style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'هل تريد محاولة التحميل المباشر؟',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 14),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(ctx),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white70,
                      side: const BorderSide(color: Colors.white24),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: const Text('إلغاء'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      // Send to home extractor as fallback
                      ref.read(pendingExtractorUrlProvider.notifier).set(url);
                      _showSuccessSnackBar('تم إرسال الرابط لمحرك التحميل 🔄');
                    },
                    icon: const Icon(Icons.download_rounded, size: 18),
                    label: const Text('تحميل'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF00A3FF),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showSuccessSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
            const SizedBox(width: 10),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: const Color(0xFF00A3FF),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  void _showTabSwitcher() {
    final state = ref.read(browserTabsProvider);
    final activeTab = state.activeTab;
    if (activeTab?.webViewController != null) {
      activeTab!.webViewController!.takeScreenshot().then((screenshot) {
        if (screenshot != null) {
          ref.read(browserTabsProvider.notifier).updateActiveTab(screenshot: screenshot);
        }
      });
    }

    showGeneralDialog(
      context: context,
      barrierDismissible: false,
      pageBuilder: (context, animation, secondaryAnimation) {
        return const TabSwitcherSheet();
      },
    );
  }

  void _showBookmarks() {
    showGeneralDialog(
      context: context,
      barrierDismissible: false,
      pageBuilder: (context, animation, secondaryAnimation) {
        return const BookmarksSheet();
      },
    );
  }

  void _showHistory() {
    showGeneralDialog(
      context: context,
      barrierDismissible: false,
      pageBuilder: (context, animation, secondaryAnimation) {
        return const BrowserHistorySheet();
      },
    );
  }

  String _getDomain(String url) {
    try {
      final uri = Uri.parse(url);
      return uri.host.replaceFirst('www.', '');
    } catch (_) {
      return url;
    }
  }

  @override
  Widget build(BuildContext context) {
    final browserState = ref.watch(browserTabsProvider);
    final tabsNotifier = ref.read(browserTabsProvider.notifier);
    final activeTab = browserState.activeTab;
    final sniffedVideos = _videoSniffer.sniffedVideos.value;

    final bookmarksState = ref.watch(bookmarksProvider);
    final bookmarksNotifier = ref.read(bookmarksProvider.notifier);
    final isBookmarked = bookmarksNotifier.isBookmarked(activeTab?.url ?? '');

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      body: SafeArea(
        child: Column(
          children: [
            // 1. Professional Omnibox (Address Bar)
            Container(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.7),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.15),
                      ),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            // Main Menu
                            PopupMenuButton<String>(
                              icon: const Icon(Icons.more_vert_rounded, color: Colors.white70),
                              color: const Color(0xFF1E1E1E),
                              onSelected: (value) {
                                if (value == 'home') {
                                  tabsNotifier.updateActiveTab(url: '');
                                } else if (value == 'bookmarks') {
                                  _showBookmarks();
                                } else if (value == 'history') {
                                  _showHistory();
                                } else if (value == 'refresh') {
                                  activeTab?.webViewController?.reload();
                                }
                              },
                              itemBuilder: (context) => [
                                const PopupMenuItem(value: 'home', child: Row(children: [Icon(Icons.home_rounded, color: Colors.white), SizedBox(width: 12), Text('الرئيسية', style: TextStyle(color: Colors.white))])),
                                const PopupMenuItem(value: 'bookmarks', child: Row(children: [Icon(Icons.bookmarks_rounded, color: Colors.white), SizedBox(width: 12), Text('الإشارات المرجعية', style: TextStyle(color: Colors.white))])),
                                const PopupMenuItem(value: 'history', child: Row(children: [Icon(Icons.history_rounded, color: Colors.white), SizedBox(width: 12), Text('سجل التصفح', style: TextStyle(color: Colors.white))])),
                                const PopupMenuItem(value: 'refresh', child: Row(children: [Icon(Icons.refresh_rounded, color: Colors.white), SizedBox(width: 12), Text('تحديث', style: TextStyle(color: Colors.white))])),
                              ],
                            ),

                            // Navigation (Back/Forward)
                            if (activeTab != null && activeTab.canGoBack)
                              IconButton(
                                icon: const Icon(Icons.arrow_back_ios_rounded, color: Colors.white, size: 18),
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(minWidth: 36),
                                onPressed: () => activeTab.webViewController?.goBack(),
                              ),
                            if (activeTab != null && activeTab.canGoForward)
                              IconButton(
                                icon: const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white, size: 18),
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(minWidth: 36),
                                onPressed: () => activeTab.webViewController?.goForward(),
                              ),

                            // Smart URL Field
                            Expanded(
                              child: GestureDetector(
                                onTap: () {
                                  if (!_searchFocusNode.hasFocus) {
                                    _searchFocusNode.requestFocus();
                                  }
                                },
                                child: Container(
                                  height: 48,
                                  alignment: Alignment.center,
                                  child: !_searchFocusNode.hasFocus && activeTab != null && activeTab.url.isNotEmpty
                                      ? Row(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            if (activeTab.isSecure)
                                              const Icon(Icons.lock_rounded, size: 14, color: Colors.white70),
                                            if (!activeTab.isSecure && activeTab.url.startsWith('http:'))
                                              const Icon(Icons.warning_amber_rounded, size: 14, color: Colors.redAccent),
                                            if (activeTab.url.startsWith('http'))
                                              const SizedBox(width: 6),
                                            Flexible(
                                              child: Text(
                                                _getDomain(activeTab.url),
                                                style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w500),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                          ],
                                        )
                                      : TextField(
                                          controller: _searchController,
                                          focusNode: _searchFocusNode,
                                          style: const TextStyle(color: Colors.white, fontSize: 15),
                                          textAlign: TextAlign.center,
                                          decoration: InputDecoration(
                                            hintText: activeTab?.url.isEmpty == true ? 'ابحث أو أدخل رابطاً...' : '',
                                            hintStyle: const TextStyle(color: Colors.white54),
                                            border: InputBorder.none,
                                            contentPadding: EdgeInsets.zero,
                                          ),
                                          textInputAction: TextInputAction.go,
                                          onSubmitted: (value) {
                                            var searchUrl = value;
                                            if (!value.startsWith("http")) {
                                              searchUrl = "https://google.com/search?q=$value";
                                            }
                                            if (activeTab?.webViewController != null && activeTab!.url.isNotEmpty) {
                                              activeTab.webViewController!.loadUrl(urlRequest: URLRequest(url: WebUri(searchUrl)));
                                            } else {
                                              tabsNotifier.updateActiveTab(url: searchUrl);
                                            }
                                          },
                                        ),
                                ),
                              ),
                            ),

                            // Bookmark Star
                            IconButton(
                              icon: Icon(isBookmarked ? Icons.star_rounded : Icons.star_outline_rounded),
                              color: isBookmarked ? Colors.amber : Colors.white70,
                              onPressed: () {
                                if (activeTab == null || activeTab.url.isEmpty) return;
                                if (isBookmarked) {
                                  final items = bookmarksState.value ?? [];
                                  final idx = items.indexWhere((b) => b.url == activeTab.url);
                                  if (idx != -1) bookmarksNotifier.removeBookmark(items[idx].id);
                                } else {
                                  bookmarksNotifier.addBookmark(activeTab.title, activeTab.url);
                                }
                              },
                            ),

                            // Tab Switcher Button
                            GestureDetector(
                              onTap: _showTabSwitcher,
                              child: Container(
                                margin: const EdgeInsets.only(right: 8, left: 12),
                                padding: const EdgeInsets.all(6),
                                decoration: BoxDecoration(
                                  border: Border.all(color: Colors.white70, width: 1.5),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  '${browserState.tabs.length}',
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        // Loading Progress Bar
                        if (activeTab != null && activeTab.progress < 1.0 && activeTab.url.isNotEmpty)
                          LinearProgressIndicator(
                            value: activeTab.progress,
                            minHeight: 2,
                            backgroundColor: Colors.transparent,
                            valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF00A3FF)),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

            // 2. Web Engine Tabs
            Expanded(
              child: Stack(
                children: browserState.tabs.asMap().entries.map((entry) {
                  final index = entry.key;
                  final tab = entry.value;
                  final isActive = index == browserState.activeTabIndex;

                  return Offstage(
                    offstage: !isActive,
                    child: tab.url.isEmpty
                        ? const BrowserStartPage()
                        : InAppWebView(
                            initialUrlRequest: URLRequest(url: WebUri(tab.url)),
                            initialUserScripts: UnmodifiableListView<UserScript>([_downloadButtonScript]),
                            initialSettings: InAppWebViewSettings(
                              contentBlockers: _adBlocker.getContentBlockers(),
                              transparentBackground: true,
                              javaScriptEnabled: true,
                              mediaPlaybackRequiresUserGesture: false,
                              allowsInlineMediaPlayback: true,
                              useShouldInterceptRequest: true,
                              useOnDownloadStart: true,
                            ),
                            onWebViewCreated: (controller) {
                              // Handler: Download video (from injected button on <video>)
                              controller.addJavaScriptHandler(
                                handlerName: 'downloadVideo',
                                callback: (args) {
                                  if (args.isNotEmpty) {
                                    final pageUrl = args[0].toString();
                                    final videoSrc = args.length > 1 ? args[1].toString() : null;
                                    _extractAndDownload(pageUrl, fallbackUrl: videoSrc);
                                  }
                                },
                              );
                              // Handler: Download page (from page-level download button)
                              controller.addJavaScriptHandler(
                                handlerName: 'downloadPage',
                                callback: (args) {
                                  if (args.isNotEmpty) {
                                    final pageUrl = args[0].toString();
                                    _extractAndDownload(pageUrl);
                                  }
                                },
                              );
                              // Handler: Sniffed <source> element
                              controller.addJavaScriptHandler(
                                handlerName: 'sniffedSource',
                                callback: (args) {
                                  if (args.isNotEmpty) {
                                    _videoSniffer.analyzeRequest(args[0].toString());
                                  }
                                },
                              );
                              tabsNotifier.updateTab(index, controller: controller);
                            },
                            onLoadStart: (controller, uri) {
                              if (uri != null) {
                                tabsNotifier.updateTab(index, url: uri.toString(), isSecure: uri.scheme == 'https');
                                // Clear sniffed videos on new page navigation
                                _videoSniffer.clearSniffedVideos();
                              }
                            },
                            onLoadStop: (controller, uri) async {
                              if (uri != null) {
                                final title = await controller.getTitle() ?? 'New Tab';
                                final canGoBack = await controller.canGoBack();
                                final canGoForward = await controller.canGoForward();
                                tabsNotifier.updateTab(
                                  index,
                                  url: uri.toString(),
                                  title: title,
                                  isSecure: uri.scheme == 'https',
                                  canGoBack: canGoBack,
                                  canGoForward: canGoForward,
                                );
                                ref.read(browserHistoryProvider.notifier).addVisit(uri.toString(), title);
                              }
                            },
                            onProgressChanged: (controller, progress) {
                              tabsNotifier.updateTab(index, progress: progress / 100);
                            },
                            onUpdateVisitedHistory: (controller, uri, androidIsReload) async {
                              final canGoBack = await controller.canGoBack();
                              final canGoForward = await controller.canGoForward();
                              tabsNotifier.updateTab(index, canGoBack: canGoBack, canGoForward: canGoForward);
                            },
                            shouldInterceptRequest: (controller, request) async {
                              return await _videoSniffer.shouldInterceptRequest(request);
                            },
                            onDownloadStartRequest: (controller, downloadRequest) {
                              final downloadUrl = downloadRequest.url.toString();
                              _extractAndDownload(activeTab?.url ?? downloadUrl, fallbackUrl: downloadUrl);
                            },
                          ),
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      ),

      // Floating Action Button: shows sniffed video count or extraction spinner
      floatingActionButton: _isExtracting
          ? FloatingActionButton.extended(
              onPressed: null,
              icon: const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
              ),
              label: const Text('جاري التحليل...'),
              backgroundColor: const Color(0xFF00A3FF),
              foregroundColor: Colors.white,
            )
          : sniffedVideos.isNotEmpty
              ? FloatingActionButton.extended(
                  onPressed: () {
                    final currentUrl = activeTab?.url;
                    if (sniffedVideos.length == 1) {
                      _extractAndDownload(currentUrl ?? sniffedVideos.first.url, fallbackUrl: sniffedVideos.first.url);
                    } else {
                      _showSniffedVideosSheet(sniffedVideos, currentUrl);
                    }
                  },
                  icon: const Icon(Icons.download_rounded),
                  label: Text(
                    sniffedVideos.length == 1
                        ? 'تحميل الفيديو'
                        : 'تم اكتشاف ${sniffedVideos.length} فيديو',
                  ),
                  backgroundColor: const Color(0xFF00A3FF),
                  foregroundColor: Colors.white,
                )
              : null,
    );
  }

  /// Show a list of all detected videos to choose from.
  void _showSniffedVideosSheet(List<SniffedVideo> videos, String? pageUrl) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(ctx).size.height * 0.6,
        ),
        margin: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A2E),
          borderRadius: BorderRadius.circular(24),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  const Icon(Icons.video_library_rounded, color: Color(0xFF00A3FF), size: 24),
                  const SizedBox(width: 12),
                  Text(
                    'فيديوهات مكتشفة (${videos.length})',
                    style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
            const Divider(color: Colors.white12, height: 1),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: videos.length,
                itemBuilder: (ctx, i) {
                  final video = videos[i];
                  final domain = _getDomain(video.url);
                  return ListTile(
                    leading: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: const Color(0xFF00A3FF).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.play_circle_fill_rounded, color: Color(0xFF00A3FF)),
                    ),
                    title: Text(
                      domain,
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                    ),
                    subtitle: Text(
                      video.mimeType ?? video.url.split('?').first.split('/').last,
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 12),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.download_rounded, color: Color(0xFF00A3FF)),
                      onPressed: () {
                        Navigator.pop(ctx);
                        _extractAndDownload(pageUrl ?? video.url, fallbackUrl: video.url);
                      },
                    ),
                    onTap: () {
                      Navigator.pop(ctx);
                      _extractAndDownload(pageUrl ?? video.url, fallbackUrl: video.url);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// Download Bottom Sheet Widget
// ──────────────────────────────────────────────────────────────────────────────

class _DownloadBottomSheet extends StatefulWidget {
  final VideoModel video;
  final List<StreamInfo> streams;
  final StreamInfo? bestStream;
  final void Function(StreamInfo? video, StreamInfo? audio) onDownload;
  final VoidCallback onDownloadBest;

  const _DownloadBottomSheet({
    required this.video,
    required this.streams,
    this.bestStream,
    required this.onDownload,
    required this.onDownloadBest,
  });

  @override
  State<_DownloadBottomSheet> createState() => _DownloadBottomSheetState();
}

class _DownloadBottomSheetState extends State<_DownloadBottomSheet> {
  bool _showAllStreams = false;

  @override
  Widget build(BuildContext context) {
    final muxedStreams = widget.streams
        .where((s) => s.kind == StreamKind.muxed)
        .toList()
      ..sort((a, b) => b.sortScore.compareTo(a.sortScore));

    final videoOnlyStreams = widget.streams
        .where((s) => s.kind == StreamKind.videoOnly)
        .toList()
      ..sort((a, b) => b.sortScore.compareTo(a.sortScore));

    return Container(
      margin: const EdgeInsets.all(16),
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.75,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
            child: Row(
              children: [
                // Thumbnail
                if (widget.video.thumbnailUrl != null)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.network(
                      widget.video.thumbnailUrl!,
                      width: 80,
                      height: 56,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        width: 80,
                        height: 56,
                        color: Colors.white10,
                        child: const Icon(Icons.video_file_rounded, color: Colors.white24),
                      ),
                    ),
                  ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.video.title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        widget.video.platform,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.5),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Quick Download Button
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: widget.onDownloadBest,
                icon: const Icon(Icons.bolt_rounded, size: 20),
                label: Text(
                  'تحميل سريع (${widget.bestStream?.resolutionBucket ?? 'أفضل جودة'})',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00A3FF),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
              ),
            ),
          ),

          const SizedBox(height: 12),

          // Toggle to show all streams
          if (widget.streams.isNotEmpty)
            TextButton.icon(
              onPressed: () => setState(() => _showAllStreams = !_showAllStreams),
              icon: Icon(
                _showAllStreams ? Icons.expand_less : Icons.expand_more,
                color: Colors.white54,
              ),
              label: Text(
                _showAllStreams ? 'إخفاء الخيارات' : 'عرض كل الجودات (${widget.streams.length})',
                style: const TextStyle(color: Colors.white54),
              ),
            ),

          // Stream List
          if (_showAllStreams)
            Flexible(
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                children: [
                  if (muxedStreams.isNotEmpty) ...[
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Text('فيديو + صوت', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold, fontSize: 13)),
                    ),
                    ...muxedStreams.map((s) => _StreamTile(
                          stream: s,
                          isSelected: s == widget.bestStream,
                          onTap: () => widget.onDownload(s, null),
                        )),
                  ],
                  if (videoOnlyStreams.isNotEmpty) ...[
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Text('فيديو فقط (يحتاج دمج)', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold, fontSize: 13)),
                    ),
                    ...videoOnlyStreams.map((s) {
                      // Find best audio stream to pair with
                      final bestAudio = widget.streams
                          .where((a) => a.kind == StreamKind.audioOnly)
                          .fold<StreamInfo?>(null, (prev, a) => prev == null || a.sortScore > prev.sortScore ? a : prev);
                      return _StreamTile(
                        stream: s,
                        isSelected: false,
                        onTap: () => widget.onDownload(s, bestAudio),
                      );
                    }),
                  ],
                ],
              ),
            ),

          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

class _StreamTile extends StatelessWidget {
  final StreamInfo stream;
  final bool isSelected;
  final VoidCallback onTap;

  const _StreamTile({
    required this.stream,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFF00A3FF).withValues(alpha: 0.15)
              : Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(12),
          border: isSelected
              ? Border.all(color: const Color(0xFF00A3FF).withValues(alpha: 0.5))
              : null,
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 28,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: const Color(0xFF00A3FF).withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                stream.resolutionBucket,
                style: const TextStyle(color: Color(0xFF00A3FF), fontSize: 11, fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${stream.format.toUpperCase()} • ${stream.quality}',
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                  ),
                  if (stream.codecLabel.isNotEmpty)
                    Text(
                      stream.codecLabel,
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 11),
                    ),
                ],
              ),
            ),
            if (stream.fileSizeBytes != null)
              Text(
                _formatBytes(stream.fileSizeBytes!.toInt()),
                style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 12),
              ),
            const SizedBox(width: 8),
            const Icon(Icons.download_rounded, color: Color(0xFF00A3FF), size: 20),
          ],
        ),
      ),
    );
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
}
