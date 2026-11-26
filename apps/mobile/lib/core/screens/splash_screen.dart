import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:grepmind_mobile/core/providers/app_provider.dart';
import 'package:grepmind_mobile/core/screens/admin_portal_screen.dart';
import 'package:grepmind_mobile/core/screens/role_selection_screen.dart';
import 'package:grepmind_mobile/core/theme/app_theme.dart';
import 'package:grepmind_mobile/core/widgets/abashyaka_logo_mark.dart';
import 'package:grepmind_mobile/core/widgets/fluid_wave_background.dart';
import 'package:grepmind_mobile/core/widgets/fluid_wave_painter.dart';
import 'package:grepmind_mobile/features/onboarding/introduction_screen.dart';
import 'package:grepmind_mobile/main.dart';

/// Screen 01 & 02: Opening & Splash Screen.
///
/// Implements the approved Metallic Teal Abstract Fluid Wave + Pearl White UI.
/// - Screen 01 (Flutter Premium Dark Splash): Deep ocean teal base with glowing metallic fluid wave ribbons,
///   prominent official logo, wordmark, and lightweight loading dots.
/// - Screen 02 (Opening / Regional Heritage Screen): Complete approved background
///   (bg-2-complete.png) featuring official branding, Odisha heritage artwork, and a 3-second loader
///   that auto-transitions into the app for registered users or to Onboarding for new users.
class SplashScreen extends ConsumerStatefulWidget {
  final bool isDark;
  final VoidCallback? onComplete;

  const SplashScreen({super.key, this.isDark = false, this.onComplete});

  /// Factory for the dark splash variant (Screen 01 in design system)
  const SplashScreen.dark({super.key, this.onComplete}) : isDark = true;

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    if (!widget.isDark) {
      _timer = Timer(const Duration(seconds: 3), _handleTransition);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _handleTransition() {
    if (!mounted) return;
    _timer?.cancel();
    if (widget.onComplete != null) {
      widget.onComplete!();
      return;
    }
    final authState = ref.read(authProvider);
    if (authState.isAuthenticated) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => authState.activeRole == null
              ? const RoleSelectionScreen()
              : authState.activeRole == 'admin'
              ? const AdminPortalScreen()
              : MainNavigator(
                  key: ValueKey('workspace-${authState.activeRole}'),
                  activeRole: authState.activeRole ?? 'customer',
                ),
        ),
      );
    } else {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const IntroductionScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.abashyaka;
    final dark = widget.isDark || palette.isDark;
    final canvas = dark ? const Color(0xFF0B1320) : AbashyakaColors.pearlWhite;
    final primaryText = dark ? AbashyakaColors.pureWhite : AbashyakaColors.signatureTeal;
    final subtitleText = dark
        ? const Color(0xFF94A3B8)
        : AbashyakaColors.graphiteCharcoal;

    return Scaffold(
      backgroundColor: canvas,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _handleTransition,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Top crisp vector FluidWave curve (no raster opening_complete.png)
            const Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: 190,
              child: FluidWaveBackground(
                variant: FluidWaveVariant.discovery,
                child: SizedBox.expand(),
              ),
            ),

            // Odisha Heritage landscape anchored cleanly at the bottom
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: IgnorePointer(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Image.asset(
                      'assets/abashyaka/splash_landscape.png',
                      width: double.infinity,
                      height: 175,
                      fit: BoxFit.cover,
                      alignment: Alignment.bottomCenter,
                      color: dark
                          ? const Color(0xFF0B1320).withValues(alpha: 0.25)
                          : null,
                      colorBlendMode: dark ? BlendMode.darken : null,
                      errorBuilder: (_, _, _) => const SizedBox(height: 80),
                    ),
                  ],
                ),
              ),
            ),

            // Foreground: Centered Option 2 Commerce-A Brand Lockup + Heritage Tagline
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 36, 24, 190),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    AbashyakaLogoMark(
                      size: 108,
                      badgeColor: dark
                          ? const Color(0xFF152232)
                          : AbashyakaColors.signatureTeal,
                      borderColor: dark
                          ? const Color(0xFF243447)
                          : Colors.white.withValues(alpha: 0.35),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      'Abashyaka',
                      style: AbashyakaTypography.brandWordmark(
                        color: primaryText,
                      ).copyWith(
                        fontSize: 38,
                        letterSpacing: -0.6,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: dark
                            ? const Color(0xFF152232)
                            : const Color(0xFFE6F7F7),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: dark
                              ? const Color(0xFF243447)
                              : AbashyakaColors.metallicTeal.withValues(
                                  alpha: 0.25,
                                ),
                        ),
                      ),
                      child: Text(
                        'ଆବଶ୍ୟକ · Odisha’s Own Local Commerce',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: dark
                              ? const Color(0xFF55D6CD)
                              : AbashyakaColors.signatureTeal,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Container(
                      width: 44,
                      height: 3,
                      decoration: BoxDecoration(
                        color: AbashyakaColors.saffronOrange,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'ସବୁ ଆବଶ୍ୟକତା,\nଆପଣଙ୍କ ପାଖରେ।',
                      locale: const Locale('or'),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 21,
                        fontWeight: FontWeight.w800,
                        color: primaryText,
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Everything You Need, Locally.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        fontStyle: FontStyle.italic,
                        color: subtitleText,
                      ),
                    ),
                    const SizedBox(height: 24),
                    _SplashLoadingDots(
                      color: dark
                          ? const Color(0xFF55D6CD)
                          : AbashyakaColors.deepMetallicTeal,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 3 Lightweight Loading Dots for Splash and Opening Screen
class _SplashLoadingDots extends StatefulWidget {
  final Color? color;
  const _SplashLoadingDots({this.color});

  @override
  State<_SplashLoadingDots> createState() => _SplashLoadingDotsState();
}

class _SplashLoadingDotsState extends State<_SplashLoadingDots>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final baseColor = widget.color ?? AbashyakaColors.aquaGlow;

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (index) {
            final delay = index * 0.25;
            final progress = (_controller.value - delay).clamp(0.0, 1.0);
            final scale =
                0.6 + 0.4 * (1 - (progress - 0.5).abs() * 2).clamp(0.0, 1.0);
            final opacity =
                0.4 + 0.6 * (1 - (progress - 0.5).abs() * 2).clamp(0.0, 1.0);

            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 4),
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: baseColor.withValues(alpha: opacity),
                boxShadow: [
                  BoxShadow(
                    color: baseColor.withValues(alpha: 0.4 * opacity),
                    blurRadius: 6 * scale,
                    spreadRadius: 1 * scale,
                  ),
                ],
              ),
            );
          }),
        );
      },
    );
  }
}
