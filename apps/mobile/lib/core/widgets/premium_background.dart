import 'package:flutter/material.dart';

import '../theme/abashyaka_colors.dart';
import 'fluid_wave_painter.dart';

/// Reusable background wrapper providing the official
/// Metallic Teal Fluid Wave + Pearl White background.
class PremiumBackground extends StatelessWidget {
  final Widget child;
  final FluidWaveVariant variant;
  final bool useSafeArea;
  final Color backgroundColor;

  const PremiumBackground({
    super.key,
    required this.child,
    this.variant = FluidWaveVariant.brandLight,
    this.useSafeArea = true,
    this.backgroundColor = AbashyakaColors.pearlWhite,
  });

  @override
  Widget build(BuildContext context) {
    Widget content = CustomPaint(
      painter: FluidWavePainter(variant: variant),
      child: child,
    );

    if (useSafeArea) {
      content = SafeArea(child: content);
    }

    return Scaffold(
      backgroundColor: variant == FluidWaveVariant.brandDark
          ? AbashyakaColors.darkOceanTeal
          : backgroundColor,
      body: content,
    );
  }
}
