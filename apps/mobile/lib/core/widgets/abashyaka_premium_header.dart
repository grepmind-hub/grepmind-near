import 'package:flutter/material.dart';

import '../theme/abashyaka_colors.dart';
import '../theme/abashyaka_palette.dart';
import '../theme/abashyaka_tokens.dart';
import '../theme/abashyaka_typography.dart';
import 'fluid_wave_painter.dart';

/// The official reusable header for Abashyaka screens.
///
/// Supports:
/// - Brand Discovery header (Logo, Wordmark, Location, Notification bell, Search bar)
/// - Auth header (Back navigation, Logo, Title)
/// - Onboarding header (Skip button, Wave artwork)
/// - Compact page headers
class AbashyakaPremiumHeader extends StatelessWidget {
  final FluidWaveVariant variant;
  final Widget? leading;
  final Widget? trailing;
  final String? title;
  final String? subtitle;
  final Widget? bottom;
  final double? height;
  final bool showBrandRow;
  final String? locationText;
  final VoidCallback? onLocationTap;
  final int notificationCount;
  final VoidCallback? onNotificationTap;
  final VoidCallback? onBackTap;
  final bool showBack;

  const AbashyakaPremiumHeader({
    super.key,
    this.variant = FluidWaveVariant.discovery,
    this.leading,
    this.trailing,
    this.title,
    this.subtitle,
    this.bottom,
    this.height,
    this.showBrandRow = false,
    this.locationText,
    this.onLocationTap,
    this.notificationCount = 0,
    this.onNotificationTap,
    this.onBackTap,
    this.showBack = false,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return RepaintBoundary(
          child: CustomPaint(
            painter: FluidWavePainter(
              variant: variant,
              brightness: Theme.of(context).brightness,
            ),
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AbashyakaSpacing.screenHorizontal,
                vertical: 8,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Top Navigation / Brand Row
                  if (showBrandRow)
                    _buildDiscoveryTopRow(context)
                  else if (showBack ||
                      title != null ||
                      leading != null ||
                      trailing != null)
                    _buildNavigationRow(context),

                  // Optional Location Selector
                  if (locationText != null) ...[
                    const SizedBox(height: 8),
                    _buildLocationBar(context),
                  ],

                  // Bottom content (e.g. Search Bar or custom widgets)
                  if (bottom != null) ...[
                    const SizedBox(height: 10),
                    bottom!,
                    const SizedBox(height: 4),
                  ],
                ],
              ),
            ),
          ),
          ),
        );
      },
    );
  }

  Widget _buildDiscoveryTopRow(BuildContext context) {
    final palette = context.abashyaka;
    return Row(
      children: [
        // Brand Logo
        Image.asset(
          'assets/abashyaka/brand_logo_teal_aqua.png',
          width: 32,
          height: 32,
          fit: BoxFit.contain,
          errorBuilder: (_, _, _) => Image.asset(
            'assets/abashyaka/splash_emblem.png',
            width: 32,
            height: 32,
          ),
        ),
        const SizedBox(width: 8),

        // Brand Wordmark
        Text(
          'Abashyaka',
          style: AbashyakaTypography.brandWordmark().copyWith(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            color: palette.isDark
                ? palette.textPrimary
                : AbashyakaColors.deepMetallicTeal,
          ),
        ),

        const Spacer(),

        // Notification Bell with Badge
        Semantics(
          button: true,
          label: notificationCount > 0
              ? 'Notifications, $notificationCount unread'
              : 'Notifications',
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: palette.card,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: palette.border.withValues(alpha: 0.9),
                    width: 1.0,
                  ),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x0A003F46),
                      blurRadius: 8,
                      offset: Offset(0, 2),
                    ),
                  ],
                ),
                child: IconButton(
                  padding: EdgeInsets.zero,
                  tooltip: 'Notifications',
                  icon: Icon(
                    Icons.notifications_none_rounded,
                    color: palette.textPrimary,
                    size: 20,
                  ),
                  onPressed: onNotificationTap,
                ),
              ),
              if (notificationCount > 0)
                Positioned(
                  top: -2,
                  right: -2,
                  child: ExcludeSemantics(
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: const BoxDecoration(
                        color: AbashyakaColors.error,
                        shape: BoxShape.circle,
                      ),
                      constraints: const BoxConstraints(
                        minWidth: 16,
                        minHeight: 16,
                      ),
                      child: Text(
                        notificationCount > 9 ? '9+' : '$notificationCount',
                        style: const TextStyle(
                          color: AbashyakaColors.pureWhite,
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          height: 1.0,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildNavigationRow(BuildContext context) {
    final palette = context.abashyaka;
    return Row(
      children: [
        if (showBack)
          IconButton(
            icon: Icon(
              Icons.arrow_back_rounded,
              color: palette.textPrimary,
            ),
            onPressed: onBackTap ?? () => Navigator.of(context).maybePop(),
          )
        else if (leading != null)
          leading!,

        if (title != null) ...[
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              title!,
              style: AbashyakaTypography.pageTitle(color: palette.textPrimary),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ] else
          const Spacer(),

        if (trailing != null) trailing!,
      ],
    );
  }

  Widget _buildLocationBar(BuildContext context) {
    final palette = context.abashyaka;
    return InkWell(
      onTap: onLocationTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.location_on_outlined,
              size: 18,
              color: palette.accent,
            ),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                locationText ?? '',
                style: AbashyakaTypography.cardTitle(
                  color: palette.textPrimary,
                ).copyWith(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 2),
            Icon(
              Icons.keyboard_arrow_down_rounded,
              size: 18,
              color: palette.textSecondary,
            ),
            const SizedBox(width: 4),
            Icon(
              Icons.arrow_forward_ios_rounded,
              size: 11,
              color: palette.textSecondary,
            ),
          ],
        ),
      ),
    );
  }
}
