import 'package:flutter/material.dart';

import 'abashyaka_colors.dart';

/// Adaptive color palette for Light (Pearl White V2.0) and Dark (Midnight Slate & Aqua) themes.
///
/// Access via `context.abashyaka` on any `BuildContext`.
@immutable
class AbashyakaPalette extends ThemeExtension<AbashyakaPalette> {
  const AbashyakaPalette({
    required this.canvas,
    required this.card,
    required this.cardElevated,
    required this.border,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.accent,
    required this.accentSoft,
    required this.accentSurface,
    required this.navBackground,
    required this.navActivePill,
    required this.navActiveText,
    required this.isDark,
  });

  final Color canvas;
  final Color card;
  final Color cardElevated;
  final Color border;
  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;
  final Color accent;
  final Color accentSoft;
  final Color accentSurface;
  final Color navBackground;
  final Color navActivePill;
  final Color navActiveText;
  final bool isDark;

  static const light = AbashyakaPalette(
    canvas: AbashyakaColors.pearlWhite,
    card: AbashyakaColors.pureWhite,
    cardElevated: AbashyakaColors.luminousWhite,
    border: AbashyakaColors.aquaSilverBorder,
    textPrimary: AbashyakaColors.primaryText,
    textSecondary: AbashyakaColors.secondaryText,
    textMuted: AbashyakaColors.mutedText,
    accent: AbashyakaColors.metallicTeal,
    accentSoft: AbashyakaColors.luminousAqua,
    accentSurface: AbashyakaColors.iceAquaWhite,
    navBackground: AbashyakaColors.pureWhite,
    navActivePill: AbashyakaColors.iceAquaWhite,
    navActiveText: AbashyakaColors.metallicTeal,
    isDark: false,
  );

  /// Option 2: Midnight Slate & Luminous Aqua Dark Mode
  static const dark = AbashyakaPalette(
    canvas: Color(0xFF0B1320),
    card: Color(0xFF152232),
    cardElevated: Color(0xFF1B2B3F),
    border: Color(0xFF243447),
    textPrimary: Color(0xFFF8FAFC),
    textSecondary: Color(0xFFCBD5E1),
    textMuted: Color(0xFF94A3B8),
    accent: Color(0xFF00B3AE),
    accentSoft: Color(0xFF55D6CD),
    accentSurface: Color(0xFF12323B),
    navBackground: Color(0xFF152232),
    navActivePill: Color(0xFF163B45),
    navActiveText: Color(0xFF55D6CD),
    isDark: true,
  );

  @override
  AbashyakaPalette copyWith({
    Color? canvas,
    Color? card,
    Color? cardElevated,
    Color? border,
    Color? textPrimary,
    Color? textSecondary,
    Color? textMuted,
    Color? accent,
    Color? accentSoft,
    Color? accentSurface,
    Color? navBackground,
    Color? navActivePill,
    Color? navActiveText,
    bool? isDark,
  }) {
    return AbashyakaPalette(
      canvas: canvas ?? this.canvas,
      card: card ?? this.card,
      cardElevated: cardElevated ?? this.cardElevated,
      border: border ?? this.border,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textMuted: textMuted ?? this.textMuted,
      accent: accent ?? this.accent,
      accentSoft: accentSoft ?? this.accentSoft,
      accentSurface: accentSurface ?? this.accentSurface,
      navBackground: navBackground ?? this.navBackground,
      navActivePill: navActivePill ?? this.navActivePill,
      navActiveText: navActiveText ?? this.navActiveText,
      isDark: isDark ?? this.isDark,
    );
  }

  @override
  AbashyakaPalette lerp(ThemeExtension<AbashyakaPalette>? other, double t) {
    if (other is! AbashyakaPalette) return this;
    return AbashyakaPalette(
      canvas: Color.lerp(canvas, other.canvas, t)!,
      card: Color.lerp(card, other.card, t)!,
      cardElevated: Color.lerp(cardElevated, other.cardElevated, t)!,
      border: Color.lerp(border, other.border, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textMuted: Color.lerp(textMuted, other.textMuted, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      accentSoft: Color.lerp(accentSoft, other.accentSoft, t)!,
      accentSurface: Color.lerp(accentSurface, other.accentSurface, t)!,
      navBackground: Color.lerp(navBackground, other.navBackground, t)!,
      navActivePill: Color.lerp(navActivePill, other.navActivePill, t)!,
      navActiveText: Color.lerp(navActiveText, other.navActiveText, t)!,
      isDark: t < 0.5 ? isDark : other.isDark,
    );
  }
}

extension AbashyakaThemeContext on BuildContext {
  AbashyakaPalette get abashyaka {
    final ext = Theme.of(this).extension<AbashyakaPalette>();
    if (ext != null) return ext;
    return Theme.of(this).brightness == Brightness.dark
        ? AbashyakaPalette.dark
        : AbashyakaPalette.light;
  }
}
