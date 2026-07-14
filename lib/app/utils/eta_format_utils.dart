import 'dart:ui' show Locale;

import '../config/localization.dart';

/// Compact ETA for downloads / torrents (seconds through multi-day).
String formatEtaSeconds(int etaSeconds, Locale locale) {
  if (etaSeconds <= 0) return '';
  const t = AppLocalization.translate;
  if (etaSeconds < 60) {
    return t('eta_under_minute', locale).replaceAll('{n}', '$etaSeconds');
  }
  if (etaSeconds < 3600) {
    final m = etaSeconds ~/ 60;
    final s = etaSeconds % 60;
    return t('eta_under_hour', locale).replaceAll('{m}', '$m').replaceAll('{s}', '$s');
  }
  if (etaSeconds < 86400) {
    final h = etaSeconds ~/ 3600;
    final m = (etaSeconds % 3600) ~/ 60;
    return t('eta_under_day', locale).replaceAll('{h}', '$h').replaceAll('{m}', '$m');
  }
  final d = etaSeconds ~/ 86400;
  final h = (etaSeconds % 86400) ~/ 3600;
  return t('eta_days', locale).replaceAll('{d}', '$d').replaceAll('{h}', '$h');
}

String formatEtaSecondsBigInt(BigInt secs, Locale locale) =>
    formatEtaSeconds(secs.toInt(), locale);
