import 'dart:async';
import 'dart:io' show Platform;

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

import '../providers/floating_download_bubble_provider.dart';
import '../providers/incoming_link_provider.dart';
import '../utils/auth_callback_utils.dart';
import '../utils/incoming_link_utils.dart';

/// Subscribes to app/deep links and share intents, then forwards payloads to
/// [incomingRawLinkProvider]. Must sit under [ProviderScope].
class IncomingLinksBinding extends ConsumerStatefulWidget {
  const IncomingLinksBinding({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<IncomingLinksBinding> createState() =>
      _IncomingLinksBindingState();
}

class _IncomingLinksBindingState extends ConsumerState<IncomingLinksBinding>
    with WidgetsBindingObserver {
  final _appLinks = AppLinks();
  StreamSubscription<Uri>? _uriSub;
  StreamSubscription<List<SharedMediaFile>>? _shareSub;
  StreamSubscription<dynamic>? _overlaySub;

  static bool get _shareSupported =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  static bool get _overlayBridgeSupported => !kIsWeb && Platform.isAndroid;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initAppLinks();
    if (_shareSupported) {
      _initShareIntent();
    }
    if (_overlayBridgeSupported) {
      _initOverlayBridge();
    }
  }

  Future<void> _initAppLinks() async {
    _processWindowsProtocolLaunchArgs();

    try {
      final initial = await _appLinks.getInitialLink();
      if (initial != null) {
        _emitFromUri(initial);
      }
    } catch (_) {
      /* non-fatal */
    }

    try {
      _uriSub = _appLinks.uriLinkStream.listen(_emitFromUri, onError: (_) {});
    } catch (_) {
      /* non-fatal */
    }
  }

  /// Windows: email confirm opens the app via `com.darkdownloader://...` in argv.
  void _processWindowsProtocolLaunchArgs() {
    if (kIsWeb || !Platform.isWindows) return;
    for (final arg in Platform.executableArguments) {
      final trimmed = arg.trim();
      if (!trimmed.contains('darkdownloader')) continue;
      final uri = Uri.tryParse(trimmed);
      if (uri != null) {
        _emitFromUri(uri);
      }
    }
  }


  void _emitFromUri(Uri uri) {
    if (isAuthCallbackUri(uri)) {
      return;
    }
    final payload = uriToDownloadPayload(uri);
    if (payload == null) return;
    final normalized = extractFirstDownloadTarget(payload);
    if (normalized != null) {
      _offerIncomingDownload(normalized);
    }
  }

  void _offerIncomingDownload(String normalized) {
    ref.read(incomingRawLinkProvider.notifier).offer(normalized);
  }

  Future<void> _initShareIntent() async {
    try {
      final initial = await ReceiveSharingIntent.instance.getInitialMedia();
      _emitFromSharedMedia(initial);
      await ReceiveSharingIntent.instance.reset();
    } catch (_) {
      /* non-fatal */
    }

    try {
      _shareSub = ReceiveSharingIntent.instance.getMediaStream().listen((
        files,
      ) {
        _emitFromSharedMedia(files);
      }, onError: (_) {},);
    } catch (_) {
      /* non-fatal */
    }
  }

  void _emitFromSharedMedia(List<SharedMediaFile> files) {
    for (final f in files) {
      String? chunk;
      switch (f.type) {
        case SharedMediaType.text:
        case SharedMediaType.url:
          chunk = f.path;
          break;
        default:
          break;
      }
      if (f.message != null && f.message!.trim().isNotEmpty) {
        chunk = '${chunk ?? ''} ${f.message}'.trim();
      }
      if (chunk == null || chunk.isEmpty) continue;
      final normalized = extractFirstDownloadTarget(chunk);
      if (normalized != null) {
        _offerIncomingDownload(normalized);
        return;
      }
    }
  }

  void _initOverlayBridge() {
    _overlaySub = FlutterOverlayWindow.overlayListener.listen((message) {
      if (message is! Map) return;
      final type = message['type'];
      if (type == 'dd_url' && message['url'] is String) {
        _offerIncomingDownload(message['url'] as String);
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _overlayBridgeSupported) {
      ref.read(floatingDownloadBubbleProvider.notifier).syncOnResume();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _uriSub?.cancel();
    _shareSub?.cancel();
    _overlaySub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
