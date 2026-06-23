/// Detects Supabase OAuth / magic-link / password-reset return URIs.
bool isAuthCallbackUri(Uri uri) {
  final scheme = uri.scheme.toLowerCase();
  if (scheme != 'darkdownloader' && scheme != 'com.darkdownloader') {
    return false;
  }

  final host = uri.host.toLowerCase();
  final path = uri.path.toLowerCase();
  if (host == 'login-callback' ||
      host == 'reset-callback' ||
      host == 'email-confirm' ||
      path.contains('login-callback') ||
      path.contains('reset-callback') ||
      path.contains('email-confirm')) {
    return true;
  }

  if (uri.queryParameters.containsKey('code')) return true;

  final frag = uri.fragment.toLowerCase();
  return frag.contains('access_token') || frag.contains('refresh_token');
}
