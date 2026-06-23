import 'package:flutter/material.dart';

class AppTheme {
  // اللون الأزرق السماوي (Sky Blue) الاحترافي
  static const primaryColor = Color(0xFF00A3FF); 
  static const backgroundLight = Color(0xFFFFFFFF);
  static const backgroundDark = Color(0xFF000000); // أسود ملكي

  static ThemeData lightTheme(Color primary) => ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: primary,
      primary: primary,
      brightness: Brightness.light,
      surface: backgroundLight,
    ),
    scaffoldBackgroundColor: backgroundLight,
    appBarTheme: const AppBarTheme(
      centerTitle: true,
      elevation: 0,
      backgroundColor: backgroundLight,
      foregroundColor: Colors.black,
    ),
    cardTheme: CardThemeData(
      elevation: 2,
      shadowColor: primary.withValues(alpha: 0.1),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      color: Colors.white,
    ),
  );

  static ThemeData darkTheme(Color primary) => ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: primary,
      primary: primary,
      brightness: Brightness.dark,
      surface: const Color(0xFF0A0A0A),
      onSurface: Colors.white,
    ),
    scaffoldBackgroundColor: backgroundDark,
    appBarTheme: const AppBarTheme(
      centerTitle: true,
      elevation: 0,
      backgroundColor: backgroundDark,
      foregroundColor: Colors.white,
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: primary.withValues(alpha: 0.1)),
      ),
      color: const Color(0xFF0A0A0A),
    ),
  );
}
