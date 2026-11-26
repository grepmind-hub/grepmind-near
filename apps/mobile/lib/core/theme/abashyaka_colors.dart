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
  static const Color champagneHighlight = Color(0xFFF4F5C9);
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

  static const Color primaryText = Color(0xFF102B32);
  static const Color brandText = signatureTeal;
  static const Color secondaryText = Color(0xFF36545C);
  static const Color mutedText = Color(0xFF526971);
  static const Color placeholderText = Color(0xFF607D85);
  static const Color disabledText = Color(0xFF9AAEB3);
  static const Color inverseText = pureWhite;
  static const Color linkText = Color(0xFF006E75);
  static const Color premiumObsidian = primaryText;
  static const Color inkBlack = primaryText;
  static const Color graphiteCharcoal = secondaryText;
  static const Color slateCharcoal = secondaryText;

  // -------------------------------------------------------------
  // Functional Colours
  // -------------------------------------------------------------
  static const Color success = Color(0xFF047857);
  static const Color successSurface = Color(0xFFD1FAE5);
  static const Color error = Color(0xFFBE123C);
  static const Color errorSurface = Color(0xFFFFE4E6);
  static const Color warning = Color(0xFF92400E);
  static const Color warningSurface = Color(0xFFFFF4D6);
  static const Color information = Color(0xFF0369A1);
  static const Color informationSurface = Color(0xFFE0F2FE);
  static const Color verified = linkText;
  static const Color verifiedSurface = Color(0xFFE0F5F2);
  static const Color unavailable = mutedText;
  static const Color unavailableSurface = Color(0xFFEDF2F3);
  static const Color offer = Color(0xFFC2410C);
  static const Color offerSurface = Color(0xFFFFF0E0);
  static const Color ratingStar = Color(0xFFF59E0B);
  static const Color ratingText = warning;
  static const Color favourite = Color(0xFFEF476F);

  static const Color customer = Color(0xFF166534);
  static const Color customerSurface = Color(0xFFE8F8EE);
  static const Color merchant = warning;
  static const Color merchantSurface = Color(0xFFFFF3DC);
  static const Color rider = information;
  static const Color riderSurface = Color(0xFFE8F5FD);
  static const Color admin = Color(0xFF6D28D9);
  static const Color adminSurface = Color(0xFFF3EBFC);

  // -------------------------------------------------------------
  // Surface Translucent Highlights for Glass Effects
  // -------------------------------------------------------------
  static const Color glassHighlight = Color(0x66FFFFFF);
  static const Color glassBorder = Color(0x33DCEBED);
  static const Color tealTint = Color(0x14007D80);
  static const Color darkTealTint = Color(0x2800545B);
}
