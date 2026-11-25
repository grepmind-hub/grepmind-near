import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'abashyaka_colors.dart';

/// Centralized Typography system for Abashyaka using Plus Jakarta Sans
/// with fallback to sans-serif and Odia script support.
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

  /// Brand wordmark: 36–40 logical px, weight 800
  static TextStyle brandWordmark({
    Color color = AbashyakaColors.deepMetallicTeal,
    double fontSize = 36,
  }) => _font(
    fontSize: fontSize,
    fontWeight: FontWeight.w800,
    color: color,
    letterSpacing: -0.8,
  );

  /// Display heading: 28–32 logical px, weight 800
  static TextStyle displayHeading({
    Color color = AbashyakaColors.inkBlack,
    double fontSize = 28,
  }) => _font(
    fontSize: fontSize,
    fontWeight: FontWeight.w800,
    color: color,
    height: 1.25,
    letterSpacing: -0.5,
  );

  /// Page title: 24 logical px, weight 700
  static TextStyle pageTitle({Color color = AbashyakaColors.inkBlack}) => _font(
    fontSize: 24,
    fontWeight: FontWeight.w700,
    color: color,
    letterSpacing: -0.3,
  );

  /// Section title: 20 logical px, weight 700
  static TextStyle sectionTitle({Color color = AbashyakaColors.inkBlack}) =>
      _font(
        fontSize: 20,
        fontWeight: FontWeight.w700,
        color: color,
        letterSpacing: -0.2,
      );

  /// Card title: 16 logical px, weight 600
  static TextStyle cardTitle({Color color = AbashyakaColors.inkBlack}) =>
      _font(fontSize: 16, fontWeight: FontWeight.w600, color: color);

  /// Body large: 16 logical px
  static TextStyle bodyLarge({
    Color color = AbashyakaColors.inkBlack,
    double fontSize = 16,
  }) => _font(
    fontSize: fontSize,
    fontWeight: FontWeight.w400,
    color: color,
    height: 1.4,
  );

  /// Body medium: 14 logical px
  static TextStyle bodyMedium({
    Color color = AbashyakaColors.secondaryText,
    double fontSize = 14,
  }) => _font(
    fontSize: fontSize,
    fontWeight: FontWeight.w400,
    color: color,
    height: 1.4,
  );

  /// Supporting text: 12–14 logical px
  static TextStyle supportingText({
    Color color = AbashyakaColors.secondaryText,
    double? fontSize,
  }) => _font(
    fontSize: fontSize ?? 13,
    fontWeight: FontWeight.w400,
    color: color,
    height: 1.35,
  );

  /// Category labels: 11–12 logical px, weight 600
  static TextStyle categoryLabel({Color color = AbashyakaColors.inkBlack}) =>
      _font(fontSize: 12, fontWeight: FontWeight.w600, color: color);

  /// Button text: 16 logical px, weight 700
  static TextStyle buttonText({Color color = AbashyakaColors.pureWhite}) =>
      _font(
        fontSize: 16,
        fontWeight: FontWeight.w700,
        color: color,
        letterSpacing: 0.2,
      );

  /// Odia script typography
  static TextStyle odiaScript({
    Color color = AbashyakaColors.deepMetallicTeal,
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
