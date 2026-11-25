import 'package:flutter/material.dart';

import 'abashyaka_colors.dart';

/// Official gradient system for Abashyaka Metallic Teal + Pearl White UI.
abstract final class AbashyakaGradients {
  /// Metallic button gradient: brightTeal -> metallicTeal -> deepMetallicTeal
  static const LinearGradient metallicButton = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [
      AbashyakaColors.brightTeal,
      AbashyakaColors.metallicTeal,
      AbashyakaColors.deepMetallicTeal,
    ],
    stops: [0.0, 0.45, 1.0],
  );

  /// Brand dark gradient (used for Splash & dark headers)
  static const LinearGradient brandDark = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [
      AbashyakaColors.darkOceanTeal,
      AbashyakaColors.deepMetallicTeal,
      AbashyakaColors.metallicTeal,
    ],
    stops: [0.0, 0.55, 1.0],
  );

  /// Promotional banner gradient: darkOceanTeal -> metallicTeal -> aquaGlow
  static const LinearGradient promotionalBanner = LinearGradient(
    begin: Alignment.bottomLeft,
    end: Alignment.topRight,
    colors: [
      AbashyakaColors.darkOceanTeal,
      AbashyakaColors.metallicTeal,
      AbashyakaColors.aquaGlow,
    ],
    stops: [0.0, 0.65, 1.0],
  );

  /// Soft Pearl White background gradient
  static const LinearGradient pearlBackground = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [AbashyakaColors.luminousWhite, AbashyakaColors.pearlWhite],
    stops: [0.0, 1.0],
  );

  /// Header transition gradient
  static const LinearGradient headerTransition = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [AbashyakaColors.iceAquaWhite, AbashyakaColors.pearlWhite],
    stops: [0.0, 1.0],
  );

  /// Top glossy highlight overlay for buttons
  static const LinearGradient buttonGlassHighlight = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0x40FFFFFF), Color(0x00FFFFFF)],
    stops: [0.0, 0.6],
  );
}
