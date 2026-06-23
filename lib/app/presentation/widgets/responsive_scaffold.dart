import 'package:flutter/material.dart';

import '../../config/breakpoints.dart';

/// Helper that switches between a vertically stacked layout (mobile) and a
/// two-column side-by-side layout (tablet/desktop).
///
/// On mobile, the [primary] widget is shown above the [secondary] widget in a
/// single scrollable column. On tablet and desktop, the two columns are laid
/// out side-by-side with a configurable ratio.
class ResponsiveTwoColumn extends StatelessWidget {
  const ResponsiveTwoColumn({
    super.key,
    required this.primary,
    required this.secondary,
    this.primaryFlex = 5,
    this.secondaryFlex = 7,
    this.gap = 20,
    this.stackedScrollable = true,
  });

  /// Left column on desktop/tablet, top block on mobile.
  final Widget primary;

  /// Right column on desktop/tablet, bottom block on mobile.
  final Widget secondary;

  final int primaryFlex;
  final int secondaryFlex;
  final double gap;

  /// When `true` the stacked mobile layout is wrapped in a
  /// [SingleChildScrollView] so long content scrolls naturally.
  final bool stackedScrollable;

  @override
  Widget build(BuildContext context) {
    if (context.isMobile) {
      final child = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          primary,
          SizedBox(height: gap),
          secondary,
        ],
      );
      if (stackedScrollable) {
        return SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          child: child,
        );
      }
      return child;
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Flexible(flex: primaryFlex, child: primary),
        SizedBox(width: gap),
        Flexible(flex: secondaryFlex, child: secondary),
      ],
    );
  }
}

/// Centres its [child] horizontally with an optional max width constraint,
/// which is useful on wide desktop windows. On mobile the child fills the
/// viewport as usual.
class ReadableWidthContainer extends StatelessWidget {
  const ReadableWidthContainer({
    super.key,
    required this.child,
    this.maxWidth,
    this.padding,
  });

  final Widget child;
  final double? maxWidth;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final effective = maxWidth ?? context.readableMaxWidth;
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: effective),
        child: Padding(
          padding: padding ?? EdgeInsets.zero,
          child: child,
        ),
      ),
    );
  }
}
