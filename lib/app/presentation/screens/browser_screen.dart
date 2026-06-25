import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../../providers/incoming_link_provider.dart';

class BrowserScreen extends ConsumerStatefulWidget {
  final String initialUrl;
  const BrowserScreen({this.initialUrl = 'https://www.google.com', super.key});

  @override
  ConsumerState<BrowserScreen> createState() => _BrowserScreenState();
}

class _BrowserScreenState extends ConsumerState<BrowserScreen> {
  late final WebViewController _controller;
  bool _canDownload = false;
  String? _currentUrl;
  double _loadingProgress = 0;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (int progress) {
            setState(() => _loadingProgress = progress / 100);
          },
          onPageStarted: (String url) {
            setState(() {
              _currentUrl = url;
              _canDownload = _isSupportedPlatform(url);
            });
          },
          onPageFinished: (String url) {
            _sniffer();
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.initialUrl));
  }

  bool _isSupportedPlatform(String url) {
    final u = url.toLowerCase();
    return u.contains('youtube.com') ||
        u.contains('youtu.be') ||
        u.contains('tiktok.com') ||
        u.contains('instagram.com') ||
        u.contains('facebook.com') ||
        u.contains('twitter.com') ||
        u.contains('x.com') ||
        u.contains('vimeo.com');
  }

  Future<void> _sniffer() async {
    // Basic JS sniffer to find video tags
    final hasVideo = await _controller.runJavaScriptReturningResult(
      "document.getElementsByTagName('video').length > 0"
    );
    if (hasVideo == true) {
      setState(() => _canDownload = true);
    }
  }

  void _triggerDownload() {
    if (_currentUrl == null) return;
    ref.read(pendingExtractorUrlProvider.notifier).set(_currentUrl);
    Navigator.pop(context); // Close browser and start analysis on home
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_currentUrl ?? 'Browser'),
        bottom: _loadingProgress < 1.0
            ? PreferredSize(
                preferredSize: const Size.fromHeight(2),
                child: LinearProgressIndicator(value: _loadingProgress, minHeight: 2),
              )
            : null,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => _controller.reload(),
          ),
        ],
      ),
      body: WebViewWidget(controller: _controller),
      floatingActionButton: _canDownload
          ? FloatingActionButton.extended(
              onPressed: _triggerDownload,
              label: const Text('تحميل الفيديو', style: TextStyle(fontWeight: FontWeight.bold)),
              icon: const Icon(Icons.download_rounded),
              backgroundColor: Theme.of(context).colorScheme.primary,
              foregroundColor: Colors.white,
            )
          : null,
    );
  }
}
