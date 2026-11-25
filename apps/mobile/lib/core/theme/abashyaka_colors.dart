import 'package:flutter/material.dart';

/// Centralized official color tokens for Abashyaka Customer Brand Design System V2.0.
///
/// Design Language:
/// **Metallic Teal Abstract Fluid Wave + Pearl White Glossy UI**
/// Core 6 Public-Facing Brand Palette & 45/25/15/8/4/3 visual distribution ratio.
abstract final class AbashyakaColors {
  // -------------------------------------------------------------
  // Core 6 Brand Colours (Authoritative Recommendation)
  // -------------------------------------------------------------
  static const Color signatureTeal = Color(0xFF00545B);
  static const Color metallicTeal = Color(0xFF007D80);
  static const Color luminousAqua = Color(0xFF00B3AE);
  static const Color metallicGold = Color(0xFFF4B942);
  static const Color pearlWhite = Color(0xFFF5FAFA);
  static const Color pureWhite = Color(0xFFFFFFFF);

  // -------------------------------------------------------------
  // Backward-Compatible Brand Aliases & Gradient Steps
  // -------------------------------------------------------------
  static const Color darkOceanTeal = Color(0xFF003F46);
  static const Color deepMetallicTeal = signatureTeal;
  static const Color metallicTealDark = signatureTeal;
  static const Color brightTeal = luminousAqua;
  static const Color aquaGlow = Color(0xFF55D6CD);
  static const Color metallicTealGlow = aquaGlow;
  static const Color lightAqua = Color(0xFFB8EFEB);
  static const Color metallicTealLight = lightAqua;

  // Odisha / Accent Highlights
  static const Color saffronOrange = metallicGold;
  static const Color saffronGlow = metallicGold;

  // -------------------------------------------------------------
  // Surfaces, Borders & Neutrals
  // -------------------------------------------------------------
  static const Color luminousWhite = Color(0xFFFAFDFE);
  static const Color iceAquaWhite = Color(0xFFEAF7F7);
  static const Color aquaSilverBorder = Color(0xFFDCEBED);
  static const Color silverGlass = Color(0xFFDCEBED);
  static const Color softGrey = Color(0xFFE8EFF1);
  static const Color inkBlack = Color(0xFF102B32);
  static const Color slateCharcoal = Color(0xFF22383E);
  static const Color secondaryText = Color(0xFF4A626A);
  static const Color mutedText = Color(0xFF526971);

  // -------------------------------------------------------------
  // Functional Colours
  // -------------------------------------------------------------
  static const Color success = Color(0xFF16A34A);
  static const Color error = Color(0xFFDC3545);
  static const Color warning = Color(0xFFF59E0B);
  static const Color information = Color(0xFF0369A1);
  static const Color ratingStar = metallicGold;
  static const Color ratingText = Color(0xFF92400E);
  static const Color favourite = Color(0xFFEF476F);

  // -------------------------------------------------------------
  // Surface Translucent Highlights for Glass Effects
  // -------------------------------------------------------------
  static const Color glassHighlight = Color(0x66FFFFFF);
  static const Color glassBorder = Color(0x33DCEBED);
  static const Color tealTint = Color(0x14007D80);
  static const Color darkTealTint = Color(0x2800545B);
}
