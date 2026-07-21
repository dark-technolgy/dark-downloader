import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:ui';
import '../../providers/browser_tabs_provider.dart';

class TabSwitcherSheet extends ConsumerWidget {
  const TabSwitcherSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final browserState = ref.watch(browserTabsProvider);
    final notifier = ref.read(browserTabsProvider.notifier);

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
                      IconButton(
                        icon: const Icon(Icons.add_rounded, color: Colors.white, size: 28),
                        onPressed: () {
                          notifier.addTab();
                          Navigator.pop(context);
                        },
                      ),
                      Text(
                        'التبويبات (${browserState.tabs.length})',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('تم', style: TextStyle(color: Color(0xFF00A3FF), fontSize: 16, fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                ),
                
                // Grid of Tabs
                Expanded(
                  child: GridView.builder(
                    padding: const EdgeInsets.all(16.0),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      crossAxisSpacing: 16.0,
                      mainAxisSpacing: 16.0,
                      childAspectRatio: 0.65,
                    ),
                    itemCount: browserState.tabs.length,
                    itemBuilder: (context, index) {
                      final tab = browserState.tabs[index];
                      final isActive = index == browserState.activeTabIndex;

                      return GestureDetector(
                        onTap: () {
                          notifier.setActiveTab(index);
                          Navigator.pop(context);
                        },
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.05),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: isActive ? const Color(0xFF00A3FF) : Colors.white.withValues(alpha: 0.1),
                              width: isActive ? 2.0 : 1.0,
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              // Tab Header
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 6.0),
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.3),
                                  borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        tab.title,
                                        style: const TextStyle(color: Colors.white, fontSize: 12),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    GestureDetector(
                                      onTap: () {
                                        notifier.closeTab(index);
                                      },
                                      child: const Icon(Icons.close_rounded, color: Colors.white70, size: 18),
                                    ),
                                  ],
                                ),
                              ),
                              
                              // Tab Thumbnail
                              Expanded(
                                child: ClipRRect(
                                  borderRadius: const BorderRadius.vertical(bottom: Radius.circular(14)),
                                  child: tab.screenshot != null
                                      ? Image.memory(tab.screenshot!, fit: BoxFit.cover)
                                      : Container(
                                          color: Colors.white.withValues(alpha: 0.02),
                                          child: const Center(
                                            child: Icon(Icons.public, color: Colors.white24, size: 40),
                                          ),
                                        ),
                                ),
                              ),
                            ],
                          ),
                        ),
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
