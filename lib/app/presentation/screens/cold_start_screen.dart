import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../config/localization.dart';
import '../../config/theme.dart';

class ColdStartShell extends StatelessWidget {
  const ColdStartShell({super.key});

  @override
  Widget build(BuildContext context) {
    const primary = AppTheme.primaryColor;
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: primary),
        scaffoldBackgroundColor: AppTheme.backgroundDark,
      ),
      home: Scaffold(
        backgroundColor: AppTheme.backgroundDark,
        body: Container(
          width: double.infinity,
          decoration: BoxDecoration(
            gradient: RadialGradient(
              colors: [
                primary.withValues(alpha: 0.25),
                Colors.transparent,
              ],
              radius: 1.5,
              center: const Alignment(0, -0.1),
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Animated Logo Container
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0.0, end: 1.0),
                duration: const Duration(milliseconds: 1000),
                curve: Curves.easeOutBack,
                builder: (context, value, child) {
                  return Transform.scale(
                    scale: value,
                    child: Container(
                      padding: const EdgeInsets.all(32),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0A0A0A),
                        borderRadius: BorderRadius.circular(40),
                        border: Border.all(color: primary.withValues(alpha: 0.4), width: 1.5),
                        boxShadow: [
                          BoxShadow(
                            color: primary.withValues(alpha: 0.3),
                            blurRadius: 40,
                            spreadRadius: -5,
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.cloud_download_rounded,
                        size: 100,
                        color: primary,
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 48),
              // Brand Name
              const Text(
                'DARK',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 42,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 14,
                ),
              ),
              Text(
                'TECHNOLOGY',
                style: TextStyle(
                  color: primary.withValues(alpha: 0.8),
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 6,
                ),
              ),
              const SizedBox(height: 80),
              // Modern Loading
              SizedBox(
                width: 140,
                child: Column(
                  children: [
                    const LinearProgressIndicator(
                      backgroundColor: Color(0xFF111111),
                      color: primary,
                      minHeight: 3,
                      borderRadius: BorderRadius.all(Radius.circular(10)),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'SYSTEM READY',
                      style: TextStyle(
                        color: Colors.white30,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 3,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class BootstrapFatalApp extends StatelessWidget {
  const BootstrapFatalApp({super.key, required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) {
    final loc = PlatformDispatcher.instance.locale;
    final title = AppLocalization.translate('app_name', loc);
    final body = kDebugMode
        ? AppLocalization.translate('bootstrap_engine_failed_debug', loc).replaceAll('{detail}', error.toString())
        : AppLocalization.translate('bootstrap_engine_failed_release', loc);

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        appBar: AppBar(title: Text(title)),
        body: Padding(
          padding: const EdgeInsets.all(24),
          child: SelectableText(
            body,
            style: const TextStyle(fontSize: 15),
          ),
        ),
      ),
    );
  }
}
