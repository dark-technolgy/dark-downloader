import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter/foundation.dart';

class AdBlockerService {
  static final AdBlockerService _instance = AdBlockerService._internal();
  factory AdBlockerService() => _instance;
  AdBlockerService._internal();

  // Basic list of common ad domains
  // Expanded list of common ad domains, popups, and trackers
  final List<String> _adDomains = [
    "*://*.doubleclick.net/*",
    "*://partner.googleadservices.com/*",
    "*://*.googlesyndication.com/*",
    "*://*.google-analytics.com/*",
    "*://adservice.google.com/*",
    "*://*.adbrite.com/*",
    "*://*.exponential.com/*",
    "*://*.quantserve.com/*",
    "*://*.scorecardresearch.com/*",
    "*://*.zedo.com/*",
    "*://*.adsafeprotected.com/*",
    "*://*.teads.tv/*",
    "*://*.outbrain.com/*",
    "*://*.taboola.com/*",
    "*://*.criteo.com/*",
    "*://*.rubiconproject.com/*",
    "*://*.pubmatic.com/*",
    "*://*.appnexus.com/*",
    "*://*.popads.net/*",
    "*://*.propellerads.com/*",
    "*://*.popcash.net/*",
    "*://*.exoclick.com/*",
    "*://*.onclickads.net/*",
    "*://*.adsterra.com/*",
    "*://*.mgid.com/*",
    "*://*.amazon-adsystem.com/*",
    "*://*.advertising.com/*",
    "*://*.adroll.com/*",
    "*://*.gemius.pl/*",
    "*://*.yandex.ru/metrika/*",
    "*://*.hotjar.com/*",
    "*://*.adform.net/*",
  ];

  List<ContentBlocker> getContentBlockers() {
    if (defaultTargetPlatform != TargetPlatform.android && defaultTargetPlatform != TargetPlatform.iOS) {
      return []; // Desktop platforms might not support ContentBlocker fully yet in flutter_inappwebview
    }

    List<ContentBlocker> contentBlockers = [];

    for (final adUrl in _adDomains) {
      contentBlockers.add(ContentBlocker(
        trigger: ContentBlockerTrigger(
          urlFilter: adUrl,
        ),
        action: ContentBlockerAction(
          type: ContentBlockerActionType.BLOCK,
        ),
      ));
    }

    // Additional CSS injection to hide ad containers (optional but recommended)
    contentBlockers.add(ContentBlocker(
      trigger: ContentBlockerTrigger(
        urlFilter: ".*",
      ),
      action: ContentBlockerAction(
        type: ContentBlockerActionType.CSS_DISPLAY_NONE,
        selector: ".ad, .ads, .ad-container, .adsbygoogle, div[id^='div-gpt-ad'], div[class*='ad-'], .sponsored, .banner-ad, .ad-banner, iframe[src*='ads'], .outbrain-ad, .taboola-ad, .popunder, #popup, .popup-ad, div[data-ad-slot], div[data-ad-client]",
      ),
    ));

    return contentBlockers;
  }
}
