import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:uuid/uuid.dart';

class BrowserTab {
  final String id;
  String url;
  String title;
  double progress;
  bool isSecure;
  bool canGoBack;
  bool canGoForward;
  Uint8List? screenshot;
  InAppWebViewController? webViewController;

  BrowserTab({
    required this.id,
    this.url = '',
    this.title = 'New Tab',
    this.progress = 0.0,
    this.isSecure = false,
    this.canGoBack = false,
    this.canGoForward = false,
    this.screenshot,
    this.webViewController,
  });

  BrowserTab copyWith({
    String? id,
    String? url,
    String? title,
    double? progress,
    bool? isSecure,
    bool? canGoBack,
    bool? canGoForward,
    Uint8List? screenshot,
    InAppWebViewController? webViewController,
  }) {
    return BrowserTab(
      id: id ?? this.id,
      url: url ?? this.url,
      title: title ?? this.title,
      progress: progress ?? this.progress,
      isSecure: isSecure ?? this.isSecure,
      canGoBack: canGoBack ?? this.canGoBack,
      canGoForward: canGoForward ?? this.canGoForward,
      screenshot: screenshot ?? this.screenshot,
      webViewController: webViewController ?? this.webViewController,
    );
  }
}

class BrowserState {
  final List<BrowserTab> tabs;
  final int activeTabIndex;

  BrowserState({
    required this.tabs,
    required this.activeTabIndex,
  });

  BrowserState copyWith({
    List<BrowserTab>? tabs,
    int? activeTabIndex,
  }) {
    return BrowserState(
      tabs: tabs ?? this.tabs,
      activeTabIndex: activeTabIndex ?? this.activeTabIndex,
    );
  }

  BrowserTab? get activeTab {
    if (tabs.isEmpty || activeTabIndex < 0 || activeTabIndex >= tabs.length) {
      return null;
    }
    return tabs[activeTabIndex];
  }
}

class BrowserTabsNotifier extends Notifier<BrowserState> {
  final _uuid = const Uuid();

  @override
  BrowserState build() {
    return BrowserState(
      tabs: [BrowserTab(id: _uuid.v4(), url: '')],
      activeTabIndex: 0,
    );
  }

  void addTab({String url = ''}) {
    final newTab = BrowserTab(id: _uuid.v4(), url: url);
    final newTabs = List<BrowserTab>.from(state.tabs)..add(newTab);
    state = state.copyWith(tabs: newTabs, activeTabIndex: newTabs.length - 1);
  }

  void closeTab(int index) {
    if (state.tabs.length <= 1) {
      // If closing the last tab, just reset it
      final newTabs = [BrowserTab(id: _uuid.v4())];
      state = state.copyWith(tabs: newTabs, activeTabIndex: 0);
      return;
    }

    final newTabs = List<BrowserTab>.from(state.tabs)..removeAt(index);
    int newIndex = state.activeTabIndex;
    
    // Adjust active index
    if (index < state.activeTabIndex) {
      newIndex--;
    } else if (index == state.activeTabIndex) {
      // Switched tab was closed, select the one to the left (or 0 if it was 0)
      newIndex = newIndex > 0 ? newIndex - 1 : 0;
    }

    state = state.copyWith(tabs: newTabs, activeTabIndex: newIndex);
  }

  void setActiveTab(int index) {
    if (index >= 0 && index < state.tabs.length) {
      state = state.copyWith(activeTabIndex: index);
    }
  }

  void updateTab(int index, {String? url, String? title, double? progress, bool? isSecure, bool? canGoBack, bool? canGoForward, Uint8List? screenshot, InAppWebViewController? controller}) {
    if (index >= 0 && index < state.tabs.length) {
      final updatedTabs = List<BrowserTab>.from(state.tabs);
      updatedTabs[index] = updatedTabs[index].copyWith(
        url: url,
        title: title,
        progress: progress,
        isSecure: isSecure,
        canGoBack: canGoBack,
        canGoForward: canGoForward,
        screenshot: screenshot,
        webViewController: controller,
      );
      state = state.copyWith(tabs: updatedTabs);
    }
  }

  void updateActiveTab({String? url, String? title, double? progress, bool? isSecure, bool? canGoBack, bool? canGoForward, Uint8List? screenshot, InAppWebViewController? controller}) {
    updateTab(
      state.activeTabIndex,
      url: url,
      title: title,
      progress: progress,
      isSecure: isSecure,
      canGoBack: canGoBack,
      canGoForward: canGoForward,
      screenshot: screenshot,
      controller: controller,
    );
  }
}

final browserTabsProvider = NotifierProvider<BrowserTabsNotifier, BrowserState>(BrowserTabsNotifier.new);
