# Flutter ProGuard Rules

# Keep the main activity and any classes used by the platform
-keep class com.dark.dark_downloader.** { *; }

# Keep Flutter Rust Bridge classes
-keep class com.flutter_rust_bridge.** { *; }

# Media Kit rules
-keep class com.sun.jna.** { *; }
-keep class com.google.android.exoplayer2.** { *; }

# Avoid stripping common libraries
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.embedding.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.app.** { *; }

# Support libraries
-keep class androidx.annotation.** { *; }

# For Dio/OkHttp if used
-keep class okhttp3.** { *; }
-keep class retrofit2.** { *; }

# Supabase / GoTrue / Realtime
-keep class io.supabase.** { *; }

# Sentry
-keep class io.sentry.** { *; }

# General optimizations
-dontwarn com.sun.jna.**
-dontwarn androidx.**
-dontwarn okhttp3.**
-dontwarn retrofit2.**
-dontwarn io.sentry.**

# Flutter Play Store Split Application / deferred components
-dontwarn com.google.android.play.core.splitcompat.**
-dontwarn com.google.android.play.core.splitinstall.**
-dontwarn com.google.android.play.core.tasks.**
