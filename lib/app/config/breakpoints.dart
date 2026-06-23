import 'package:flutter/widgets.dart';

/// Responsive breakpoints used across all screens.
///
/// Kept intentionally small and conservative. All comparisons use the short
/// side of the screen (width in portrait, height in landscape) via
/// `MediaQuery.sizeOf(context).width` so that rotating the device picks the
/// most appropriate layout automatically.
class Breakpoints {
  /// Up to this width is considered a phone-sized viewport.
  static const double mobile = 600;

  /// Between `mobile` and this width is tablet-sized.
  static const double tablet = 900;

  /// At or above this width we treat the viewport as a desktop window.
  static const double desktop = 1200;
}

/// Discrete device classification used by UI code to pick column counts,
/// padding sizes, stacked vs. side-by-side layouts, etc.
enum DeviceKind { mobile, tablet, desktop }

/// Convenience `BuildContext` accessors for responsive code.
extension ResponsiveCtx on BuildContext {
  DeviceKind get device {
    final w = MediaQuery.sizeOf(this).width;
    if (w >= Breakpoints.desktop) return DeviceKind.desktop;
    if (w >= Breakpoints.tablet) return DeviceKind.tablet;
    return DeviceKind.mobile;
  }

  bool get isMobile => device == DeviceKind.mobile;
  bool get isTablet => device == DeviceKind.tablet;
  bool get isDesktop => device == DeviceKind.desktop;
  bool get isTabletOrLarger => device != DeviceKind.mobile;

  /// Horizontal page padding appropriate for the current device size.
  /// Vertical padding is left to callers so lists/grids can tune it.
  EdgeInsets get pageInsets {
    switch (device) {
      case DeviceKind.desktop:
        return const EdgeInsets.symmetric(horizontal: 32, vertical: 16);
      case DeviceKind.tablet:
        return const EdgeInsets.symmetric(horizontal: 24, vertical: 16);
      case DeviceKind.mobile:
        return const EdgeInsets.symmetric(horizontal: 16, vertical: 12);
    }
  }

  /// Upper bound on content width for text-heavy columns.
  /// Prevents line lengths from becoming uncomfortable on wide monitors.
  double get readableMaxWidth {
    switch (device) {
      case DeviceKind.desktop:
        return 1100;
      case DeviceKind.tablet:
        return 900;
      case DeviceKind.mobile:
        return double.infinity;
    }
  }
}
