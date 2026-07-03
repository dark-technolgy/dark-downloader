import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../src/rust/api/remote_rules.dart' as rust_rules;
import '../config/supabase_config.dart';

/// Keeps the Rust extractor rule engine fed with an up-to-date pack.
///
/// Boot sequence (called by `main.dart`):
///
/// 1. On the very first run of a new version we install the *bundled* seed
///    pack from `assets/bootstrap/extractor_rules.json`. This guarantees the
///    rule engine works fully offline before any network sync.
/// 2. In the background we try to pull a fresher pack from a remote URL, in
///    priority order:
///       a. `--dart-define=REMOTE_RULES_URL=…`
///       b. Supabase Edge Function `get-extractor-rules`
///       c. Public CDN fallback baked into the app (`_kFallbackRulesUrl`)
/// 3. On failure we silently keep whatever is already installed. The native
///    Rust extractors keep working regardless.
///
/// The sync runs at most once every [_kMinSyncGap] between app launches to
/// avoid hammering endpoints on hot restarts.
class RulePackSync {
  RulePackSync._();

  static const _kMinSyncGap = Duration(hours: 6);
  static const _kPrefsLastSync = 'rules_pack_last_sync_v1';
  static const _kPrefsSeedVersion = 'rules_pack_seed_version_v1';
  static const _kAssetPath = 'assets/bootstrap/extractor_rules.json';

  /// Public CDN mirror. Updated whenever we ship a new rule set — no app
  /// release required. Kept lowercase / plain-text so it's easy to swap.
  static const _kFallbackRulesUrl =
      'https://raw.githubusercontent.com/dark-technolgy/dark-downloader/master/assets/bootstrap/extractor_rules.json';

  static bool _bootstrapping = false;

  /// Idempotent entry point. Safe to call more than once; only the first call
  /// runs full logic.
  static Future<void> ensure() async {
    if (_bootstrapping) return;
    _bootstrapping = true;

    // 1. Install bundled seed on first launch (or after a version upgrade
    //    that ships a newer seed).
    try {
      await _installBundledSeedIfNeeded();
    } catch (e) {
      debugPrint('RulePackSync: seed install skipped ($e)');
    }

    // 2. Try to refresh from the network, but only if enough time has passed.
    try {
      final prefs = await SharedPreferences.getInstance();
      final lastMs = prefs.getInt(_kPrefsLastSync) ?? 0;
      final elapsed = DateTime.now().difference(
        DateTime.fromMillisecondsSinceEpoch(lastMs),
      );
      if (elapsed < _kMinSyncGap) return;

      final url = _resolveRemoteUrl();
      if (url == null || url.isEmpty) return;

      await rust_rules
          .rustSyncRemoteRules(url: url)
          .timeout(const Duration(seconds: 20));
      await prefs.setInt(
        _kPrefsLastSync,
        DateTime.now().millisecondsSinceEpoch,
      );
      debugPrint(
        'RulePackSync: refreshed from $url — '
        '${rust_rules.rustGetRulesStatus()}',
      );
    } catch (e) {
      debugPrint('RulePackSync: remote sync skipped ($e)');
    }
  }

  /// Force a re-sync now (used by the debug settings screen if wired later).
  static Future<void> forceSync() async {
    final url = _resolveRemoteUrl();
    if (url == null || url.isEmpty) return;
    await rust_rules.rustSyncRemoteRules(url: url);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kPrefsLastSync, DateTime.now().millisecondsSinceEpoch);
  }

  // ------------------------------------------------------------------

  static Future<void> _installBundledSeedIfNeeded() async {
    final json = await rootBundle.loadString(_kAssetPath);
    final decoded = jsonDecode(json);
    final version = (decoded is Map && decoded['version'] is int)
        ? decoded['version'] as int
        : _fingerprint(json);
    final prefs = await SharedPreferences.getInstance();
    final installed = prefs.getInt(_kPrefsSeedVersion) ?? -1;
    if (installed == version) return;

    final count = await rust_rules.rustInstallBundledRules(json: json);
    await prefs.setInt(_kPrefsSeedVersion, version);
    debugPrint('RulePackSync: installed seed pack ($count rules, v$version)');

    // Also copy the seed to app-support so downstream tooling can see it.
    try {
      final sup = await getApplicationSupportDirectory();
      final target = p.join(
        sup.path,
        'dark_downloader',
        'extractor_rules.seed.json',
      );
      await Directory(p.dirname(target)).create(recursive: true);
      await File(target).writeAsString(json, flush: true);
    } catch (_) {}
  }

  /// Deterministic small integer derived from the seed contents. Used when
  /// the JSON does not expose an explicit `version` top-level field.
  static int _fingerprint(String json) {
    var h = 0;
    for (final code in json.codeUnits) {
      h = (h * 31 + code) & 0x7fffffff;
    }
    return h;
  }

  static String? _resolveRemoteUrl() {
    const fromEnv = String.fromEnvironment('REMOTE_RULES_URL');
    if (fromEnv.isNotEmpty) return fromEnv;

    final base = SupabaseConfig.url;
    if (base.isNotEmpty) {
      final trimmed = base.endsWith('/')
          ? base.substring(0, base.length - 1)
          : base;
      return '$trimmed/functions/v1/get-extractor-rules';
    }

    return _kFallbackRulesUrl;
  }
}
