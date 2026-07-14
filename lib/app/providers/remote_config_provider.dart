import 'package:flutter/foundation.dart';
import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../src/rust/api/remote_rules.dart' as rust_rules;
import '../config/supabase_config.dart';
import '../services/telemetry_service.dart';

class RemoteConfigState {
  final bool maintenanceMode;
  final String? maintenanceMessage;
  final String minAppVersion;
  final String latestVersion;
  final String? downloadUrl;
  final String? releaseNotes;
  final String? sentryDsn;
  final bool rulesSynced;

  RemoteConfigState({
    this.maintenanceMode = false,
    this.maintenanceMessage,
    this.minAppVersion = '1.0.0',
    this.latestVersion = '1.0.0',
    this.downloadUrl,
    this.releaseNotes,
    this.sentryDsn,
    this.rulesSynced = false,
  });

  RemoteConfigState copyWith({
    bool? maintenanceMode,
    String? maintenanceMessage,
    String? minAppVersion,
    String? latestVersion,
    String? downloadUrl,
    String? releaseNotes,
    String? sentryDsn,
    bool? rulesSynced,
  }) {
    return RemoteConfigState(
      maintenanceMode: maintenanceMode ?? this.maintenanceMode,
      maintenanceMessage: maintenanceMessage ?? this.maintenanceMessage,
      minAppVersion: minAppVersion ?? this.minAppVersion,
      latestVersion: latestVersion ?? this.latestVersion,
      downloadUrl: downloadUrl ?? this.downloadUrl,
      releaseNotes: releaseNotes ?? this.releaseNotes,
      sentryDsn: sentryDsn ?? this.sentryDsn,
      rulesSynced: rulesSynced ?? this.rulesSynced,
    );
  }
}

class RemoteConfigNotifier extends AsyncNotifier<RemoteConfigState> {
  @override
  Future<RemoteConfigState> build() async {
    return _fetch();
  }

  Future<RemoteConfigState> _fetch() async {
    try {
      // 1. Sync Rust Rules (Legacy logic kept)
      const remoteRulesUrl =
          String.fromEnvironment('REMOTE_RULES_URL', defaultValue: '');
      if (remoteRulesUrl.isNotEmpty) {
        await rust_rules.rustSyncRemoteRules(url: remoteRulesUrl);
      }

      // 2. Fetch Global App Config from Supabase
      // We assume a 'remote_config' table exists for professional management
      final res = await supabase.from('remote_config').select().maybeSingle();

      if (res != null) {
        final dsn = res['sentry_dsn'] as String?;
        if (dsn != null && dsn.isNotEmpty) {
          unawaited(Telemetry.instance.setupSentry(dsn));
        }

        return RemoteConfigState(
          maintenanceMode: res['maintenance_mode'] ?? false,
          maintenanceMessage: res['maintenance_message'],
          minAppVersion: res['min_version'] ?? '1.0.0',
          latestVersion: res['latest_version'] ?? '1.0.0',
          downloadUrl: res['download_url'],
          releaseNotes: res['release_notes'],
          sentryDsn: res['sentry_dsn'],
          rulesSynced: true,
        );
      }
    } catch (e) {
      debugPrint('RemoteConfig: Error fetching: $e');
    }
    return RemoteConfigState();
  }

  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() => _fetch());
  }
}

final remoteConfigProvider =
    AsyncNotifierProvider<RemoteConfigNotifier, RemoteConfigState>(
        RemoteConfigNotifier.new,);
