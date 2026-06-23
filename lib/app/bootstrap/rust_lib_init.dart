import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated_io.dart';
import 'package:path/path.dart' as p;

import '../../src/rust/frb_generated.dart';

/// Prefer the DLL/dylib/so next to the running executable (Flutter build output).
///
/// The generated [RustLib] defaults to looking under `rust/target/release/`
/// first. A stale developper artifact there shadows the freshly built library
/// next to `dark_downloader.exe`, causing content-hash mismatches while the
/// app still starts but loads the wrong binary.
Future<void> initRustLibBundledFirst() async {
  final path = _bundledRustLibraryPath();
  if (path != null) {
    await RustLib.init(externalLibrary: ExternalLibrary.open(path));
    return;
  }
  await RustLib.init();
}

String? _bundledRustLibraryPath() {
  if (kIsWeb) return null;
  try {
    final dir = File(Platform.resolvedExecutable).parent.path;
    if (Platform.isWindows) {
      final dll = p.join(dir, 'rust_lib_dark_downloader.dll');
      if (File(dll).existsSync()) return dll;
    } else if (Platform.isLinux) {
      final so = p.join(dir, 'librust_lib_dark_downloader.so');
      if (File(so).existsSync()) return so;
    } else if (Platform.isMacOS) {
      final dylib = p.join(dir, 'librust_lib_dark_downloader.dylib');
      if (File(dylib).existsSync()) return dylib;
    }
  } catch (_) {
    /* fall through */
  }
  return null;
}
