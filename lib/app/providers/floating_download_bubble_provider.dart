import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/brand_config.dart';

const _kFloatingBubblePref = 'floating_download_bubble_v1';

/// Android-only: draggable floating button over other apps. Sends clipboard URL to main app.
class FloatingDownloadBubbleNotifier extends Notifier<bool> {
  @override
  bool build() {
    _hydrate();
    return false;
  }

  Future<void> _hydrate() async {
    final prefs = await SharedPreferences.getInstance();
    final enabled = prefs.getBool(_kFloatingBubblePref) ?? false;
    state = enabled;
    if (enabled && _isAndroid) {
      await _ensureOverlayVisible();
    }
  }

  bool get _isAndroid => !kIsWeb && Platform.isAndroid;

  Future<void> setEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kFloatingBubblePref, enabled);
    state = enabled;

    if (!_isAndroid) return;

    if (!enabled) {
      try {
        await FlutterOverlayWindow.closeOverlay();
      } catch (_) {}
      return;
    }

    var ok = await FlutterOverlayWindow.isPermissionGranted();
    if (!ok) {
      try {
        await FlutterOverlayWindow.requestPermission();
      } catch (_) {}
      ok = await FlutterOverlayWindow.isPermissionGranted();
    }
    if (ok) {
      await _showOverlay();
    }
  }

  /// After returning from system settings (overlay permission).
  Future<void> syncOnResume() async {
    if (!state || !_isAndroid) return;
    await _ensureOverlayVisible();
  }

  Future<void> _ensureOverlayVisible() async {
    if (!state || !_isAndroid) return;
    final perm = await FlutterOverlayWindow.isPermissionGranted();
    if (!perm) return;
    final active = await FlutterOverlayWindow.isActive();
    if (!active) {
      await _showOverlay();
    }
  }

  Future<void> _showOverlay() async {
    try {
      await FlutterOverlayWindow.showOverlay(
        height: 72,
        width: 72,
        alignment: OverlayAlignment.centerRight,
        enableDrag: true,
        positionGravity: PositionGravity.auto,
        overlayTitle: kBrandNameAr,
        overlayContent: kBrandNameAr,
        flag: OverlayFlag.defaultFlag,
      );
    } catch (e) {
      if (kDebugMode) {
        // ignore: avoid_print
        print('[floating_overlay] showOverlay failed: $e');
      }
    }
  }
}

final floatingDownloadBubbleProvider =
    NotifierProvider<FloatingDownloadBubbleNotifier, bool>(FloatingDownloadBubbleNotifier.new);
