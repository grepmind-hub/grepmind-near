import 'package:flutter/material.dart';

import 'abashyaka_colors.dart';

/// Official gradient system for Abashyaka Metallic Teal + Pearl White UI.
abstract final class AbashyakaGradients {
  /// Metallic button gradient: luminousAqua -> metallicTeal -> signatureTeal
  static const LinearGradient metallicButton = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [
      AbashyakaColors.luminousAqua,
      AbashyakaColors.metallicTeal,
      AbashyakaColors.signatureTeal,
    ],
    stops: [0.0, 0.45, 1.0],
  );

  /// Brand dark gradient (used for Splash & dark headers)
  static const LinearGradient brandDark = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [
      AbashyakaColors.darkOceanTeal,
      AbashyakaColors.signatureTeal,
      AbashyakaColors.metallicTeal,
    ],
    stops: [0.0, 0.55, 1.0],
  );

  /// Promotional banner gradient: signatureTeal -> metallicTeal -> luminousAqua
  static const LinearGradient promotionalBanner = LinearGradient(
    begin: Alignment.bottomLeft,
    end: Alignment.topRight,
    colors: [
      AbashyakaColors.signatureTeal,
      AbashyakaColors.metallicTeal,
      AbashyakaColors.luminousAqua,
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
