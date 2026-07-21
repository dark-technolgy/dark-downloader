import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'dart:ui';
import '../../providers/browser_history_provider.dart';
import '../../providers/browser_tabs_provider.dart';

class BrowserHistorySheet extends ConsumerWidget {
  const BrowserHistorySheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final historyItems = ref.watch(browserHistoryProvider);
    final historyNotifier = ref.read(browserHistoryProvider.notifier);
    final tabsNotifier = ref.read(browserTabsProvider.notifier);

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
                      const Icon(Icons.history_rounded, color: Colors.white, size: 28),
                      const Text(
                        'سجل التصفح',
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
                
                // Action Bar
                if (historyItems.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton.icon(
                          onPressed: () {
                            showDialog(
                              context: context,
                              builder: (context) => AlertDialog(
                                backgroundColor: const Color(0xFF1E1E1E),
                                title: const Text('مسح السجل', style: TextStyle(color: Colors.white)),
                                content: const Text('هل أنت متأكد أنك تريد مسح سجل التصفح بالكامل؟', style: TextStyle(color: Colors.white70)),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(context),
                                    child: const Text('إلغاء', style: TextStyle(color: Colors.white54)),
                                  ),
                                  TextButton(
                                    onPressed: () {
                                      historyNotifier.clearHistory();
                                      Navigator.pop(context);
                                    },
                                    child: const Text('مسح', style: TextStyle(color: Colors.redAccent)),
                                  ),
                                ],
                              ),
                            );
                          },
                          icon: const Icon(Icons.delete_sweep_rounded, color: Colors.redAccent, size: 20),
                          label: const Text('مسح الكل', style: TextStyle(color: Colors.redAccent)),
                        ),
                      ],
                    ),
                  ),

                // List of History Items
                Expanded(
                  child: historyItems.isEmpty
                      ? const Center(
                          child: Text(
                            'سجل التصفح فارغ',
                            style: TextStyle(color: Colors.white54, fontSize: 16),
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                          itemCount: historyItems.length,
                          separatorBuilder: (context, index) => Divider(color: Colors.white.withValues(alpha: 0.1)),
                          itemBuilder: (context, index) {
                            final item = historyItems[index];
                            final timeStr = "${item.visitedAt.hour.toString().padLeft(2, '0')}:${item.visitedAt.minute.toString().padLeft(2, '0')}";
                            
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
                                item.title,
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Text(
                                "$timeStr • ${item.url}",
                                style: const TextStyle(color: Colors.white54, fontSize: 12),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              trailing: IconButton(
                                icon: const Icon(Icons.close_rounded, color: Colors.white38, size: 20),
                                onPressed: () {
                                  historyNotifier.removeVisit(item.id);
                                },
                              ),
                              onTap: () {
                                final activeTab = ref.read(browserTabsProvider).activeTab;
                                if (activeTab != null && activeTab.webViewController != null && activeTab.url.isEmpty) {
                                  activeTab.webViewController!.loadUrl(
                                    urlRequest: URLRequest(url: WebUri(item.url)),
                                  );
                                } else {
                                  tabsNotifier.addTab(url: item.url);
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
