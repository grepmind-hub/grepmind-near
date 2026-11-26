import 'package:flutter/material.dart';

import '../theme/abashyaka_colors.dart';

/// Available variants for the FluidWavePainter.
enum FluidWaveVariant {
  brandLight,
  brandDark,
  onboarding,
  auth,
  discovery,
  compact,
  promotional,
  tracking,
  profile,
  merchant,
  rider,
}

/// A lightweight, high-performance CustomPainter that renders
/// metallic teal abstract fluid waves using normalized cubic and quadratic
/// Bézier curves, translucent layers, and subtle glossy highlights.
class FluidWavePainter extends CustomPainter {
  final FluidWaveVariant variant;
  final double progress; // For optional subtle motion or transition
  final Brightness brightness;

  const FluidWavePainter({
    this.variant = FluidWaveVariant.brandLight,
    this.progress = 1.0,
    this.brightness = Brightness.light,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;

    if (brightness == Brightness.dark && variant != FluidWaveVariant.brandDark) {
      _paintMidnightSlateWave(canvas, size);
      return;
    }

    switch (variant) {
      case FluidWaveVariant.brandDark:
        _paintBrandDark(canvas, size);
        break;
      case FluidWaveVariant.brandLight:
        _paintBrandLight(canvas, size);
        break;
      case FluidWaveVariant.onboarding:
        _paintOnboarding(canvas, size);
        break;
      case FluidWaveVariant.auth:
        _paintAuth(canvas, size);
        break;
      case FluidWaveVariant.discovery:
        _paintDiscovery(canvas, size);
        break;
      case FluidWaveVariant.promotional:
        _paintPromotional(canvas, size);
        break;
      default:
        _paintCompact(canvas, size);
        break;
    }
  }

  /// Screen 02: Splash Screen (Dark metallic teal base with glowing fluid wave ribbons)
  void _paintBrandDark(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // 1. Deep background gradient
    final bgRect = Offset.zero & size;
    final bgPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          AbashyakaColors.darkOceanTeal,
          AbashyakaColors.deepMetallicTeal,
          AbashyakaColors.darkOceanTeal,
        ],
        stops: [0.0, 0.5, 1.0],
      ).createShader(bgRect);
    canvas.drawRect(bgRect, bgPaint);

    // 2. Soft radial glow in the center-top
    final glowPaint = Paint()
      ..shader = RadialGradient(
        center: const Alignment(-0.2, -0.1),
        radius: 0.9,
        colors: [
          AbashyakaColors.aquaGlow.withValues(alpha: 0.18),
          Colors.transparent,
        ],
      ).createShader(bgRect);
    canvas.drawRect(bgRect, glowPaint);

    // 3. Broad fluid wave 1 (sweeping from middle-left to top-right)
    final path1 = Path()
      ..moveTo(0, h * 0.28)
      ..cubicTo(w * 0.25, h * 0.38, w * 0.55, h * 0.15, w, h * 0.24)
      ..lineTo(w, 0)
      ..lineTo(0, 0)
      ..close();

