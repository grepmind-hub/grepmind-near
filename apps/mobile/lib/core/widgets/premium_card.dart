import 'package:flutter/material.dart';
import 'package:grepmind_mobile/core/theme/app_theme.dart';

/// Premium container card used across listing surfaces.
///
/// Rounded, bordered, subtle elevation, consistent padding.
class PremiumCard extends StatelessWidget {
  const PremiumCard({
    super.key,
    this.child,
    this.padding = const EdgeInsets.all(16),
    this.radius = kCardRadius,
    this.elevation = 0,
    this.borderColor = AppTheme.border,
    this.color = AppTheme.surface,
    this.onTap,
    this.margin,
  });

  final Widget? child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final double elevation;
  final Color borderColor;
  final Color color;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry? margin;

  @override
  Widget build(BuildContext context) {
    final card = Container(
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: borderColor),
        boxShadow: elevation > 0
            ? [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ]
            : null,
      ),
      child: padding == EdgeInsets.zero ? child! : Padding(padding: padding, child: child!),
    );

    if (onTap == null) return margin != null ? Container(margin: margin, child: card) : card;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(radius),
        child: margin != null ? Container(margin: margin, child: card) : card,
      ),
    );
  }
}

/// Rounded container for grouped content sections.
class PremiumSection extends StatelessWidget {
  const PremiumSection({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.symmetric(horizontal: kScreenPadding, vertical: 12),
    this.radius = kCardRadius,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return PremiumCard(
      padding: padding,
      radius: radius,
      child: child,
    );
  }
}
