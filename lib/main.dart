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
    // This is where we would trigger scheduled downloads.
    // For now, we'll just log and return success.
    // In a real scenario, we'd need to init a minimal ProviderContainer
    // and call DownloadManager.checkScheduled().
    return Future.value(true);
  });
}

Future<void> main() async {
  final bootstrap = runZonedGuarded<Future<void>>(
    () async {
      WidgetsFlutterBinding.ensureInitialized();
      MediaKit.ensureInitialized();

      if (Platform.isAndroid || Platform.isIOS) {
        await Workmanager().initialize(callbackDispatcher);
        await Workmanager().registerPeriodicTask(
          "com.darkdownloader.scheduler",
          "checkScheduledDownloads",
          frequency: const Duration(minutes: 15),
          constraints: Constraints(networkType: NetworkType.connected),
        );
      }

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

        await TrayService().init();
      }

      const telemetryIngestUrl = String.fromEnvironment('TELEMETRY_INGEST_URL');
      const telemetryIngestToken =
          String.fromEnvironment('TELEMETRY_INGEST_TOKEN');
      await Telemetry.instance.init(
        tags: {
          'platform': defaultTargetPlatform.name,
          'build_mode': kReleaseMode
              ? 'release'
              : kProfileMode
              ? 'profile'
              : 'debug',
        },
        ingestUrl: telemetryIngestUrl.isEmpty ? null : telemetryIngestUrl,
        ingestToken:
            telemetryIngestToken.isEmpty ? null : telemetryIngestToken,
      );

      FlutterError.onError = (FlutterErrorDetails details) {
        FlutterError.presentError(details);
        Telemetry.instance.recordError(
          'flutter.error',
          details.exception,
          stackTrace: details.stack,
          context: {
            'library': details.library ?? 'unknown',
            'context': details.context?.toString() ?? 'unknown',
          },
        );
      };

      PlatformDispatcher.instance.onError = (error, stack) {
        Telemetry.instance.recordError(
          'platform.error',
          error,
          stackTrace: stack,
        );
        return true;
      };

      // Show splash immediately while heavy init happens
      runApp(const ColdStartShell());
      await _waitForFirstFrame();

      // Rust MUST init before Supabase — SupabaseConfig.init() calls
      // rustGetSupabaseConfig() which requires the Rust bridge.
      try {
        await initRustLibBundledFirst();
      } catch (e, st) {
        Telemetry.instance.recordError(
          'bootstrap.rust_init_failed',
          e,
          stackTrace: st,
        );
        runApp(BootstrapFatalApp(error: e));
        return;
      }

      await SupabaseConfig.init();



      try {
        await NotificationService.init();
      } catch (e, st) {
        Telemetry.instance.recordError(
          'notifications.init_failed',
          e,
          stackTrace: st,
        );
      }

      try {
        await ToolBootstrapper.ensure();
      } catch (e, st) {
        Telemetry.instance.recordError(
          'tool_bootstrap.ensure_failed',
          e,
          stackTrace: st,
        );
      }

      final container = ProviderContainer();
      final bridge = BrowserBridgeService(container);
      unawaited(bridge.start());

      runApp(
        UncontrolledProviderScope(
          container: container,
          child: IncomingLinksBinding(child: const DarkDownloaderApp()),
        ),
      );
    },
    (error, stack) {
      Telemetry.instance.recordError('zone.uncaught', error, stackTrace: stack);
    },
  );
  if (bootstrap != null) await bootstrap;
}

Future<void> _waitForFirstFrame() async {
  final completer = Completer<void>();
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (!completer.isCompleted) completer.complete();
  });
  await completer.future;
}

// Extracted widgets are in lib/app/presentation/screens and widgets

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
          textDirection: locale.languageCode == 'ar'
              ? TextDirection.rtl
              : TextDirection.ltr,
          child: remoteConfig.when(
            data: (config) {
              if (config.maintenanceMode) {
                return MaintenanceScreen(message: config.maintenanceMessage);
              }
              return VersionCheckWrapper(
                config: config,
                child: child!,
              );
            },
            loading: () => const ColdStartShell(),
            error: (err, st) => child!,
          ),
        );
      },
      home: const AuthGate(),
    );
  }
}

// Extracted VersionCheckWrapper

// Extracted MaintenanceScreen

final onboardingProvider = FutureProvider<bool>((ref) async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getBool('has_seen_onboarding') ?? false;
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
          return OnboardingScreen(
            onFinish: () {
              ref.invalidate(onboardingProvider);
            },
          );
        }

        if (authState.status == AuthStatus.initial || authState.status == AuthStatus.loading) {
          return const ColdStartShell();
        }

        if (!authState.isAuthenticated) {
          return const LoginScreen();
        }
        return const HomeScreen();
      },
      loading: () => const ColdStartShell(),
      error: (_, _) => const ColdStartShell(),
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
