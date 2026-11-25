import 'package:flutter/material.dart';

import '../theme/abashyaka_colors.dart';
import '../theme/abashyaka_gradients.dart';
import '../theme/abashyaka_tokens.dart';
import '../theme/abashyaka_typography.dart';
import 'fluid_wave_painter.dart';

/// The official promotional hero banner for Abashyaka Home screen.
class PremiumBanner extends StatelessWidget {
  final String title;
  final String subtitle;
  final String buttonText;
  final VoidCallback? onExploreTap;
  final Widget? illustration;
  final double height;
  final double radius;

  const PremiumBanner({
    super.key,
    this.title = 'Everything local.',
    this.subtitle = 'At your doorstep.',
    this.buttonText = 'Explore Now',
    this.onExploreTap,
    this.illustration,
    this.height = 155.0,
    this.radius = AbashyakaRadius.banner,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        gradient: AbashyakaGradients.promotionalBanner,
        boxShadow: const [
          BoxShadow(
            color: Color(0x24003F46),
            blurRadius: 16,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: Stack(
          children: [
            // Decorative background fluid wave
            Positioned.fill(
              child: CustomPaint(
                painter: const FluidWavePainter(
                  variant: FluidWaveVariant.promotional,
                ),
              ),
            ),

            // Foreground Content
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: Row(
                children: [
                  // Text and CTA
                  Expanded(
                    flex: 6,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          title,
                          style:
                              AbashyakaTypography.displayHeading(
                                color: AbashyakaColors.pureWhite,
                              ).copyWith(
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.3,
                              ),
                        ),
                        Text(
                          subtitle,
                          style: AbashyakaTypography.bodyMedium(
                            color: AbashyakaColors.lightAqua,
                          ).copyWith(fontSize: 14, fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 12),

                        // Explore Now Button
                        InkWell(
                          onTap: onExploreTap,
                          borderRadius: BorderRadius.circular(20),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 7,
                            ),
                            decoration: BoxDecoration(
                              color: AbashyakaColors.pureWhite,
                              borderRadius: BorderRadius.circular(20),
                              boxShadow: const [
                                BoxShadow(
                                  color: Color(0x1F000000),
                                  blurRadius: 6,
                                  offset: Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  buttonText,
                                  style:
                                      AbashyakaTypography.buttonText(
                                        color: AbashyakaColors.deepMetallicTeal,
                                      ).copyWith(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                      ),
                                ),
                                const SizedBox(width: 4),
                                const Icon(
                                  Icons.arrow_forward_rounded,
                                  color: AbashyakaColors.deepMetallicTeal,
                                  size: 13,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Right 3D Illustration / Graphic
                  Expanded(
                    flex: 4,
                    child: Align(
                      alignment: Alignment.centerRight,
                      child:
                          illustration ??
                          Image.asset(
                            'assets/abashyaka/home_banner_bags.png',
                            height: 100,
                            fit: BoxFit.contain,
                            errorBuilder: (context, error, stackTrace) =>
                                const Icon(
                                  Icons.shopping_bag_outlined,
                                  size: 64,
                                  color: AbashyakaColors.aquaGlow,
                                ),
                          ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
