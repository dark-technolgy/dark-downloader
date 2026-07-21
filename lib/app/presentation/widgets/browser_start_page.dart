import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import '../../providers/browser_tabs_provider.dart';
import '../../providers/browser_history_provider.dart';
import 'dart:ui';

class BrowserStartPage extends ConsumerWidget {
  const BrowserStartPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tabsNotifier = ref.read(browserTabsProvider.notifier);
    final activeTab = ref.watch(browserTabsProvider).activeTab;
    final recentHistory = ref.watch(browserHistoryProvider).take(5).toList();

    void navigate(String url) {
      if (activeTab?.webViewController != null) {
        activeTab!.webViewController!.loadUrl(urlRequest: URLRequest(url: WebUri(url)));
      } else {
        tabsNotifier.updateActiveTab(url: url);
      }
    }

    void search(String query) {
      if (query.trim().isEmpty) return;
      var searchUrl = query;
      if (!query.startsWith("http")) {
        searchUrl = "https://google.com/search?q=$query";
      }
      navigate(searchUrl);
    }

    Widget buildSpeedDialItem(String name, String url, IconData icon, Color color) {
      return GestureDetector(
        onTap: () => navigate(url),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
              ),
              child: Icon(icon, color: color, size: 30),
            ),
            const SizedBox(height: 8),
            Text(
              name,
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ],
        ),
      );
    }

    return Container(
      color: const Color(0xFF0A0A0A),
      child: Stack(
        children: [
          // Background Gradient / Glow
          Positioned(
            top: -100,
            left: -100,
            child: Container(
              width: 300,
              height: 300,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF00A3FF).withValues(alpha: 0.15),
              ),
            ),
          ),
          Positioned(
            bottom: -100,
            right: -100,
            child: Container(
              width: 300,
              height: 300,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFFB026FF).withValues(alpha: 0.15),
              ),
            ),
          ),
          BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 50, sigmaY: 50),
            child: Container(color: Colors.transparent),
          ),
          
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Logo
                    const Icon(
                      Icons.travel_explore_rounded,
                      size: 80,
                      color: Colors.white,
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Dark Browser',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(height: 40),
                    
                    // Search Box
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                      ),
                      child: TextField(
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          hintText: 'ابحث في الويب أو أدخل رابطاً...',
                          hintStyle: const TextStyle(color: Colors.white54),
                          prefixIcon: const Icon(Icons.search_rounded, color: Colors.white54),
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
                        ),
                        textInputAction: TextInputAction.go,
                        onSubmitted: search,
                      ),
                    ),
                    
                    const SizedBox(height: 48),
                    
                    // Speed Dial
                    const Text(
                      'مواقع مفضلة',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white70, fontSize: 16, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 24,
                      runSpacing: 24,
                      alignment: WrapAlignment.center,
                      children: [
                        buildSpeedDialItem('Google', 'https://google.com', Icons.g_mobiledata_rounded, Colors.blue),
                        buildSpeedDialItem('YouTube', 'https://youtube.com', Icons.play_arrow_rounded, Colors.red),
                        buildSpeedDialItem('X (Twitter)', 'https://x.com', Icons.close_rounded, Colors.white),
                        buildSpeedDialItem('Instagram', 'https://instagram.com', Icons.camera_alt_rounded, Colors.pinkAccent),
                        buildSpeedDialItem('TikTok', 'https://tiktok.com', Icons.music_note_rounded, Colors.cyanAccent),
                        buildSpeedDialItem('Facebook', 'https://facebook.com', Icons.facebook_rounded, Colors.blueAccent),
                      ],
                    ),

                    if (recentHistory.isNotEmpty) ...[
                      const SizedBox(height: 48),
                      const Text(
                        'تمت زيارتها مؤخراً',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white70, fontSize: 16, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 16),
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                        ),
                        child: Column(
                          children: recentHistory.map((item) {
                            return ListTile(
                              leading: const Icon(Icons.history_rounded, color: Colors.white54),
                              title: Text(
                                item.title,
                                style: const TextStyle(color: Colors.white, fontSize: 14),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Text(
                                item.url,
                                style: const TextStyle(color: Colors.white38, fontSize: 12),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              onTap: () => navigate(item.url),
                            );
                          }).toList(),
                        ),
                      ),
                    ],
                    const SizedBox(height: 48),
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
