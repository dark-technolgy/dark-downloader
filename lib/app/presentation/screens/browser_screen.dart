import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:webview_flutter/webview_flutter.dart' as mobile;
import 'package:webview_windows/webview_windows.dart' as win;
import '../../providers/incoming_link_provider.dart';

class BrowserScreen extends ConsumerStatefulWidget {
  final String initialUrl;
  const BrowserScreen({this.initialUrl = 'https://www.google.com', super.key});

  @override
  ConsumerState<BrowserScreen> createState() => _BrowserScreenState();
}

class _BrowserScreenState extends ConsumerState<BrowserScreen> {
  // Mobile Controller
  mobile.WebViewController? _mobileController;
  
  // Windows Controller
  final _winController = win.WebviewController();
  
  bool _canDownload = false;
  String? _currentUrl;
  double _loadingProgress = 0;
  bool _isWindows = false;
  bool _winInited = false;

  @override
  void initState() {
    super.initState();
    _currentUrl = widget.initialUrl;
    _isWindows = Platform.isWindows;
    
    if (_isWindows) {
      _initWindowsWebview();
    } else {
      _initMobileWebview();
    }
  }

  Future<void> _initWindowsWebview() async {
    try {
      await _winController.initialize();
      await _winController.setPopupWindowPolicy(win.WebviewPopupWindowPolicy.deny);
      
      _winController.url.listen((url) {
        if (mounted) {
          setState(() {
            _currentUrl = url;
            _canDownload = _isSupportedPlatform(url);
          });
        }
      });

      _winController.loadingState.listen((state) {
        if (state == win.LoadingState.loading) {
          if (mounted) setState(() => _loadingProgress = 0.5);
        } else {
          if (mounted) setState(() => _loadingProgress = 1.0);
          _winSniffer();
        }
      });

      await _winController.loadUrl(widget.initialUrl);
      if (mounted) setState(() => _winInited = true);
    } catch (e) {
      debugPrint('Windows Webview Error: $e');
    }
  }

  void _initMobileWebview() {
    _mobileController = mobile.WebViewController()
      ..setJavaScriptMode(mobile.JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        mobile.NavigationDelegate(
          onProgress: (int progress) {
            if (mounted) setState(() => _loadingProgress = progress / 100);
          },
          onPageStarted: (String url) {
            if (mounted) {
              setState(() {
                _currentUrl = url;
                _canDownload = _isSupportedPlatform(url);
              });
            }
          },
          onPageFinished: (String url) {
            _mobileSniffer();
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

  Future<void> _mobileSniffer() async {
    if (_mobileController == null) return;
    try {
      final hasVideo = await _mobileController!.runJavaScriptReturningResult(
        "document.getElementsByTagName('video').length > 0",
      );
      if (hasVideo == true && mounted) {
        setState(() => _canDownload = true);
      }
    } catch (_) {}
  }

  Future<void> _winSniffer() async {
    try {
      final hasVideo = await _winController.executeScript(
        "document.getElementsByTagName('video').length > 0",
      );
      if (hasVideo == true && mounted) {
        setState(() => _canDownload = true);
      }
    } catch (_) {}
  }

  void _triggerDownload() {
    if (_currentUrl == null) return;
    ref.read(pendingExtractorUrlProvider.notifier).set(_currentUrl);
    Navigator.pop(context);
  }

  @override
  void dispose() {
    if (_isWindows) _winController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_currentUrl ?? 'Browser', style: const TextStyle(fontSize: 14)),
        bottom: _loadingProgress < 1.0
            ? PreferredSize(
                preferredSize: const Size.fromHeight(2),
                child: LinearProgressIndicator(value: _loadingProgress, minHeight: 2),
              )
            : null,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              if (_isWindows) {
                _winController.reload();
              } else {
                _mobileController?.reload();
              }
            },
          ),
        ],
      ),
      body: _isWindows 
          ? (_winInited 
              ? win.Webview(_winController) 
              : const Center(child: CircularProgressIndicator()))
          : (_mobileController != null 
              ? mobile.WebViewWidget(controller: _mobileController!)
              : const Center(child: CircularProgressIndicator())),
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
