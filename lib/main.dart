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
import 'app/services/ytdlp_bootstrap.dart';
import 'app/services/rule_pack_sync.dart';
import 'app/widgets/incoming_links_binding.dart';
import 'app/providers/locale_provider.dart';
import 'app/providers/theme_provider.dart';
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
import 'package:flutter_native_splash/flutter_native_splash.dart';

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    return Future.value(true);
  });
}

// Global ProviderContainer to access providers during background init
late final ProviderContainer globalContainer;

Future<void> main() async {
  // 1. Critical Startup - Ensure Flutter is ready
  final widgetsBinding = WidgetsFlutterBinding.ensureInitialized();

  // 2. Preserve native splash until we are ready to show ColdStartShell
  FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);

  MediaKit.ensureInitialized();

  // 3. Show Splash immediately - THIS MUST RUN TO UNFREEZE UI
  runApp(const ColdStartShell());

  // Remove native splash now that Flutter-side splash is rendering
  FlutterNativeSplash.remove();

  // 4. Initialize in background without blocking the thread
  globalContainer = ProviderContainer();

  // Use a minimal delay to ensure the UI has frame to paint the shell
  Timer(const Duration(milliseconds: 50), () {
    _backgroundBootstrap();
  });
}

Future<void> _backgroundBootstrap() async {
  try {
    // A. Lightweight Init
    await Telemetry.instance.init(
      tags: {
        'platform': defaultTargetPlatform.name,
        'build_mode': kReleaseMode ? 'release' : 'debug',
      },
    );

    // B. Desktop Specific (Non-blocking for Android)
    if (!kIsWeb &&
        (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
      await windowManager.ensureInitialized();
      WindowOptions windowOptions = const WindowOptions(
        size: Size(1100, 700),
        center: true,
      );
      await windowManager.waitUntilReadyToShow(windowOptions, () async {
        await windowManager.show();
      });
      TrayService().init().catchError((e) => debugPrint('Tray error: $e'));
    }

    // C. Core Engine - With ultra-safe try/catch and timeouts
    // We try to init Rust, but we DON'T block if it takes too long
    try {
      await initRustLibBundledFirst().timeout(const Duration(seconds: 5));
    } catch (e) {
      debugPrint('Bootstrap: Rust engine delayed or failed: $e');
    }

    try {
      await SupabaseConfig.init().timeout(const Duration(seconds: 8));
    } catch (e) {
      debugPrint('Bootstrap: Cloud connection delayed: $e');
    }

    // D. Finalizing Services
    NotificationService.init().ok();
    ToolBootstrapper.ensure().ok();
    YtdlpBootstrap.ensure().ok();
    RulePackSync.ensure().ok();

    // E. SWITCH TO MAIN APP
    // Even if C failed, we launch the app. Providers will handle the "empty" state.
    runApp(
      UncontrolledProviderScope(
        container: globalContainer,
        child: const IncomingLinksBinding(child: DarkDownloaderApp()),
      ),
    );
  } catch (e) {
    debugPrint('Bootstrap: Fatal fallback triggered: $e');
    // Absolute fallback - never leave the user on the logo
    runApp(
      UncontrolledProviderScope(
        container: globalContainer,
        child: const IncomingLinksBinding(child: DarkDownloaderApp()),
      ),
    );
  }
}

extension _Ok<T> on Future<T> {
  void ok() => catchError((_) => null as dynamic);
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
          textDirection: locale.languageCode == 'ar'
              ? TextDirection.rtl
              : TextDirection.ltr,
          child: remoteConfig.when(
            data: (config) {
              if (config.maintenanceMode) {
                return MaintenanceScreen(message: config.maintenanceMessage);
              }
              return VersionCheckWrapper(config: config, child: child!);
            },
            loading: () => child ?? const SizedBox(),
            error: (err, st) => child ?? const SizedBox(),
          ),
        );
      },
      home: const AuthGate(),
    );
  }
}

final onboardingProvider = FutureProvider<bool>((ref) async {
  try {
    final prefs = await SharedPreferences.getInstance().timeout(
      const Duration(seconds: 3),
    );
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
          return OnboardingScreen(
            onFinish: () => ref.invalidate(onboardingProvider),
          );
        }
        if (authState.status == AuthStatus.initial ||
            authState.status == AuthStatus.loading) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (!authState.isAuthenticated) return const LoginScreen();
        return const HomeScreen();
      },
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (_, __) => const LoginScreen(),
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
