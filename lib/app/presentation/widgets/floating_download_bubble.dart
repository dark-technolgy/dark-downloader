import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import '../../utils/incoming_link_utils.dart';

@pragma('vm:entry-point')
void overlayMain() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: FloatingDownloadBubble(),
    ),
  );
}

class FloatingDownloadBubble extends StatelessWidget {
  const FloatingDownloadBubble({super.key});

  Future<void> _sendClipboardUrl() async {
    final data = await Clipboard.getData('text/plain');
    final text = data?.text ?? '';
    final target = extractFirstDownloadTarget(text);
    if (target == null) {
      await FlutterOverlayWindow.shareData({'type': 'dd_clipboard_empty'});
      return;
    }
    await FlutterOverlayWindow.shareData({
      'type': 'dd_url',
      'url': target,
    });
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Center(
        child: Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF6C63FF), Color(0xFF3F3D56)],
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF6C63FF).withValues(alpha: 0.5),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: _sendClipboardUrl,
              splashColor: Colors.white.withValues(alpha: 0.3),
              child: const Padding(
                padding: EdgeInsets.all(16),
                child: Icon(
                  Icons.download_rounded,
                  color: Colors.white,
                  size: 28,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
