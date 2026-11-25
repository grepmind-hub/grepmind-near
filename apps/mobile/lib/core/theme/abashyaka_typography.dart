import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'abashyaka_colors.dart';

/// Centralized Typography system for Abashyaka using Plus Jakarta Sans
/// with fallback to sans-serif and Odia script support.
///
/// Standardized for high contrast against Pearl White (#F5FAFA) and Pure White (#FFFFFF).
abstract final class AbashyakaTypography {
  static TextStyle _font({
    required double fontSize,
    required FontWeight fontWeight,
    Color color = AbashyakaColors.inkBlack,
    double? height,
    double? letterSpacing,
  }) {
    try {
      return GoogleFonts.plusJakartaSans(
        fontSize: fontSize,
        fontWeight: fontWeight,
        color: color,
        height: height,
        letterSpacing: letterSpacing,
      );
    } catch (_) {
      return TextStyle(
        fontFamily: 'sans-serif',
        fontSize: fontSize,
        fontWeight: fontWeight,
        color: color,
        height: height,
        letterSpacing: letterSpacing,
      );
    }
  }

  /// Brand wordmark: 32–36 logical px, weight 800
  static TextStyle brandWordmark({
    Color color = AbashyakaColors.signatureTeal,
    double fontSize = 34,
  }) => _font(
    fontSize: fontSize,
    fontWeight: FontWeight.w800,
    color: color,
    letterSpacing: -0.8,
    height: 1.15,
  );

  /// Display heading: 24–28 logical px, weight 800
  static TextStyle displayHeading({
    Color color = AbashyakaColors.inkBlack,
    double fontSize = 26,
  }) => _font(
    fontSize: fontSize,
    fontWeight: FontWeight.w800,
    color: color,
    height: 1.25,
    letterSpacing: -0.5,
  );

  /// Page title: 20–22 logical px, weight 700
  static TextStyle pageTitle({
    Color color = AbashyakaColors.inkBlack,
    double fontSize = 20,
  }) => _font(
    fontSize: fontSize,
    fontWeight: FontWeight.w700,
    color: color,
    letterSpacing: -0.3,
    height: 1.3,
  );

  /// Section title: 18–20 logical px, weight 700
  static TextStyle sectionTitle({
    Color color = AbashyakaColors.inkBlack,
    double fontSize = 18,
  }) => _font(
    fontSize: fontSize,
    fontWeight: FontWeight.w700,
    color: color,
    letterSpacing: -0.2,
    height: 1.3,
  );

  /// Card title: 15–16 logical px, weight 600
  static TextStyle cardTitle({
    Color color = AbashyakaColors.inkBlack,
    double fontSize = 15,
  }) => _font(
    fontSize: fontSize,
    fontWeight: FontWeight.w600,
    color: color,
    letterSpacing: -0.1,
    height: 1.35,
  );

  /// Body large: 15–16 logical px, weight 400
  static TextStyle bodyLarge({
    Color color = AbashyakaColors.slateCharcoal,
    double fontSize = 15,
  }) => _font(
    fontSize: fontSize,
    fontWeight: FontWeight.w400,
    color: color,
    height: 1.45,
  );

  /// Body medium: 13–14 logical px, weight 400 (never washed out)
  static TextStyle bodyMedium({
    Color color = AbashyakaColors.secondaryText,
    double fontSize = 13.5,
  }) => _font(
    fontSize: fontSize,
    fontWeight: FontWeight.w400,
    color: color,
    height: 1.4,
  );

  /// Supporting / Caption text: 11–13 logical px, weight 500
  static TextStyle supportingText({
    Color color = AbashyakaColors.secondaryText,
    double? fontSize,
  }) => _font(
    fontSize: fontSize ?? 12,
    fontWeight: FontWeight.w500,
    color: color,
    height: 1.35,
    letterSpacing: 0.1,
  );

  /// Category labels: 11–12 logical px, weight 600
  static TextStyle categoryLabel({
    Color color = AbashyakaColors.inkBlack,
    double fontSize = 11.5,
  }) => _font(
    fontSize: fontSize,
    fontWeight: FontWeight.w600,
    color: color,
    letterSpacing: 0.0,
    height: 1.25,
  );

  /// Button text: 15–16 logical px, weight 700
  static TextStyle buttonText({
    Color color = AbashyakaColors.pureWhite,
    double fontSize = 15,
  }) => _font(
    fontSize: fontSize,
    fontWeight: FontWeight.w700,
    color: color,
    letterSpacing: 0.3,
    height: 1.2,
  );

  /// Rating text: 13–14 logical px, weight 700
  static TextStyle ratingText({
    Color color = AbashyakaColors.ratingText,
    double fontSize = 13,
  }) => _font(
    fontSize: fontSize,
    fontWeight: FontWeight.w700,
    color: color,
    height: 1.2,
  );

  /// Odia script typography
  static TextStyle odiaScript({
    Color color = AbashyakaColors.signatureTeal,
    double fontSize = 14,
    FontWeight fontWeight = FontWeight.w700,
  }) => TextStyle(
    fontFamily: 'sans-serif',
    locale: const Locale('or'),
    fontSize: fontSize,
    fontWeight: fontWeight,
    color: color,
  );
}
