import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/supabase_config.dart';
import '../services/device_metadata_service.dart';
import 'locale_provider.dart';

enum AuthStatus { initial, loading, authenticated, unauthenticated, error }

class AuthState {
  static const Object _sentinel = Object();

  final AuthStatus status;
  final User? user;
  final String? errorMessage;
  final String? errorDetail;
  final String? successMessage;
  final Map<String, dynamic>? profile;

  const AuthState({
    this.status = AuthStatus.initial,
    this.user,
    this.errorMessage,
    this.errorDetail,
    this.successMessage,
    this.profile,
  });

  bool get isAuthenticated =>
      status == AuthStatus.authenticated && user != null && user?.emailConfirmedAt != null;

  bool get isLoading => status == AuthStatus.loading;

  bool get needsEmailConfirmation => false;

  /// Display name
  String get displayName {
    final fromProfile = profile?['name'] as String?;
    if (fromProfile != null && fromProfile.trim().isNotEmpty) {
      return fromProfile;
    }
    final fromMeta = user?.userMetadata?['full_name'] as String?;
    if (fromMeta != null && fromMeta.trim().isNotEmpty) return fromMeta;
    return 'مستخدم';
  }

  /// Read tracking data from userMetadata instead of profiles table!
  String? get country => user?.userMetadata?['country_code'] as String?;
  String? get countryName => user?.userMetadata?['country_name'] as String?;
  String? get city => user?.userMetadata?['city'] as String?;
  String? get devicePlatform => user?.userMetadata?['platform'] as String?;
  String? get deviceModel => user?.userMetadata?['device_model'] as String?;

  DateTime? get joinedAt {
    final raw = user?.createdAt;
    if (raw == null) return null;
    return DateTime.tryParse(raw);
  }

  DateTime? get lastSignIn {
    final raw = user?.lastSignInAt;
    if (raw == null) return null;
    return DateTime.tryParse(raw);
  }

  AuthState copyWith({
    AuthStatus? status,
    User? user,
    Object? errorMessage = _sentinel,
    Object? errorDetail = _sentinel,
    Object? successMessage = _sentinel,
    Map<String, dynamic>? profile,
    bool clearError = false,
    bool clearUser = false,
  }) {
    return AuthState(
      status: status ?? this.status,
      user: clearUser ? null : (user ?? this.user),
      errorMessage: clearError
          ? null
          : (identical(errorMessage, _sentinel)
                ? this.errorMessage
                : errorMessage as String?),
      errorDetail: clearError
          ? null
          : (identical(errorDetail, _sentinel)
                ? this.errorDetail
                : errorDetail as String?),
      successMessage: clearError
          ? null
          : (identical(successMessage, _sentinel)
                ? this.successMessage
                : successMessage as String?),
      profile: profile ?? this.profile,
    );
  }
}

class AuthNotifier extends Notifier<AuthState> {
  RealtimeChannel? _profileSubscription;

  @override
  AuthState build() {
    ref.onDispose(() {
      _profileSubscription?.unsubscribe();
    });
    _init();
    return const AuthState();
  }

  Future<void> _init() async {
    supabase.auth.onAuthStateChange.listen((data) async {
      final session = data.session;
      if (session != null) {
        _setupRealtimeRevocation(session.user.id);
        await _loadAndEnrichProfile(session.user);
      } else {
        await _profileSubscription?.unsubscribe();
        _profileSubscription = null;
        state = const AuthState(status: AuthStatus.unauthenticated);
      }
    });

    final session = supabase.auth.currentSession;
    if (session != null) {
      _setupRealtimeRevocation(session.user.id);
      await _loadAndEnrichProfile(session.user);
    } else {
      state = const AuthState(status: AuthStatus.unauthenticated);
    }
  }

