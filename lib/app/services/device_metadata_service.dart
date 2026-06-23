import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Collects device metadata and country for Supabase profile enrichment.
class DeviceMetadata {
  final String platform;       // 'windows', 'android', 'ios', 'web'
  final String deviceModel;    // e.g. 'Windows 10 Pro', 'Pixel 7', etc.
  final String locale;         // e.g. 'ar_SA', 'en_US'
  final String timezone;       // e.g. 'Asia/Riyadh'
  final String? country;       // ISO code e.g. 'SA', 'US'
  final String? countryName;   // e.g. 'Saudi Arabia'
  final String? city;          // e.g. 'Riyadh'
  final String? isp;           // e.g. 'STC'

  const DeviceMetadata({
    required this.platform,
    required this.deviceModel,
    required this.locale,
    required this.timezone,
    this.country,
    this.countryName,
    this.city,
    this.isp,
  });

  Map<String, dynamic> toJson() => {
    'platform': platform,
    'device_model': deviceModel,
    'locale': locale,
    'timezone': timezone,
    if (country != null) 'country_code': country,
    if (countryName != null) 'country_name': countryName,
    if (city != null) 'city': city,
    if (isp != null) 'isp': isp,
  };

  static Future<DeviceMetadata> collect() async {
    String platformName = 'unknown';
    String deviceModel = 'unknown';

    if (kIsWeb) {
      platformName = 'web';
      deviceModel = 'Web Browser';
    } else {
      platformName = Platform.operatingSystem;
      deviceModel = '${Platform.operatingSystem} System';
    }

    final locale = Platform.localeName;
    final timezone = DateTime.now().timeZoneName;

    // Try to get country from free IP geolocation API
    String? country;
    String? countryName;
    String? city;
    String? isp;

    try {
      final response = await http.get(
        Uri.parse('http://ip-api.com/json/?fields=status,country,countryCode,city,isp'),
      ).timeout(const Duration(seconds: 5));
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        if (data['status'] == 'success') {
          country = data['countryCode'] as String?;
          countryName = data['country'] as String?;
          city = data['city'] as String?;
          isp = data['isp'] as String?;
        }
      }
    } catch (_) {
      // Fallback: try to guess country from locale
      final parts = locale.split('_');
      if (parts.length >= 2 && parts.last.length == 2) {
        country = parts.last.toUpperCase();
      }
    }

    return DeviceMetadata(
      platform: platformName,
      deviceModel: deviceModel,
      locale: locale,
      timezone: timezone,
      country: country,
      countryName: countryName,
      city: city,
      isp: isp,
    );
  }
}
