import 'package:flutter/material.dart';

/// Centralized official color tokens for Abashyaka Design System V1.0.
///
/// Design Language:
/// **Metallic Teal Abstract Fluid Wave + Pearl White Glossy UI**
abstract final class AbashyakaColors {
  // Brand Colours
  static const Color darkOceanTeal = Color(0xFF003F46);
  static const Color deepMetallicTeal = Color(0xFF00545B);
  static const Color metallicTealDark = deepMetallicTeal;
  static const Color metallicTeal = Color(0xFF008C95);
  static const Color brightTeal = Color(0xFF00B3AE);
  static const Color aquaGlow = Color(0xFF55D6CD);
  static const Color metallicTealGlow = aquaGlow;
  static const Color lightAqua = Color(0xFFB8EFEB);
  static const Color metallicTealLight = lightAqua;

  // Odisha / Accent Highlights
  static const Color saffronOrange = Color(0xFFFF8A00);
  static const Color saffronGlow = Color(0xFFFF8A00);

  // White and Neutral Colours
  static const Color pureWhite = Color(0xFFFFFFFF);
  static const Color pearlWhite = Color(0xFFF3F7F8);
  static const Color luminousWhite = Color(0xFFFAFDFE);
  static const Color iceAquaWhite = Color(0xFFEAF7F7);
  static const Color silverGlass = Color(0xFFDCE8E8);
  static const Color softGrey = Color(0xFFE8EFF1);
  static const Color inkBlack = Color(0xFF102A33);
  static const Color secondaryText = Color(0xFF607680);

  // Functional Colours
  static const Color success = Color(0xFF16A34A);
  static const Color error = Color(0xFFDC3545);
  static const Color warning = Color(0xFFF59E0B);
  static const Color information = Color(0xFF2563EB);
  static const Color ratingStar = Color(0xFFFFB020);
  static const Color favourite = Color(0xFFEF476F);

  // Surface Translucent Highlights for Glass Effects
  static const Color glassHighlight = Color(0x66FFFFFF);
  static const Color glassBorder = Color(0x33DCE8E8);
  static const Color tealTint = Color(0x14008C95);
  static const Color darkTealTint = Color(0x2800545B);
}
