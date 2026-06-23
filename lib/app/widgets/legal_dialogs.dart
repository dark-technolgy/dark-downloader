import 'package:flutter/material.dart';
import '../config/localization.dart';

class LegalDialogs {
  static void showPrivacyPolicy(BuildContext context, Locale locale) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(AppLocalization.translate('privacy_policy', locale)),
        content: SingleChildScrollView(
          child: Text(AppLocalization.translate('privacy_policy_content', locale)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(AppLocalization.translate('close', locale)),
          ),
        ],
      ),
    );
  }

  static void showTermsOfService(BuildContext context, Locale locale) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(AppLocalization.translate('terms_of_service', locale)),
        content: SingleChildScrollView(
          child: Text(AppLocalization.translate('terms_of_service_content', locale)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(AppLocalization.translate('close', locale)),
          ),
        ],
      ),
    );
  }
}
