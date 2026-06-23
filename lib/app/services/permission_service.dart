import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'telemetry_service.dart';

/// Summary of a permission request.
class PermissionResult {
  final bool granted;
  final bool permanentlyDenied;
  final String? reason;
  const PermissionResult({
    required this.granted,
    this.permanentlyDenied = false,
    this.reason,
  });
}

class PermissionService {
  static final _deviceInfo = DeviceInfoPlugin();
  static int? _cachedAndroidSdk;

  /// Request every permission required to start a download.
  ///
  /// Notification permission is best-effort (a user may decline it and still
  /// use the app); storage / media access is mandatory on mobile.
  static Future<PermissionResult> requestDownloadPermissions() async {
    if (!Platform.isAndroid && !Platform.isIOS) {
      return const PermissionResult(granted: true);
    }

    try {
      if (Platform.isAndroid) {
        return await _requestAndroid();
      } else {
        return await _requestIOS();
      }
    } catch (e, st) {
      Telemetry.instance.recordError(
        'permissions.request_failed',
        e,
        stackTrace: st,
      );
      return PermissionResult(granted: false, reason: e.toString());
    }
  }

  static Future<PermissionResult> _requestAndroid() async {
    final sdk = await _androidSdkInt() ?? 33;

    final required = <Permission>[];
    if (sdk >= 33) {
      // Android 13+: scoped media permissions.
      required.addAll([Permission.videos, Permission.audio, Permission.photos]);
    } else {
      // Android 12 and older: storage permission.
      required.add(Permission.storage);
    }

    final statuses = <Permission, PermissionStatus>{};
    for (final p in required) {
      statuses[p] = await p.request();
    }
    // Best-effort notification permission on Android 13+.
    if (sdk >= 33) {
      await Permission.notification.request();
    }

    final anyGranted =
        statuses.values.any((s) => s.isGranted || s.isLimited);
    final permanentlyDenied =
        statuses.values.every((s) => s.isPermanentlyDenied);

    if (anyGranted) return const PermissionResult(granted: true);
    return PermissionResult(
      granted: false,
      permanentlyDenied: permanentlyDenied,
      reason: permanentlyDenied
          ? 'الصلاحيات مرفوضة نهائياً — افتح الإعدادات وفعّلها يدوياً'
          : 'لم يتم منح صلاحية التخزين',
    );
  }

  static Future<PermissionResult> _requestIOS() async {
    final photos = await Permission.photos.request();
    await Permission.notification.request();
    if (photos.isGranted || photos.isLimited) {
      return const PermissionResult(granted: true);
    }
    return PermissionResult(
      granted: false,
      permanentlyDenied: photos.isPermanentlyDenied,
      reason: 'يرجى السماح بالوصول للصور لحفظ التحميلات',
    );
  }

  /// True if storage / media access is already granted (does not prompt).
  static Future<bool> hasStoragePermission() async {
    if (!Platform.isAndroid && !Platform.isIOS) return true;
    try {
      if (Platform.isAndroid) {
        final sdk = await _androidSdkInt() ?? 33;
        if (sdk >= 33) {
          final v = await Permission.videos.status;
          final a = await Permission.audio.status;
          final p = await Permission.photos.status;
          return v.isGranted || a.isGranted || p.isGranted;
        }
        return (await Permission.storage.status).isGranted;
      }
      return (await Permission.photos.status).isGranted;
    } catch (e, st) {
      Telemetry.instance.recordError(
        'permissions.status_check_failed',
        e,
        stackTrace: st,
      );
      return false;
    }
  }

  /// Opens the OS-level settings page for this app so a user can enable
  /// permissions they previously denied permanently.
  static Future<bool> openSettings() async {
    try {
      return await openAppSettings();
    } catch (e, st) {
      Telemetry.instance.recordError(
        'permissions.open_settings_failed',
        e,
        stackTrace: st,
      );
      return false;
    }
  }

  static Future<int?> _androidSdkInt() async {
    if (_cachedAndroidSdk != null) return _cachedAndroidSdk;
    if (!Platform.isAndroid) return null;
    try {
      final info = await _deviceInfo.androidInfo;
      _cachedAndroidSdk = info.version.sdkInt;
      return _cachedAndroidSdk;
    } catch (e, st) {
      Telemetry.instance.recordError(
        'permissions.sdk_detect_failed',
        e,
        stackTrace: st,
      );
      return null;
    }
  }

  // Backwards compatibility for the old requestStoragePermission call
  @Deprecated('Use requestDownloadPermissions instead')
  static Future<bool> requestStoragePermission() async {
    final result = await requestDownloadPermissions();
    return result.granted;
  }
}
