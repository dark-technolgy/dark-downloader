import 'package:flutter/foundation.dart';

/// Native deep link Supabase uses after email confirm / OAuth / reset.
const String kAuthNativeRedirectUri = 'com.darkdownloader://login-callback';

/// Must match entries in Supabase Dashboard → Auth → URL Configuration → Redirect URLs.
String authEmailRedirectTo() {
  const site = 'https://keenx.net'; // Official Corporate Domain
  if (kIsWeb) {
    return '$site/auth/callback';
  }
  return '$site/welcome';
}
