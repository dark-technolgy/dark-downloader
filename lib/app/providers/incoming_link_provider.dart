import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Raw link text from OS share sheet, browser "Open in app", or deep link.
final incomingRawLinkProvider =
    NotifierProvider<IncomingRawLinkNotifier, String?>(IncomingRawLinkNotifier.new);

class IncomingRawLinkNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void offer(String value) {
    final v = value.trim();
    if (v.isEmpty) return;
    state = v;
  }

  void clear() => state = null;
}

class PendingExtractorUrlNotifier extends Notifier<String?> {
  @override
  String? build() => null;
  void set(String? value) => state = value;
}

/// Set by [HomeScreen] when routing video URLs to the home extractor tab.
final pendingExtractorUrlProvider = NotifierProvider<PendingExtractorUrlNotifier, String?>(PendingExtractorUrlNotifier.new);

class PendingBrowserUrlNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void set(String? value) {
    if (value == null) {
      state = null;
      return;
    }
    final t = value.trim();
    state = t.isEmpty ? null : t;
  }
}

/// URL for [BrowserScreen] to load (platform shortcuts, legal pages, etc.).
final pendingBrowserUrlProvider =
    NotifierProvider<PendingBrowserUrlNotifier, String?>(PendingBrowserUrlNotifier.new);

class OpenBrowserTabNotifier extends Notifier<int> {
  @override
  int build() => 0;

  void request() => state++;
}

/// Increment to switch [HomeScreen] to the in-app browser tab.
final openBrowserTabRequestProvider =
    NotifierProvider<OpenBrowserTabNotifier, int>(OpenBrowserTabNotifier.new);
