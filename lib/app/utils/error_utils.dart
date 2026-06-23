import 'package:supabase_flutter/supabase_flutter.dart';

/// Maps backend / engine errors to [AppLocalization] keys (not user-visible text).
class ErrorUtils {
  /// Optional `{detail}` placeholder for [authErrorL10nKey].
  static String? authErrorDetail(dynamic error) {
    if (error is AuthException) {
      switch (error.message) {
        case 'Invalid login credentials':
        case 'User already registered':
        case 'Email not confirmed':
          return null;
        default:
          return error.message;
      }
    }
    return null;
  }

  static bool isRedirectConfigError(AuthException e) {
    final m = e.message.toLowerCase();
    return m.contains('redirect') ||
        m.contains('redirect_to') ||
        (m.contains('url') && (m.contains('allow') || m.contains('valid')));
  }

  static String authErrorL10nKey(dynamic error) {
    if (error is AuthException) {
      switch (error.message) {
        case 'Invalid login credentials':
          return 'auth_err_invalid_creds';
        case 'User already registered':
          return 'auth_err_user_exists';
        case 'Email not confirmed':
          return 'auth_err_email_not_confirmed';
        default:
          break;
      }
      final m = error.message.toLowerCase();
      if (m.contains('rate limit') || m.contains('too many')) {
        return 'auth_err_rate_limit';
      }
      if (isRedirectConfigError(error)) {
        return 'auth_err_redirect_not_allowed';
      }
      if (m.contains('signup') && m.contains('disabled')) {
        return 'auth_err_signup_disabled';
      }
      return 'auth_err_auth_with_detail';
    }

    final errStr = error.toString().toLowerCase();
    if (errStr.contains('network') || errStr.contains('connection')) {
      return 'auth_err_network';
    }
    if (errStr.contains('rate limit') || errStr.contains('too many')) {
      return 'auth_err_rate_limit';
    }

    return 'auth_unexpected';
  }

  static String extractorErrorL10nKey(String error) {
    final err = error.toLowerCase();
    if (err.contains('no_streams') || err.contains('no download links')) {
      return 'ext_err_no_streams';
    }
    if (err.contains('login_required') || err.contains('sign in')) {
      return 'ext_err_login_required';
    }
    if (err.contains('unplayable') || err.contains('unavailable')) {
      return 'ext_err_not_available_region';
    }
    if (err.contains('timeout')) {
      return 'ext_err_timeout';
    }
    return 'ext_err_parse_failed';
  }
}
