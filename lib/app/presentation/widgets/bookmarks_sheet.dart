import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'dart:ui';
import '../../providers/bookmarks_provider.dart';
import '../../providers/browser_tabs_provider.dart';

class BookmarksSheet extends ConsumerWidget {
  const BookmarksSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bookmarksState = ref.watch(bookmarksProvider);
    final tabsNotifier = ref.read(browserTabsProvider.notifier);
    
    // Using AsyncValue because the project's BookmarksNotifier uses AsyncValue
    final bookmarks = bookmarksState.value ?? [];

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          // Background Blur
          Positioned.fill(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
              child: Container(
                color: Colors.black.withValues(alpha: 0.6),
              ),
            ),
          ),
          
          // Content
          SafeArea(
            child: Column(
              children: [
                // Header
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Icon(Icons.bookmarks_rounded, color: Colors.white, size: 28),
                      const Text(
                        'الإشارات المرجعية',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('إغلاق', style: TextStyle(color: Color(0xFF00A3FF), fontSize: 16, fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                ),
                
                // List of Bookmarks
                Expanded(
                  child: bookmarks.isEmpty
                      ? const Center(
                          child: Text(
                            'لا توجد إشارات مرجعية',
                            style: TextStyle(color: Colors.white54, fontSize: 16),
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                          itemCount: bookmarks.length,
                          separatorBuilder: (context, index) => Divider(color: Colors.white.withValues(alpha: 0.1)),
                          itemBuilder: (context, index) {
                            final bookmark = bookmarks[index];
                            return ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Icon(Icons.public, color: Colors.white70),
                              ),
                              title: Text(
                                bookmark.title,
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Text(
                                bookmark.url,
                                style: const TextStyle(color: Colors.white54, fontSize: 12),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              trailing: IconButton(
                                icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                                onPressed: () {
                                  ref.read(bookmarksProvider.notifier).removeBookmark(bookmark.id);
                                },
                              ),
                              onTap: () {
                                // Open bookmark in active tab
                                final activeTab = ref.read(browserTabsProvider).activeTab;
                                if (activeTab != null && activeTab.webViewController != null) {
                                  activeTab.webViewController!.loadUrl(
                                    urlRequest: URLRequest(url: WebUri(bookmark.url)),
                                  );
                                } else {
                                  tabsNotifier.addTab(url: bookmark.url);
                                }
                                Navigator.pop(context);
                              },
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
