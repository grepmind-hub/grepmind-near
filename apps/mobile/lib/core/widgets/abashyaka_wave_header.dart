import 'package:flutter/material.dart';
import 'package:grepmind_mobile/core/theme/app_theme.dart';
import 'package:grepmind_mobile/core/widgets/abashyaka_logo_mark.dart';
import 'package:grepmind_mobile/core/widgets/fluid_wave_background.dart';
import 'package:grepmind_mobile/core/widgets/fluid_wave_painter.dart';

/// Shared compact Metallic Teal FluidWave header with the official Option 2
/// [AbashyakaLogoMark] badge, optional back button, subtitle, action icons,
/// and optional bottom slot (e.g. search bar or [TabBar]).
///
/// Adapts seamlessly between Pearl White Light Mode and Midnight Slate Dark Mode.
class AbashyakaWaveHeader extends StatelessWidget {
  const AbashyakaWaveHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.variant = FluidWaveVariant.discovery,
    this.showBackButton,
    this.onBack,
    this.actions = const [],
    this.bottom,
    this.showLogo = true,
  });

  final String title;
  final String? subtitle;
  final FluidWaveVariant variant;
  final bool? showBackButton;
  final VoidCallback? onBack;
  final List<Widget> actions;
  final Widget? bottom;
  final bool showLogo;

  @override
  Widget build(BuildContext context) {
    final palette = context.abashyaka;
    final canPop = showBackButton ?? Navigator.canPop(context);
    final headerTextColor = Colors.white;
    final subtitleColor = Colors.white.withValues(alpha: 0.86);

    return ClipRect(
      child: Stack(
        children: [
          Positioned.fill(
            child: FluidWaveBackground(
              variant: variant,
              child: const SizedBox.expand(),
            ),
          ),
          SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      if (canPop) ...[
                        _HeaderIconButton(
                          icon: Icons.arrow_back_rounded,
                          tooltip: 'Back',
                          onPressed:
                              onBack ?? () => Navigator.of(context).maybePop(),
                        ),
                        const SizedBox(width: 8),
                      ],
                      if (showLogo) ...[
                        Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            color: palette.isDark
                                ? const Color(0xFF0F1E2E)
                                : Colors.white,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.25),
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.14),
                                blurRadius: 8,
                                offset: const Offset(0, 3),
                              ),
                            ],
                          ),
                          child: const Center(
                            child: AbashyakaLogoMark(size: 28),
                          ),
                        ),
                        const SizedBox(width: 10),
                      ],
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w800,
                                color: headerTextColor,
                                letterSpacing: -0.3,
                              ),
                            ),
                            if (subtitle != null && subtitle!.isNotEmpty) ...[
                              const SizedBox(height: 1),
                              Text(
                                subtitle!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: subtitleColor,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      if (actions.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        Row(mainAxisSize: MainAxisSize.min, children: actions),
                      ],
                    ],
                  ),
                  if (bottom != null) ...[
                    const SizedBox(height: 8),
                    bottom!,
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HeaderIconButton extends StatelessWidget {
  const _HeaderIconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.16),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onPressed,
        child: SizedBox(
          width: 40,
          height: 40,
          child: Tooltip(
            message: tooltip,
            child: Icon(icon, color: Colors.white, size: 20),
          ),
        ),
      ),
    );
  }
}

/// Consistent frosted icon action button for use in [AbashyakaWaveHeader.actions].
class AbashyakaWaveActionButton extends StatelessWidget {
  const AbashyakaWaveActionButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.16),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onPressed,
        child: SizedBox(
          width: 40,
          height: 40,
          child: Tooltip(
            message: tooltip,
            child: Icon(
              icon,
              color: onPressed == null
                  ? Colors.white.withValues(alpha: 0.45)
                  : Colors.white,
              size: 20,
            ),
          ),
        ),
      ),
    );
  }
}
