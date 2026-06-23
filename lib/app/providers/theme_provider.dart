import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppThemeState {
  final ThemeMode mode;
  final Color primaryColor;

  AppThemeState({required this.mode, required this.primaryColor});

  AppThemeState copyWith({ThemeMode? mode, Color? primaryColor}) {
    return AppThemeState(
      mode: mode ?? this.mode,
      primaryColor: primaryColor ?? this.primaryColor,
    );
  }
}

class AppThemeNotifier extends Notifier<AppThemeState> {
  @override
  AppThemeState build() {
    _load();
    return AppThemeState(mode: ThemeMode.system, primaryColor: const Color(0xFF00BCD4));
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final modeIndex = prefs.getInt('theme_mode') ?? 0;
    final colorValue = prefs.getInt('theme_color') ?? const Color(0xFF00BCD4).toARGB32();
    
    state = AppThemeState(
      mode: ThemeMode.values[modeIndex],
      primaryColor: Color(colorValue),
    );
  }

  Future<void> setMode(ThemeMode mode) async {
    state = state.copyWith(mode: mode);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('theme_mode', mode.index);
  }

  Future<void> setColor(Color color) async {
    state = state.copyWith(primaryColor: color);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('theme_color', color.toARGB32());
  }
}

final themeProvider = NotifierProvider<AppThemeNotifier, AppThemeState>(AppThemeNotifier.new);

// مصفوفة الألوان المتاحة
const List<Color> appAccentColors = [
  Color(0xFF6C63FF), // Indigo
  Color(0xFFE91E63), // Pink
  Color(0xFF00BCD4), // Cyan
  Color(0xFF4CAF50), // Green
  Color(0xFFFFC107), // Amber
  Color(0xFF9C27B0), // Purple
  Color(0xFF607D8B), // Blue Grey
];
