import 'package:flutter/material.dart';

import 'fluid_wave_painter.dart';

/// Performance-isolated vector fluid wave background wrapped in [RepaintBoundary].
///
/// Automatically adapts between Pearl White Light Mode and Midnight Slate Dark Mode
/// via `Theme.of(context).brightness` without decoding static raster bitmaps.
class FluidWaveBackground extends StatelessWidget {
  const FluidWaveBackground({
    super.key,
    this.variant = FluidWaveVariant.discovery,
    this.child,
  });

  final FluidWaveVariant variant;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return RepaintBoundary(
      child: CustomPaint(
        painter: FluidWavePainter(
          variant: variant,
          brightness: brightness,
        ),
        child: child ?? const SizedBox.expand(),
      ),
    );
  }
}
