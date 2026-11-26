import 'package:flutter/material.dart';

import '../theme/abashyaka_colors.dart';
import '../theme/abashyaka_palette.dart';
import '../theme/abashyaka_tokens.dart';

/// The official glossy Pure White card for Abashyaka content and categories.
class PremiumCard extends StatelessWidget {
  final Widget? child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;
  final double radius;
  final double elevation;
  final Color? borderColor;
  final Color? color;
  final VoidCallback? onTap;
  final List<BoxShadow>? shadow;
  final Border? border;
  final double? width;
  final double? height;

  const PremiumCard({
    super.key,
    this.child,
    this.padding = const EdgeInsets.all(16),
    this.margin,
    this.radius = AbashyakaRadius.lg,
    this.elevation = 0,
    this.borderColor,
    this.color,
    this.onTap,
    this.shadow,
    this.border,
    this.width,
    this.height,
  });

  @override
  Widget build(BuildContext context) {
    final palette = context.abashyaka;
    final resolvedColor = color ?? palette.card;
    final resolvedBorderColor = borderColor ?? palette.border;
    final borderRadius = BorderRadius.circular(radius);

    Widget content = Container(
      width: width,
      height: height,
      margin: margin,
      decoration: BoxDecoration(
        color: resolvedColor,
        borderRadius: borderRadius,
        border: border ?? Border.all(color: resolvedBorderColor),
        boxShadow:
            shadow ??
            (elevation > 0
                ? [
                    BoxShadow(
                      color: const Color(0x0C003F46),
                      blurRadius: 12 + elevation * 2,
                      offset: Offset(0, 2 + elevation),
                    ),
                  ]
                : AbashyakaShadows.card),
      ),
      child: ClipRRect(
        borderRadius: borderRadius,
        child: padding == EdgeInsets.zero
            ? (child ?? const SizedBox.shrink())
            : Padding(
                padding: padding,
                child: child ?? const SizedBox.shrink(),
              ),
      ),
    );

    if (onTap != null) {
      return Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: borderRadius,
          splashColor: AbashyakaColors.lightAqua.withValues(alpha: 0.2),
          child: content,
        ),
      );
    }

    return content;
  }
}

/// Rounded container for grouped content sections.
class PremiumSection extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;

  const PremiumSection({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    this.radius = AbashyakaRadius.lg,
  });

  @override
  Widget build(BuildContext context) {
    return PremiumCard(padding: padding, radius: radius, child: child);
  }
}
