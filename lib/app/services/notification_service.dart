import 'dart:io';

import 'package:flutter/material.dart' show Locale;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:open_file/open_file.dart';
import 'package:local_notifier/local_notifier.dart';

import '../config/localization.dart';

class NotificationService {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _initialized = false;

  static Future<void> init() async {
    if (_initialized) return;

    // Windows support for flutter_local_notifications is limited and requires 
    // specific shell setup. We disable it for Windows for now to prevent crashes.
    if (Platform.isWindows) {
      await localNotifier.setup(appName: 'Dark Downloader');
      _initialized = true;
      return;
    }

    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    const macos = DarwinInitializationSettings();
    const linux = LinuxInitializationSettings(defaultActionName: 'Open');

    await _plugin.initialize(
      settings: const InitializationSettings(
        android: android,
        iOS: ios,
        macOS: macos,
        linux: linux,
      ),
      onDidReceiveNotificationResponse: _onSelectNotification,
    );
    _initialized = true;
  }

  static void _onSelectNotification(NotificationResponse response) async {
    final payload = response.payload;
    final actionId = response.actionId;

    if (actionId == 'pause_download') {
      // We will need a way to trigger pause from here. 
      // Since this is a static service, we might need a callback or a Stream.
      return;
    }

    if (payload != null && payload.isNotEmpty) {
      final file = File(payload);
      if (file.existsSync()) {
        await OpenFile.open(payload);
      }
    }
  }

  static Future<void> showProgress({
    required int id,
    required String title,
    required String body,
    required int progress,
    required int maxProgress,
    required Locale locale,
  }) async {
    if (!_initialized) await init();

    final trDownloads = AppLocalization.translate('notif_channel_downloads', locale);
    final trDesc = AppLocalization.translate('notif_channel_downloads_desc', locale);

    final android = AndroidNotificationDetails(
      'download_channel',
      trDownloads,
      channelDescription: trDesc,
      channelShowBadge: false,
      importance: Importance.low,
      priority: Priority.low,
      onlyAlertOnce: true,
      showProgress: true,
      maxProgress: maxProgress,
      progress: progress,
      indeterminate: maxProgress == 0,
      ongoing: true,
      autoCancel: false,
      actions: <AndroidNotificationAction>[
        AndroidNotificationAction(
          'pause_download',
          AppLocalization.translate('pause', locale),
          showsUserInterface: true,
          cancelNotification: false,
        ),
      ],
    );

    const ios = DarwinNotificationDetails(
      presentAlert: false,
      presentBadge: false,
      presentSound: false,
    );

    if (Platform.isWindows) {
      // Progress not easily supported in native windows notifications without complex bindings
      // We will skip progress for Windows to avoid spam.
      return;
    }

    await _plugin.show(
      id: id,
      title: title,
      body: body,
      notificationDetails: NotificationDetails(android: android, iOS: ios, macOS: ios),
    );
  }

  static Future<void> showComplete({
    required int id,
    required String title,
    required String filePath,
    required Locale locale,
  }) async {
    if (!_initialized) await init();

    final trDownloads = AppLocalization.translate('notif_channel_downloads', locale);
    final trDesc = AppLocalization.translate('notif_channel_downloads_desc', locale);
    final trComplete = AppLocalization.translate('notif_download_complete', locale);
    final trOpen = AppLocalization.translate('notif_open_file', locale);

    final android = AndroidNotificationDetails(
      'download_channel',
      trDownloads,
      channelDescription: trDesc,
      importance: Importance.high,
      priority: Priority.high,
      autoCancel: true,
      category: AndroidNotificationCategory.status,
      actions: <AndroidNotificationAction>[
        AndroidNotificationAction(
          'open_file',
          trOpen,
          showsUserInterface: true,
        ),
      ],
    );
    const ios = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
      interruptionLevel: InterruptionLevel.critical,
    );

    if (Platform.isWindows) {
      final notif = LocalNotification(
        title: trComplete,
        body: title,
      );
      notif.onClick = () async {
        final file = File(filePath);
        if (file.existsSync()) {
          await OpenFile.open(filePath);
        }
      };
      await notif.show();
      return;
    }

    await _plugin.show(
      id: id,
      title: trComplete,
      body: title,
      notificationDetails: NotificationDetails(
        android: android,
        iOS: ios,
        macOS: ios,
      ),
      payload: filePath,
    );
  }

  static Future<void> showInfo({
    required int id,
    required String title,
    required String body,
    required Locale locale,
  }) async {
    if (!_initialized) await init();

    final trDownloads = AppLocalization.translate('notif_channel_downloads', locale);
    final trDesc = AppLocalization.translate('notif_channel_downloads_desc', locale);

    final android = AndroidNotificationDetails(
      'download_channel',
      trDownloads,
      channelDescription: trDesc,
      channelShowBadge: false,
      importance: Importance.low,
      priority: Priority.low,
      onlyAlertOnce: true,
      autoCancel: true,
    );
    const ios = DarwinNotificationDetails(
      presentAlert: false,
      presentBadge: false,
      presentSound: false,
    );

    if (Platform.isWindows) {
      final notif = LocalNotification(
        title: title,
        body: body,
      );
      await notif.show();
      return;
    }

    await _plugin.show(
      id: id,
      title: title,
      body: body,
      notificationDetails: NotificationDetails(android: android, iOS: ios, macOS: ios),
    );
  }

  static Future<void> showError({
    required int id,
    required String title,
    required String error,
    required Locale locale,
  }) async {
    if (!_initialized) await init();

    final trDownloads = AppLocalization.translate('notif_channel_downloads', locale);
    final line = AppLocalization.translate('notif_download_failed_line', locale).replaceAll('{title}', title);

    final android = AndroidNotificationDetails(
      'download_channel',
      trDownloads,
      importance: Importance.high,
      priority: Priority.high,
    );
    const ios = DarwinNotificationDetails();

    if (Platform.isWindows) {
      final notif = LocalNotification(
        title: line,
        body: error,
      );
      await notif.show();
      return;
    }

    await _plugin.show(
      id: id,
      title: line,
      body: error,
      notificationDetails: NotificationDetails(android: android, iOS: ios, macOS: ios),
    );
  }

  static Future<void> cancel(int id) async {
    if (!_initialized) return;
    await _plugin.cancel(id: id);
  }

  static bool get isSupported =>
      Platform.isAndroid || Platform.isIOS || Platform.isMacOS || Platform.isLinux;
}