    final paint1 = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          AbashyakaColors.deepMetallicTeal.withValues(alpha: 0.4),
          AbashyakaColors.metallicTeal.withValues(alpha: 0.25),
        ],
      ).createShader(bgRect);
    canvas.drawPath(path1, paint1);

    // 4. Large sweeping ribbon from bottom-left up to middle-right
    final path2 = Path()
      ..moveTo(0, h * 0.62)
      ..cubicTo(w * 0.35, h * 0.58, w * 0.60, h * 0.42, w, h * 0.32)
      ..lineTo(w, h * 0.48)
      ..cubicTo(w * 0.55, h * 0.62, w * 0.25, h * 0.72, 0, h * 0.70)
      ..close();

    final paint2 = Paint()
      ..shader = LinearGradient(
        begin: Alignment.bottomLeft,
        end: Alignment.topRight,
        colors: [
          AbashyakaColors.aquaGlow.withValues(alpha: 0.22),
          AbashyakaColors.brightTeal.withValues(alpha: 0.35),
          AbashyakaColors.metallicTeal.withValues(alpha: 0.15),
        ],
      ).createShader(bgRect);
    canvas.drawPath(path2, paint2);

    // 5. Crisp luminous stroke along ribbon edge
    final strokePath = Path()
      ..moveTo(0, h * 0.62)
      ..cubicTo(w * 0.35, h * 0.58, w * 0.60, h * 0.42, w, h * 0.32);

    final strokePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..shader = LinearGradient(
        begin: Alignment.bottomLeft,
        end: Alignment.topRight,
        colors: [
          AbashyakaColors.lightAqua.withValues(alpha: 0.55),
          AbashyakaColors.aquaGlow.withValues(alpha: 0.85),
          Colors.transparent,
        ],
      ).createShader(bgRect);
    canvas.drawPath(strokePath, strokePaint);

    // 6. Bottom wave
    final pathBottom = Path()
      ..moveTo(0, h * 0.82)
      ..cubicTo(w * 0.4, h * 0.88, w * 0.7, h * 0.78, w, h * 0.85)
      ..lineTo(w, h)
      ..lineTo(0, h)
      ..close();

    final paintBottom = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          AbashyakaColors.deepMetallicTeal.withValues(alpha: 0.5),
          AbashyakaColors.darkOceanTeal.withValues(alpha: 0.8),
        ],
      ).createShader(bgRect);
    canvas.drawPath(pathBottom, paintBottom);
  }

  /// Screen 01: Opening Screen (Pearl white base with top teal wave and bottom dark wave)
  void _paintBrandLight(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final bgRect = Offset.zero & size;

    // 1. Pearl White base
    canvas.drawRect(bgRect, Paint()..color = AbashyakaColors.pearlWhite);

    // Subtle radial light at center
    final lightPaint = Paint()
      ..shader = RadialGradient(
        center: Alignment.center,
        radius: 0.8,
        colors: [AbashyakaColors.pureWhite, AbashyakaColors.pearlWhite],
      ).createShader(bgRect);
    canvas.drawRect(bgRect, lightPaint);

    // 2. Top wave layer 1 (outer soft tint)
    final topPath1 = Path()
      ..moveTo(0, h * 0.22)
      ..cubicTo(w * 0.3, h * 0.16, w * 0.7, h * 0.25, w, h * 0.14)
      ..lineTo(w, 0)
      ..lineTo(0, 0)
      ..close();

    final topPaint1 = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          AbashyakaColors.lightAqua.withValues(alpha: 0.45),
          AbashyakaColors.aquaGlow.withValues(alpha: 0.20),
        ],
      ).createShader(bgRect);
    canvas.drawPath(topPath1, topPaint1);

    // Top wave layer 2 (metallic teal sweep)
    final topPath2 = Path()
      ..moveTo(0, h * 0.15)
      ..cubicTo(w * 0.25, h * 0.08, w * 0.65, h * 0.18, w, h * 0.07)
      ..lineTo(w, 0)
      ..lineTo(0, 0)
      ..close();

    final topPaint2 = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          AbashyakaColors.metallicTeal.withValues(alpha: 0.55),
          AbashyakaColors.brightTeal.withValues(alpha: 0.35),
        ],
      ).createShader(bgRect);
    canvas.drawPath(topPath2, topPaint2);

    // Top wave stroke highlight
    final topStroke = Path()
      ..moveTo(0, h * 0.15)
      ..cubicTo(w * 0.25, h * 0.08, w * 0.65, h * 0.18, w, h * 0.07);
    canvas.drawPath(
      topStroke,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..color = AbashyakaColors.aquaGlow.withValues(alpha: 0.6),
    );

    // 3. Bottom waves (blending with Odisha landmark)
    final bottomPath1 = Path()
      ..moveTo(0, h * 0.88)
      ..cubicTo(w * 0.35, h * 0.84, w * 0.65, h * 0.90, w, h * 0.85)
      ..lineTo(w, h)
      ..lineTo(0, h)
      ..close();

    final bottomPaint1 = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          AbashyakaColors.metallicTeal.withValues(alpha: 0.35),
          AbashyakaColors.deepMetallicTeal.withValues(alpha: 0.70),
        ],
      ).createShader(bgRect);
    canvas.drawPath(bottomPath1, bottomPaint1);

    final bottomPath2 = Path()
      ..moveTo(0, h * 0.93)
      ..cubicTo(w * 0.4, h * 0.95, w * 0.7, h * 0.91, w, h * 0.94)
      ..lineTo(w, h)
      ..lineTo(0, h)
      ..close();

    final bottomPaint2 = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          AbashyakaColors.deepMetallicTeal,
          AbashyakaColors.darkOceanTeal,
        ],
      ).createShader(bgRect);
    canvas.drawPath(bottomPath2, bottomPaint2);
  }

  /// Screen 03: Onboarding / Get Started header
  void _paintOnboarding(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final bgRect = Offset.zero & size;

    // Header wave from top
    final wave1 = Path()
      ..moveTo(0, h * 0.75)
      ..cubicTo(w * 0.3, h * 0.95, w * 0.7, h * 0.60, w, h * 0.70)
      ..lineTo(w, 0)
      ..lineTo(0, 0)
      ..close();

    final paint1 = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          AbashyakaColors.lightAqua.withValues(alpha: 0.35),
          AbashyakaColors.iceAquaWhite.withValues(alpha: 0.60),
        ],
      ).createShader(bgRect);
    canvas.drawPath(wave1, paint1);

    final wave2 = Path()
      ..moveTo(0, h * 0.50)
      ..cubicTo(w * 0.35, h * 0.65, w * 0.65, h * 0.40, w, h * 0.55)
      ..lineTo(w, 0)
      ..lineTo(0, 0)
      ..close();

    final paint2 = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          AbashyakaColors.metallicTeal.withValues(alpha: 0.20),
          AbashyakaColors.aquaGlow.withValues(alpha: 0.12),
        ],
      ).createShader(bgRect);
    canvas.drawPath(wave2, paint2);
  }

  /// Screen 04 & 05: Auth (Login & OTP)
  void _paintAuth(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final bgRect = Offset.zero & size;

    // Top flowing curves
    final topWave1 = Path()
      ..moveTo(0, h * 0.20)
      ..cubicTo(w * 0.25, h * 0.26, w * 0.65, h * 0.12, w, h * 0.18)
      ..lineTo(w, 0)
      ..lineTo(0, 0)
      ..close();

    final paintTop1 = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          AbashyakaColors.metallicTeal.withValues(alpha: 0.25),
          AbashyakaColors.brightTeal.withValues(alpha: 0.12),
        ],
      ).createShader(bgRect);
    canvas.drawPath(topWave1, paintTop1);

    final topWave2 = Path()
      ..moveTo(0, h * 0.12)
      ..cubicTo(w * 0.4, h * 0.18, w * 0.7, h * 0.08, w, h * 0.12)
      ..lineTo(w, 0)
      ..lineTo(0, 0)
      ..close();

    final paintTop2 = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          AbashyakaColors.brightTeal.withValues(alpha: 0.35),
          AbashyakaColors.aquaGlow.withValues(alpha: 0.20),
        ],
      ).createShader(bgRect);
    canvas.drawPath(topWave2, paintTop2);

    // Subtle bottom wave
    final bottomWave = Path()
      ..moveTo(0, h * 0.94)
      ..cubicTo(w * 0.35, h * 0.91, w * 0.7, h * 0.96, w, h * 0.93)
      ..lineTo(w, h)
      ..lineTo(0, h)
      ..close();

    final paintBottom = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          AbashyakaColors.lightAqua.withValues(alpha: 0.25),
          AbashyakaColors.iceAquaWhite.withValues(alpha: 0.50),
        ],
      ).createShader(bgRect);
    canvas.drawPath(bottomWave, paintBottom);
  }

  /// Screen 06: Discovery / Home screen header (Option 4 Pearl White Vector)
  void _paintDiscovery(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final bgRect = Offset.zero & size;

    // Pearl White base behind the bottom curve
    canvas.drawRect(
      bgRect,
      Paint()..color = AbashyakaColors.pearlWhite,
    );

    // Primary rich Signature Teal -> Metallic Teal wave
    final path1 = Path()
      ..moveTo(0, 0)
      ..lineTo(w, 0)
      ..lineTo(w, h * 0.76)
      ..quadraticBezierTo(w * 0.72, h * 0.98, w * 0.45, h * 0.78)
      ..quadraticBezierTo(w * 0.2, h * 0.60, 0, h * 0.84)
      ..close();

    canvas.drawPath(
      path1,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AbashyakaColors.signatureTeal,
            AbashyakaColors.metallicTeal,
          ],
        ).createShader(bgRect),
    );

    // Secondary Luminous Aqua -> Aqua Glow layered wave
    final path2 = Path()
      ..moveTo(0, 0)
      ..lineTo(w, 0)
      ..lineTo(w, h * 0.56)
      ..quadraticBezierTo(w * 0.65, h * 0.82, w * 0.35, h * 0.60)
      ..quadraticBezierTo(w * 0.14, h * 0.44, 0, h * 0.66)
      ..close();

    canvas.drawPath(
      path2,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [
            AbashyakaColors.luminousAqua.withValues(alpha: 0.65),
            AbashyakaColors.aquaGlow.withValues(alpha: 0.35),
          ],
        ).createShader(bgRect),
    );

    // Crisp specular aqua rim along the wave edge
    final rimPath = Path()
      ..moveTo(0, h * 0.84)
      ..quadraticBezierTo(w * 0.2, h * 0.60, w * 0.45, h * 0.78)
      ..quadraticBezierTo(w * 0.72, h * 0.98, w, h * 0.76);

    canvas.drawPath(
      rimPath,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..color = AbashyakaColors.lightAqua.withValues(alpha: 0.85),
    );
  }

  /// Promotional banner wave background
  void _paintPromotional(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final bgRect = Offset.zero & size;

    final path = Path()
      ..moveTo(0, h * 0.5)
      ..cubicTo(w * 0.3, h * 0.8, w * 0.7, h * 0.2, w, h * 0.6)
      ..lineTo(w, h)
      ..lineTo(0, h)
      ..close();

    final paint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          AbashyakaColors.brightTeal.withValues(alpha: 0.25),
          AbashyakaColors.aquaGlow.withValues(alpha: 0.15),
        ],
      ).createShader(bgRect);
    canvas.drawPath(path, paint);
  }

  void _paintCompact(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final bgRect = Offset.zero & size;

    canvas.drawRect(
      bgRect,
      Paint()..color = AbashyakaColors.pearlWhite,
    );

    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(w, 0)
      ..lineTo(w, h * 0.78)
      ..quadraticBezierTo(w * 0.5, h * 1.04, 0, h * 0.84)
      ..close();

    canvas.drawPath(
      path,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AbashyakaColors.signatureTeal,
            AbashyakaColors.metallicTeal,
          ],
        ).createShader(bgRect),
    );
  }

  /// Option 2: Midnight Slate & Luminous Aqua Dark Mode vector wave
  void _paintMidnightSlateWave(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final bgRect = Offset.zero & size;

    canvas.drawRect(
      bgRect,
      Paint()..color = const Color(0xFF0B1320),
    );

    final isHeader =
        variant == FluidWaveVariant.discovery ||
        variant == FluidWaveVariant.compact ||
        variant == FluidWaveVariant.profile;
    final waveBottom = isHeader ? h * 0.78 : h * 0.34;

    final primaryWave = Path()
      ..moveTo(0, 0)
      ..lineTo(w, 0)
      ..lineTo(w, waveBottom * 0.96)
      ..quadraticBezierTo(w * 0.72, waveBottom * 1.24, w * 0.45, waveBottom * 0.98)
      ..quadraticBezierTo(w * 0.2, waveBottom * 0.76, 0, waveBottom * 1.06)
      ..close();

    canvas.drawPath(
      primaryWave,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AbashyakaColors.signatureTeal,
            AbashyakaColors.metallicTeal,
          ],
        ).createShader(bgRect),
    );

    final accentWave = Path()
      ..moveTo(0, 0)
      ..lineTo(w, 0)
      ..lineTo(w, waveBottom * 0.70)
      ..quadraticBezierTo(w * 0.65, waveBottom * 1.02, w * 0.35, waveBottom * 0.75)
      ..quadraticBezierTo(w * 0.14, waveBottom * 0.56, 0, waveBottom * 0.82)
      ..close();

    canvas.drawPath(
      accentWave,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [
            AbashyakaColors.aquaGlow.withValues(alpha: 0.55),
            AbashyakaColors.luminousAqua.withValues(alpha: 0.28),
          ],
        ).createShader(bgRect),
    );

    final rimPath = Path()
      ..moveTo(0, waveBottom * 1.06)
      ..quadraticBezierTo(w * 0.2, waveBottom * 0.76, w * 0.45, waveBottom * 0.98)
      ..quadraticBezierTo(w * 0.72, waveBottom * 1.24, w, waveBottom * 0.96);

    canvas.drawPath(
      rimPath,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..color = AbashyakaColors.aquaGlow.withValues(alpha: 0.78),
    );
  }

  @override
  bool shouldRepaint(covariant FluidWavePainter oldDelegate) {
    return oldDelegate.variant != variant ||
        oldDelegate.progress != progress ||
        oldDelegate.brightness != brightness;
  }
}
