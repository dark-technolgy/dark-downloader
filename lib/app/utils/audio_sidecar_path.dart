import 'dart:io';

import 'package:path/path.dart' as p;

/// يجب أن يبقى منطق امتداد ملف الصوت الجانبي مطابقاً لـ
/// `audio_ext_from_url` في `rust/src/api/downloader.rs` وإلا يفشل الدمج ويبقى
/// فيديو بلا صوت + ملف صوت منفصل.
String audioExtFromUrl(String url, String videoExtLower) {
  final u = url.toLowerCase();
  if (u.contains('mime=audio%2fwebm') || u.contains('mime=audio/webm')) {
    return 'webm';
  }
  if (u.contains('mime=audio%2fmp4') || u.contains('mime=audio/mp4')) {
    return 'm4a';
  }
  if (videoExtLower == 'webm') return 'webm';
  return 'm4a';
}

/// المسار المتوقع لملف الصوت بجانب ملف الفيديو (كما يكتبه محرك Rust).
String expectedAudioSidecarPath(String videoPath, String audioUrl) {
  final stem = p.basenameWithoutExtension(videoPath);
  var videoExt = p.extension(videoPath);
  if (videoExt.startsWith('.')) videoExt = videoExt.substring(1);
  if (videoExt.isEmpty) videoExt = 'mp4';
  final ext = audioExtFromUrl(audioUrl, videoExt.toLowerCase());
  return p.join(p.dirname(videoPath), '$stem.audio.$ext');
}

/// يحاول المسار المتوقع ثم أي ملف يطابق `اسم_الفيديو.audio.*` في نفس المجلد.
Future<String?> resolveAudioSidecarPath(String videoPath, String audioUrl) async {
  final expected = expectedAudioSidecarPath(videoPath, audioUrl);
  if (await File(expected).exists()) return expected;

  final stem = p.basenameWithoutExtension(videoPath);
  final dir = Directory(p.dirname(videoPath));
  if (!await dir.exists()) return null;

  final prefix = '$stem.audio.';
  String? found;
  await for (final ent in dir.list(followLinks: false)) {
    if (ent is! File) continue;
    final name = p.basename(ent.path);
    if (name.startsWith(prefix)) {
      found = ent.path;
      break;
    }
  }
  return found;
}

/// حذف كل ملفات الصوت الجانبية المرتبطة بمسار الفيديو (للإلغاء / التنظيف).
void deleteAudioSidecarFiles(String videoPath) {
  final stem = p.basenameWithoutExtension(videoPath);
  final dir = Directory(p.dirname(videoPath));
  if (!dir.existsSync()) return;
  final prefix = '$stem.audio.';
  for (final ent in dir.listSync(followLinks: false)) {
    if (ent is! File) continue;
    if (p.basename(ent.path).startsWith(prefix)) {
      try {
        ent.deleteSync();
      } catch (_) {}
    }
  }
}
