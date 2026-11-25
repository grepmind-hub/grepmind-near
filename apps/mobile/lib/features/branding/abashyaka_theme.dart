import 'package:flutter/material.dart';

import '../../core/theme/abashyaka_colors.dart';

export '../../core/theme/abashyaka_colors.dart';
export '../../core/theme/abashyaka_tokens.dart';
export '../../core/theme/abashyaka_gradients.dart';
export '../../core/theme/abashyaka_typography.dart';

/// 2026 Abashyaka Design System & Brand Identity Tokens.
///
/// Design Language:
/// **Metallic Teal Abstract Fluid Wave + Pearl White Glossy UI**
abstract final class AbashyakaTheme {
  // --- Authoritative Color Tokens ---
  static const Color vibrantGreen = AbashyakaColors.brightTeal;
  static const Color actionGreen = AbashyakaColors.metallicTeal;
  static const Color deepEmerald = AbashyakaColors.deepMetallicTeal;
  static const Color freshLeaf = AbashyakaColors.aquaGlow;
  static const Color softLime = AbashyakaColors.lightAqua;
  static const Color lightMint = AbashyakaColors.lightAqua;
  static const Color pearlGreen = AbashyakaColors.pearlWhite;
  static const Color signatureOrange = AbashyakaColors.warning;
  static const Color warmPeach = Color(0xFFFFE4D1);
  static const Color skyBlue = AbashyakaColors.information;
  static const Color pureWhite = AbashyakaColors.pureWhite;
  static const Color carbon = AbashyakaColors.inkBlack;
  static const Color mutedSlate = AbashyakaColors.secondaryText;
  static const Color border = AbashyakaColors.silverGlass;

  // --- Convenience & Semantic Aliases ---
  static const Color green = actionGreen;
  static const Color darkGreen = deepEmerald;
  static const Color mint = lightMint;
  static const Color orange = signatureOrange;
  static const Color warmWhite = pureWhite;
  static const Color canvas = pearlGreen;
  static const Color surface = pureWhite;
  static const Color text = carbon;
  static const Color muted = mutedSlate;
  static const Color signatureEmerald = actionGreen;

  // --- Sizing, Radii & Motion ---
  static const double space = 4.0;
  static const double pagePadding = 16.0;
  static const double cardRadius = 18.0;
  static const double controlRadius = 18.0;
  static const double pillRadius = 28.0;
  static const double touchTarget = 48.0;
  static const double elevation = 0.0;
  static const Duration entrance = Duration(milliseconds: 400);
  static const Duration transition = Duration(milliseconds: 200);

  // --- Brand Assets ---
  static const String logo = 'assets/abashyaka/brand_logo_teal_aqua.png';
  static const String logoMetallic =
      'assets/abashyaka/brand_logo_metallic_teal.png';
  static const String logoWhite = 'assets/abashyaka/brand_logo_white_teal.png';
  static const String logoWhitePure =
      'assets/abashyaka/brand_logo_white_pure.png';
  static const String splashEmblem = 'assets/abashyaka/splash_emblem.png';
  static const String splashLandscape = 'assets/abashyaka/splash_landscape.png';
  static const String illustration = 'assets/abashyaka/onboarding_3d_phone.png';
  static const String onboardingHero =
      'assets/abashyaka/onboarding_3d_phone.png';

  // --- Button Styles ---
  static ButtonStyle actionGreenButtonStyle({
    double radius = pillRadius,
    double height = 54.0,
  }) => ElevatedButton.styleFrom(
    backgroundColor: actionGreen,
    foregroundColor: pureWhite,
    elevation: 0,
    minimumSize: Size(double.infinity, height),
    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 15),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius)),
    textStyle: const TextStyle(
      fontSize: 16,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.1,
    ),
  );

  static ButtonStyle vibrantGreenButtonStyle({
    double radius = pillRadius,
    double height = 54.0,
  }) => ElevatedButton.styleFrom(
    backgroundColor: vibrantGreen,
    foregroundColor: pureWhite,
    elevation: 0,
    minimumSize: Size(double.infinity, height),
    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 15),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius)),
    textStyle: const TextStyle(
      fontSize: 16,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.1,
    ),
  );

  static ButtonStyle orangeButtonStyle({
    double radius = pillRadius,
    double height = 54.0,
  }) => ElevatedButton.styleFrom(
    backgroundColor: signatureOrange,
    foregroundColor: pureWhite,
    elevation: 0,
    minimumSize: Size(double.infinity, height),
    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 15),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius)),
    textStyle: const TextStyle(
      fontSize: 16,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.1,
    ),
  );

  static ThemeData theme(BuildContext context) {
    final base = Theme.of(context);
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(pillRadius),
    );
    return base.copyWith(
      scaffoldBackgroundColor: AbashyakaColors.pearlWhite,
      colorScheme: ColorScheme.fromSeed(seedColor: actionGreen).copyWith(
        primary: actionGreen,
        onPrimary: pureWhite,
        secondary: vibrantGreen,
        onSecondary: pureWhite,
        surface: pureWhite,
      ),
      textTheme: base.textTheme.apply(
        bodyColor: carbon,
        displayColor: deepEmerald,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: actionGreen,
          foregroundColor: pureWhite,
          minimumSize: const Size.fromHeight(54),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          shape: shape,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: actionGreen,
          side: const BorderSide(color: border, width: 1.5),
          minimumSize: const Size.fromHeight(54),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          shape: shape,
        ),
      ),
    );
  }
}