  void _setupRealtimeRevocation(String userId) {
    _profileSubscription?.unsubscribe();
    _profileSubscription = supabase
        .channel('public:profiles:$userId')
        .onPostgresChanges(
          event: PostgresChangeEvent.delete,
          schema: 'public',
          table: 'profiles',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id',
            value: userId,
          ),
          callback: (payload) async {
            debugPrint(
              '🚨 Profile deleted from DB! Revoking access instantly...',
            );
            await supabase.auth.signOut();
          },
        )
        .subscribe();
  }

  Future<void> _loadAndEnrichProfile(User user) async {
    try {
      // 1. Update user metadata with device and country info
      // This saves the data directly in auth.users without needing database migrations!
      if (user.userMetadata?['country_code'] == null) {
        await _enrichUserMetadata();
        // Update user object after metadata change
        user = supabase.auth.currentUser ?? user;
      }

      // 2. Load standard profile quietly
      Map<String, dynamic>? updatedProfile;
      try {
        final response = await supabase
            .from('profiles')
            .select()
            .eq('id', user.id)
            .maybeSingle();

        if (response == null) {
          final currentLocale = ref.read(localeProvider).languageCode;
          // Insert ONLY columns that we hope exist. If they don't, we catch it.
          await supabase.from('profiles').upsert({
            'id': user.id,
            'name': null,
            'language': currentLocale,
          });
        }

        updatedProfile = await supabase
            .from('profiles')
            .select()
            .eq('id', user.id)
            .maybeSingle();
      } catch (e) {
        debugPrint('Profiles table error bypassed: $e');
        // We don't throw here because user_metadata already has what we need!
      }

      state = AuthState(
        status: AuthStatus.authenticated,
        user: user,
        profile: updatedProfile,
      );
    } on AuthException catch (e) {
      debugPrint('Auth Exception: $e');
      if (e.statusCode == '403' || e.message.contains('User from sub claim')) {
        await supabase.auth.signOut();
        state = const AuthState(status: AuthStatus.unauthenticated);
      } else {
        state = AuthState(
          status: AuthStatus.unauthenticated,
          errorMessage: e.message,
        );
      }
    } catch (e) {
      debugPrint('Profile load error: $e');
      state = AuthState(
        status: AuthStatus.authenticated,
        user: user,
        errorMessage: 'err_profile_load_failed',
      );
    }
  }

  Future<void> _enrichUserMetadata() async {
    try {
      final meta = await DeviceMetadata.collect();
      await supabase.auth.updateUser(
        UserAttributes(
          data: {
            'platform': meta.platform,
            'device_model': meta.deviceModel,
            'locale_info': meta.locale,
            'timezone': meta.timezone,
            'country_code': meta.country,
            'country_name': meta.countryName,
            'city': meta.city,
            'isp': meta.isp,
          },
        ),
      );
    } catch (e) {
      debugPrint('Update metadata error: $e');
    }
  }

  /// Returns true if OTP is required (session is null or not confirmed), false if automatically logged in.
  Future<bool> smartSignUp({
    required String email,
    required String password,
    required String name,
  }) async {
    try {
      final meta = await DeviceMetadata.collect();

      final res = await supabase.auth.signUp(
        email: email.trim(),
        password: password,
        data: {
          'full_name': name,
          'platform': meta.platform,
          'device_model': meta.deviceModel,
          'locale_info': meta.locale,
          'timezone': meta.timezone,
          'country_code': meta.country,
          'country_name': meta.countryName,
          'city': meta.city,
          'isp': meta.isp,
        },
      );

      // Force OTP if not confirmed, even if session exists
      if (res.user != null && res.user!.emailConfirmedAt == null) {
        if (res.session != null) {
          await supabase.auth.signOut();
        }
        try {
          await supabase.auth.resend(type: OtpType.signup, email: email.trim());
        } catch (_) {}
        return true;
      }

      if (res.session != null && res.user != null) {
        await _loadAndEnrichProfile(res.user!);
        return false; // Automatically logged in
      }

      try {
        await supabase.auth.resend(type: OtpType.signup, email: email.trim());
      } catch (_) {}

      return true; // OTP required
    } on AuthException catch (e) {
      throw e.message;
    } catch (e) {
      throw 'حدث خطأ غير متوقع أثناء إنشاء الحساب';
    }
  }

  Future<void> smartSignIn({
    required String email,
    required String password,
  }) async {
    try {
      final res = await supabase.auth.signInWithPassword(
        email: email.trim(),
        password: password,
      );
      if (res.user != null) {
        // Enforce strict authentication: MUST be confirmed
        if (res.user!.emailConfirmedAt == null) {
          await supabase.auth.signOut();
          try {
            await supabase.auth.resend(type: OtpType.signup, email: email.trim());
          } catch (_) {}
          throw 'unverified';
        }
        await _loadAndEnrichProfile(res.user!);
      }
    } on AuthException catch (e) {
      throw e.message;
    } catch (e) {
      if (e == 'unverified') rethrow;
      throw 'حدث خطأ أثناء تسجيل الدخول';
    }
  }

  Future<void> verifyOTP({
    required String email,
    required String token,
    bool isRecovery = false,
  }) async {
    try {
      final res = await supabase.auth.verifyOTP(
        type: isRecovery ? OtpType.recovery : OtpType.signup,
        email: email.trim(),
        token: token.trim(),
      );
      if (res.user != null) {
        await _loadAndEnrichProfile(res.user!);
      }
    } on AuthException catch (e) {
      throw e.message;
    } catch (e) {
      throw 'رمز التحقق غير صحيح أو منتهي الصلاحية';
    }
  }

  Future<void> sendPasswordReset(String email) async {
    try {
      await supabase.auth.resetPasswordForEmail(email.trim());
    } on AuthException catch (e) {
      throw e.message;
    } catch (e) {
      throw 'حدث خطأ أثناء إرسال رمز استعادة كلمة المرور';
    }
  }

  Future<void> updatePassword(String newPassword) async {
    try {
      await supabase.auth.updateUser(UserAttributes(password: newPassword));
    } on AuthException catch (e) {
      throw e.message;
    } catch (e) {
      throw 'حدث خطأ أثناء تحديث كلمة المرور';
    }
  }

  Future<void> refreshProfile() async {
    final user = state.user ?? supabase.auth.currentUser;
    if (user == null) return;
    await _loadAndEnrichProfile(user);
  }

  Future<void> updateDisplayName(String name) async {
    final user = state.user;
    if (user == null) return;
    try {
      // تحديث الاسم في user_metadata أيضاً
      await supabase.auth.updateUser(
        UserAttributes(data: {'full_name': name.trim()}),
      );

      await supabase
          .from('profiles')
          .update({'name': name.trim()})
          .eq('id', user.id);

      await refreshProfile();
    } catch (e) {
      debugPrint('Update name error: $e');
    }
  }

  Future<void> signOut() async {
    await supabase.auth.signOut();
  }

  void clearError() => state = state.copyWith(clearError: true);
}

final authProvider = NotifierProvider<AuthNotifier, AuthState>(
  AuthNotifier.new,
);
