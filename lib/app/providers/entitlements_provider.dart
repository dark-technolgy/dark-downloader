import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/localization.dart';
import '../config/supabase_config.dart';
import 'auth_provider.dart';
import 'locale_provider.dart';

class Entitlements {
  final DateTime trialStartedAt;
  final DateTime trialEndsAt;
  final bool trialActive;
  final bool subscribed;
  final String tier;

  const Entitlements({
    required this.trialStartedAt,
    required this.trialEndsAt,
    required this.trialActive,
    required this.subscribed,
    required this.tier,
  });

  bool get canUseApp => trialActive || subscribed;
}

final entitlementsProvider = FutureProvider<Entitlements>((ref) async {
  const trialDays = 3;
  const key = 'trial_started_at_ms_v1';

  final prefs = await SharedPreferences.getInstance();
  final now = DateTime.now();

  // Prefer server-anchored trial start once the user is authenticated.
  final auth = ref.watch(authProvider);
  DateTime? serverTrialStartedAt;
  final rawTrial = auth.profile?['trial_started_at'];
  if (rawTrial is String && rawTrial.isNotEmpty) {
    serverTrialStartedAt = DateTime.tryParse(rawTrial)?.toLocal();
  }

  final startedMs = prefs.getInt(key);
  final localTrialStartedAt = startedMs != null
      ? DateTime.fromMillisecondsSinceEpoch(startedMs)
      : now;
  if (startedMs == null) {
    await prefs.setInt(key, now.millisecondsSinceEpoch);
  }

  // If the profile doesn't have trial_started_at yet (older rows), anchor on server once.
  if (auth.isAuthenticated && auth.user != null && serverTrialStartedAt == null) {
    try {
      // محاولة استخدام RPC كخيار أول (أكثر أماناً)
      await supabase.rpc('start_trial_if_null');
    } catch (_) {
      // خيار احتياطي في حال فشل الـ RPC
      try {
        final utc = localTrialStartedAt.toUtc().toIso8601String();
        await supabase
            .from('profiles')
            .update({'trial_started_at': utc})
            .eq('id', auth.user!.id);
      } catch (_) {}
    }
    
    // تحديث البيانات بعد المحاولة
    await ref.read(authProvider.notifier).refreshProfile();
    final updatedProfile = ref.read(authProvider).profile;
    if (updatedProfile != null && updatedProfile['trial_started_at'] != null) {
      serverTrialStartedAt = DateTime.tryParse(updatedProfile['trial_started_at'])?.toLocal();
    }
  }

  final trialStartedAt = serverTrialStartedAt ?? localTrialStartedAt;
  final trialEndsAt = trialStartedAt.add(const Duration(days: trialDays));
  final trialActive = now.isBefore(trialEndsAt);

  // Re-read to check authentication state
  final session = ref.read(authProvider);
  final tier = session.isAuthenticated ? 'premium' : 'free';

  final subscribed = session.isAuthenticated;

  return Entitlements(
    trialStartedAt: trialStartedAt,
    trialEndsAt: trialEndsAt,
    trialActive: trialActive,
    subscribed: subscribed,
    tier: tier,
  );
});

String entitlementsBlockedMessage(Ref ref, Entitlements ent) {
  final loc = ref.read(localeProvider);
  if (ent.subscribed) return '';
  if (!ent.trialActive) {
    return AppLocalization.translate('trial_expired', loc);
  }
  final left = ent.trialEndsAt.difference(DateTime.now()).inHours;
  return AppLocalization.translate('trial_remaining', loc)
      .replaceAll('{h}', '$left');
}

