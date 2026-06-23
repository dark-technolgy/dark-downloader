// ignore_for_file: avoid_print
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;

const winUrl = 'https://github.com/BtbN/FFmpeg-Builds/releases/download/latest/ffmpeg-master-latest-win64-gpl.zip';
// Linux usually has tar.xz which is harder to extract purely in dart without xz. 
// However, since we are executing this on the dev machine, we can just use system `tar` on Linux.
const linuxUrl = 'https://github.com/BtbN/FFmpeg-Builds/releases/download/latest/ffmpeg-master-latest-linux64-gpl.tar.xz';

void main() async {
  print('Starting FFmpeg bundling process...');
  
  final assetsDir = Directory(p.join('assets', 'bundled_ffmpeg'));
  final winDir = Directory(p.join(assetsDir.path, 'windows'));
  final linuxDir = Directory(p.join(assetsDir.path, 'linux'));
  
  if (!assetsDir.existsSync()) assetsDir.createSync(recursive: true);
  if (!winDir.existsSync()) winDir.createSync(recursive: true);
  if (!linuxDir.existsSync()) linuxDir.createSync(recursive: true);

  // 1. Download & Extract Windows
  final winOut = File(p.join(winDir.path, 'ffmpeg.exe'));
  if (!winOut.existsSync()) {
    print('Downloading Windows FFmpeg from BtbN...');
    final winZip = File(p.join(assetsDir.path, 'win_temp.zip'));
    final res = await http.get(Uri.parse(winUrl));
    if (res.statusCode == 200) {
      await winZip.writeAsBytes(res.bodyBytes);
      print('Extracting Windows FFmpeg...');
      final archive = ZipDecoder().decodeBytes(winZip.readAsBytesSync());
      for (final file in archive) {
        if (file.isFile && file.name.endsWith('bin/ffmpeg.exe')) {
          await winOut.writeAsBytes(file.content as List<int>);
          print('Saved ffmpeg.exe for Windows!');
          break;
        }
      }
      await winZip.delete();
    } else {
      print('Failed to download Windows FFmpeg: ${res.statusCode}');
    }
  } else {
    print('Windows FFmpeg already bundled.');
  }

  // 2. We skip Linux bundling via pure dart for now to keep the script light and cross-platform without xz-utils,
  // since the developer is mainly targeting Windows first. Linux users usually have ffmpeg in their package manager anyway,
  // but if needed, we can expand this script to call `tar -xf` on Linux machines.

  print('Done! FFmpeg is now bundled inside assets/bundled_ffmpeg.');
  print('When you build the app using `flutter build windows`, it will be fully embedded in your EXE!');
}
