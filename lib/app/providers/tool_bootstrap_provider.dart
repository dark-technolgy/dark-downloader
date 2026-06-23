import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/tool_bootstrapper.dart';

/// ينتظر تنزيل/استخراج أدوات سطح المكتب (مثل FFmpeg) عند أول تشغيل.
///
/// على Android / iOS / macOS: يعيد فوراً. على ويندوز/لينُكس: قد يستغرق وقتاً
/// (تنزيل ~80MB+ مرة واحدة) مع اتصال إنترنت.
final toolBootstrapProvider = FutureProvider<void>((ref) async {
  if (kIsWeb) return;
  if (defaultTargetPlatform != TargetPlatform.windows &&
      defaultTargetPlatform != TargetPlatform.linux) {
    return;
  }
  await ToolBootstrapper.ensure();
});
