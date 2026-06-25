import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:file_picker/file_picker.dart';
import '../../src/rust/api/video_processor.dart' as rust_video_processor;
import '../services/bundled_ffmpeg_path.dart';

enum ToolkitTaskStatus { idle, processing, success, error }

class ToolkitState {
  final ToolkitTaskStatus status;
  final String? statusMessage;
  final double progress; // 0.0 to 1.0

  ToolkitState({
    this.status = ToolkitTaskStatus.idle,
    this.statusMessage,
    this.progress = 0,
  });

  ToolkitState copyWith({
    ToolkitTaskStatus? status,
    String? statusMessage,
    double? progress,
  }) {
    return ToolkitState(
      status: status ?? this.status,
      statusMessage: statusMessage ?? this.statusMessage,
      progress: progress ?? this.progress,
    );
  }
}

class ToolkitNotifier extends Notifier<ToolkitState> {
  @override
  ToolkitState build() => ToolkitState();

  Future<void> convertToMp3() async {

    final result = await FilePicker.platform.pickFiles(type: FileType.video);
    if (result == null || result.files.single.path == null) return;

    state = state.copyWith(status: ToolkitTaskStatus.processing, statusMessage: 'جاري استخراج الصوت بجودة 320kbps...');
    
    final inputPath = result.files.single.path!;
    final outputDir = await getDownloadsDirectory();
    final fileName = p.basenameWithoutExtension(inputPath);
    final outputPath = p.join(outputDir!.path, 'DarkDownloader', '${fileName}_320k.mp3');

    final ffmpegPath = await resolveDesktopFfmpegPath();
    try {
      rust_video_processor.convertToMp3(
        inputPath: inputPath,
        outputPath: outputPath,
        ffmpegPath: ffmpegPath,
      );
      state = state.copyWith(status: ToolkitTaskStatus.success, statusMessage: 'تم الحفظ في: $outputPath');
    } catch (e) {
      state = state.copyWith(status: ToolkitTaskStatus.error, statusMessage: 'فشل التحويل: $e');
    }
  }

  Future<void> compressVideo() async {

    final result = await FilePicker.platform.pickFiles(type: FileType.video);
    if (result == null || result.files.single.path == null) return;

    state = state.copyWith(status: ToolkitTaskStatus.processing, statusMessage: 'جاري ضغط الفيديو مع الحفاظ على الجودة...');

    final inputPath = result.files.single.path!;
    final outputDir = await getDownloadsDirectory();
    final fileName = p.basenameWithoutExtension(inputPath);
    final ext = p.extension(inputPath);
    final outputPath = p.join(outputDir!.path, 'DarkDownloader', '${fileName}_compressed$ext');

    final ffmpegPath = await resolveDesktopFfmpegPath();
    try {
      rust_video_processor.compressVideo(
        inputPath: inputPath,
        outputPath: outputPath,
        ffmpegPath: ffmpegPath,
      );
      state = state.copyWith(status: ToolkitTaskStatus.success, statusMessage: 'تم الضغط بنجاح: $outputPath');
    } catch (e) {
      state = state.copyWith(status: ToolkitTaskStatus.error, statusMessage: 'فشل الضغط: $e');
    }
  }

  void reset() => state = ToolkitState();
}

final toolkitProvider = NotifierProvider<ToolkitNotifier, ToolkitState>(ToolkitNotifier.new);
