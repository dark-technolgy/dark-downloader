import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

@pragma('vm:entry-point')
void startCallback() {
  FlutterForegroundTask.setTaskHandler(BackgroundDownloadHandler());
}

class BackgroundDownloadHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {}

  @override
  void onRepeatEvent(DateTime timestamp) {}

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTaskDestroyed) async {}

  @override
  void onReceiveData(Object data) {}
}

class BackgroundService {
  static Future<void> init() async {
    if (kIsWeb || !Platform.isAndroid) return;

    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'download_foreground',
        channelName: 'Foreground Download',
        channelDescription: 'Keeps downloads active in background',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: false,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.nothing(),
        autoRunOnBoot: false,
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );
  }

  static Future<void> start() async {
    if (kIsWeb || !Platform.isAndroid) return;
    try {
      if (!await FlutterForegroundTask.isRunningService) {
        await FlutterForegroundTask.startService(
          notificationTitle: 'Dark Downloader',
          notificationText: 'Downloading files...',
          callback: startCallback,
        );
      }
    } catch (_) {}
  }

  static Future<void> stop() async {
    if (kIsWeb || !Platform.isAndroid) return;
    try {
      await FlutterForegroundTask.stopService();
    } catch (_) {}
  }

  static Future<void> update(String title, String text) async {
    if (kIsWeb || !Platform.isAndroid) return;
    try {
      await FlutterForegroundTask.updateService(
        notificationTitle: title,
        notificationText: text,
      );
    } catch (_) {}
  }
}
