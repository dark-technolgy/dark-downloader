import 'dart:io';

import 'package:open_file/open_file.dart';

/// Opens the folder containing [filePath] in the system file manager when possible.
Future<bool> openDownloadFolder(String filePath) async {
  final trimmed = filePath.trim();
  if (trimmed.isEmpty) return false;

  final entity = File(trimmed);
  if (await entity.exists()) {
    final parent = entity.parent.path;
    if (Platform.isWindows) {
      final normalized = entity.absolute.path.replaceAll('/', '\\');
      final result = await Process.run('explorer', ['/select,', normalized]);
      return result.exitCode == 0;
    }
    if (Platform.isMacOS) {
      final result = await Process.run('open', ['-R', entity.absolute.path]);
      return result.exitCode == 0;
    }
    if (Platform.isLinux) {
      final result = await Process.run('xdg-open', [parent]);
      return result.exitCode == 0;
    }
    return (await OpenFile.open(parent)).type == ResultType.done;
  }

  final dir = Directory(trimmed);
  if (await dir.exists()) {
    if (Platform.isWindows) {
      final result = await Process.run('explorer', [dir.absolute.path]);
      return result.exitCode == 0;
    }
    if (Platform.isMacOS) {
      final result = await Process.run('open', [dir.absolute.path]);
      return result.exitCode == 0;
    }
    if (Platform.isLinux) {
      final result = await Process.run('xdg-open', [dir.absolute.path]);
      return result.exitCode == 0;
    }
    return (await OpenFile.open(dir.path)).type == ResultType.done;
  }

  return false;
}
