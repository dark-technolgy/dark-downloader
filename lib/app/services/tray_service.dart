import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

class TrayService with TrayListener {
  static final TrayService _instance = TrayService._internal();

  factory TrayService() {
    return _instance;
  }

  TrayService._internal();

  Future<void> init() async {
    if (kIsWeb || (!Platform.isWindows && !Platform.isLinux && !Platform.isMacOS)) {
      return;
    }

    trayManager.addListener(this);

    await trayManager.setIcon(
      Platform.isWindows ? 'assets/branding/icon.ico' : 'assets/branding/icon.png',
    );
    await trayManager.setToolTip('Dark Downloader');

    Menu menu = Menu(
      items: [
        MenuItem(
          key: 'show_window',
          label: 'إظهار البرنامج',
        ),
        MenuItem.separator(),
        MenuItem(
          key: 'exit_app',
          label: 'إغلاق',
        ),
      ],
    );

    await trayManager.setContextMenu(menu);
  }

  @override
  void onTrayIconMouseDown() {
    windowManager.show();
    windowManager.focus();
  }

  @override
  void onTrayIconRightMouseDown() {
    trayManager.popUpContextMenu();
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    if (menuItem.key == 'show_window') {
      windowManager.show();
      windowManager.focus();
    } else if (menuItem.key == 'exit_app') {
      windowManager.destroy();
      exit(0);
    }
  }

  void dispose() {
    trayManager.removeListener(this);
  }
}
