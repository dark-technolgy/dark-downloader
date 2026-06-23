# Flutter Rust Bridge
-keep class com.darkdownloader.dark_downloader.RustLib { *; }
-keep class com.darkdownloader.dark_downloader.RustLib$* { *; }
-keep class com.sun.jna.** { *; }
-keep class com.darkdownloader.dark_downloader.** { *; }

# General Flutter
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# Play Store Split Install (Fix for R8 errors)
-dontwarn com.google.android.play.core.**
-keep class com.google.android.play.core.** { *; }

# Supabase & Http
-keep class okhttp3.** { *; }
-dontwarn okhttp3.**
-keep class com.google.gson.** { *; }
-dontwarn com.google.gson.**
