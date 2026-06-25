import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';
import 'package:workmanager/workmanager.dart';

import 'package:media_kit/media_kit.dart';

import 'app/config/localization.dart';
import 'app/config/theme.dart';
import 'app/presentation/screens/home_screen.dart';
import 'app/presentation/screens/onboarding_screen.dart';
import 'app/services/tool_bootstrapper.dart';
import 'app/widgets/incoming_links_binding.dart';
import 'app/providers/locale_provider.dart';
import 'app/providers/theme_provider.dart';
import 'app/services/browser_bridge_service.dart';


import 'app/config/supabase_config.dart';
import 'app/presentation/screens/login_screen.dart';
import 'app/providers/auth_provider.dart';
import 'app/services/telemetry_service.dart';
import 'app/bootstrap/rust_lib_init.dart';
import 'app/services/notification_service.dart';
import 'app/services/tray_service.dart';
import 'app/providers/remote_config_provider.dart';


import 'app/presentation/screens/cold_start_screen.dart';
import 'app/presentation/screens/maintenance_screen.dart';
import 'app/presentation/widgets/version_check_wrapper.dart';
import 'app/presentation/widgets/floating_download_bubble.dart';

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    return Future.value(true);
  });
}

Future<void> main() async {
  // 1. Ensure Flutter is ready
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();

  // 2. Show the Splash screen immediately (before any async work)
  runApp(const ColdStartShell());

  // 3. Start initialization in a separate, non-blocking flow
  unawaited(_initializeSystem());
}

Future<void> _initializeSystem() async {
  final container = ProviderContainer();

  try {
    // A. Desktop Specific Init
    if (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
      await windowManager.ensureInitialized();
      WindowOptions windowOptions = const WindowOptions(
        size: Size(1100, 700),
        minimumSize: Size(800, 600),
        center: true,
        backgroundColor: Colors.transparent,
        skipTaskbar: false,
        titleBarStyle: TitleBarStyle.normal,
      );
      await windowManager.waitUntilReadyToShow(windowOptions, () async {
        await windowManager.show();
        await windowManager.focus();
      });
      await TrayService().init().catchError((e) => debugPrint('Tray init failed: $e'));
    }

    // B. Background Worker
    if (Platform.isAndroid || Platform.isIOS) {
      await Workmanager().initialize(callbackDispatcher).catchError((e) => debugPrint('Workmanager init failed: $e'));
    }

    // C. Telemetry & Error Tracking
    await Telemetry.instance.init(
      tags: {'platform': defaultTargetPlatform.name, 'build_mode': kReleaseMode ? 'release' : 'debug'},
    );

    // D. Core Engine Init (With Safety Timeouts)
    // This is often where Android hangs, so we add aggressive timeouts
    await initRustLibBundledFirst().timeout(const Duration(seconds: 7), onTimeout: () {
      debugPrint('⚠️ Rust Lib init timed out - continuing anyway');
    });

    await SupabaseConfig.init().timeout(const Duration(seconds: 10), onTimeout: () {
      debugPrint('⚠️ Supabase init timed out - network might be slow');
    });

    await NotificationService.init().catchError((e) => debugPrint('Notification init failed: $e'));
    await ToolBootstrapper.ensure().catchError((e) => debugPrint('Tool bootstrap failed: $e'));

    // E. Services
    final bridge = BrowserBridgeService(container);
    unawaited(bridge.start());

    // F. Finally, switch from Splash to Main App
    runApp(
      UncontrolledProviderScope(
        container: container,
        child: IncomingLinksBinding(child: const DarkDownloaderApp()),
      ),
    );

  } catch (e, st) {
    debugPrint('Critical Initialization Error: $e');
    Telemetry.instance.recordError('system.bootstrap_failed', e, stackTrace: st);
    
    // Fallback: try to launch the app even if some parts failed
    runApp(
      UncontrolledProviderScope(
        container: container,
        child: IncomingLinksBinding(child: const DarkDownloaderApp()),
      ),
    );
  }
}

class DarkDownloaderApp extends ConsumerWidget {
  const DarkDownloaderApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(localeProvider);
    final theme = ref.watch(themeProvider);
    final remoteConfig = ref.watch(remoteConfigProvider);

    return MaterialApp(
      title: AppLocalization.translate('app_name', locale),
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme(theme.primaryColor),
      darkTheme: AppTheme.darkTheme(theme.primaryColor),
      themeMode: theme.mode,
      locale: locale,
      supportedLocales: AppLocalization.supportedLocales,
      localizationsDelegates: AppLocalization.localizationsDelegates,
      builder: (context, child) {
        return Directionality(
          textDirection: locale.languageCode == 'ar' ? TextDirection.rtl : TextDirection.ltr,
          child: remoteConfig.when(
            data: (config) {
              if (config.maintenanceMode) {
                return MaintenanceScreen(message: config.maintenanceMessage);
              }
              return VersionCheckWrapper(config: config, child: child!);
            },
            loading: () => child!, // Don't show splash again inside the app
            error: (err, st) => child!,
          ),
        );
      },
      home: const AuthGate(),
    );
  }
}

final onboardingProvider = FutureProvider<bool>((ref) async {
  try {
    final prefs = await SharedPreferences.getInstance().timeout(const Duration(seconds: 3));
    return prefs.getBool('has_seen_onboarding') ?? false;
  } catch (_) {
    return false;
  }
});

class AuthGate extends ConsumerWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authProvider);
    final hasSeenOnboardingAsync = ref.watch(onboardingProvider);

    return hasSeenOnboardingAsync.when(
      data: (hasSeen) {
        if (!hasSeen) {
          return OnboardingScreen(onFinish: () => ref.invalidate(onboardingProvider));
        }
        if (authState.status == AuthStatus.initial || authState.status == AuthStatus.loading) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        if (!authState.isAuthenticated) return const LoginScreen();
        return const HomeScreen();
      },
      loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (_, _) => const LoginScreen(),
    );
  }
}

@pragma('vm:entry-point')
void overlayMain() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: FloatingDownloadBubble(),
    ),
  );
}
