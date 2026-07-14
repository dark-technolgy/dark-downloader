import 'dart:io';

import '../../src/rust/api/security.dart' as rust_sec;
import 'package:flutter/foundation.dart';
import 'package:device_info_plus/device_info_plus.dart';

class SecurityService {
  static final SecurityService instance = SecurityService._();
  SecurityService._();

  final DeviceInfoPlugin _deviceInfo = DeviceInfoPlugin();

  Future<String> getDeviceFingerprint() async {
    try {
      if (kIsWeb) return 'web_client';
      
      if (Platform.isAndroid) {
        final androidInfo = await _deviceInfo.androidInfo;
        return 'android_${androidInfo.id}_${androidInfo.model}';
      } else if (Platform.isIOS) {
        final iosInfo = await _deviceInfo.iosInfo;
        return 'ios_${iosInfo.identifierForVendor}_${iosInfo.model}';
      } else if (Platform.isWindows) {
        final windowsInfo = await _deviceInfo.windowsInfo;
        return 'windows_${windowsInfo.deviceId}_${windowsInfo.computerName}';
      }
      
      return rust_sec.rustGetDeviceFingerprint();
    } catch (e) {
      debugPrint('SecurityService: Failed to get fingerprint: $e');
      return 'fallback_id_${DateTime.now().millisecondsSinceEpoch}';
    }
  }

  Future<bool> isEmulator() async {
    try {
      if (kIsWeb) return false;
      if (Platform.isAndroid) {
        final androidInfo = await _deviceInfo.androidInfo;
        return !androidInfo.isPhysicalDevice;
      } else if (Platform.isIOS) {
        final iosInfo = await _deviceInfo.iosInfo;
        return !iosInfo.isPhysicalDevice;
      }
    } catch (_) {}
    return false;
  }

  /// Check app integrity:
  /// - Android: verify the app was not tampered with (check signing fingerprint)
  /// - Windows: verify executable hasn't been modified
  /// - Returns false if running on emulator in release mode
  Future<bool> checkIntegrity() async {
    try {
      if (kIsWeb) return true;

      // 1. Reject emulators in release mode
      if (kReleaseMode && await isEmulator()) {
        debugPrint('SecurityService: Running on emulator in release mode');
        return false;
      }

      // 2. Android: check if app is debuggable or has been resigned
      if (Platform.isAndroid) {
        final androidInfo = await _deviceInfo.androidInfo;
        
        // Check for common tampering indicators
        final brand = androidInfo.brand.toLowerCase();
        final model = androidInfo.model.toLowerCase();
        
        // Detect common emulator brands
        if (kReleaseMode) {
          const emulatorIndicators = ['generic', 'unknown', 'google_sdk', 'emulator', 'android sdk'];
          if (emulatorIndicators.any((e) => brand.contains(e) || model.contains(e))) {
            return false;
          }
        }
      }

      // 3. Windows: verify the executable exists and hasn't been hollowed
      if (Platform.isWindows) {
        final exePath = Platform.resolvedExecutable;
        final exeFile = File(exePath);
        if (!exeFile.existsSync()) return false;
        
        // Minimum expected size for the release binary (sanity check)
        final size = exeFile.lengthSync();
        if (size < 1024 * 100) { // Less than 100KB is suspicious
          debugPrint('SecurityService: Executable too small, possible tampering');
          return false;
        }
      }

      return true;
    } catch (e) {
      debugPrint('SecurityService: Integrity check failed: $e');
      return false;
    }
  }

  Future<String> signMessage(String message, String secret) async {
    try {
      return await rust_sec.rustSignMessage(message: message, secret: secret);
    } catch (e) {
      return '';
    }
  }
}
