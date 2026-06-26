import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';

import '../../src/rust/api/security.dart';
import 'shipping_overrides.dart';

/// Supabase configuration.
/// Keys are injected at build time via --dart-define (SUPABASE_URL / SUPABASE_ANON_KEY)
/// or fetched (obfuscated) from the Rust layer. Never hardcode the project ref here.
class SupabaseConfig {
  static String _defaultUrl = '';
  static String _defaultAnonKey = '';

  static String get url {
    const fromEnv = String.fromEnvironment('SUPABASE_URL');
    if (fromEnv.isNotEmpty) return fromEnv;
    if (kShippingSupabaseUrl.isNotEmpty) return kShippingSupabaseUrl;
    return _defaultUrl;
  }

  static String get anonKey {
    const fromEnv = String.fromEnvironment('SUPABASE_ANON_KEY');
    if (fromEnv.isNotEmpty) return fromEnv;
    if (kShippingSupabaseAnonKey.isNotEmpty) return kShippingSupabaseAnonKey;
    return _defaultAnonKey;
  }

  static Future<void> init() async {
    // Fetch obfuscated keys securely from Rust
    try {
      final config = await rustGetSupabaseConfig().timeout(const Duration(seconds: 5));
      _defaultUrl = config.url;
      _defaultAnonKey = config.anonKey;
    } catch (e) {
      debugPrint('Failed to load secure config from Rust: $e');
    }

    try {
      await Supabase.initialize(
        url: url, 
        publishableKey: anonKey,
      ).timeout(const Duration(seconds: 10));
    } catch (e) {
      debugPrint('Supabase initialization warning: $e');
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove('supabase.auth.token');
        await Supabase.initialize(
          url: url, 
          publishableKey: anonKey,
        );
      } catch (e2) {
        debugPrint('Supabase 2nd init failed: $e2');
      }
    }
  }
}

SupabaseClient get supabase => Supabase.instance.client;
