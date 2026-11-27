import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import 'abashyaka_colors.dart';
import 'abashyaka_palette.dart';
import 'abashyaka_tokens.dart';
import 'abashyaka_typography.dart';

export 'abashyaka_colors.dart';
export 'abashyaka_gradients.dart';
export 'abashyaka_palette.dart';
export 'abashyaka_tokens.dart';
export 'abashyaka_typography.dart';

/// Abashyaka Premium Theme — Metallic Teal & Pearl White Glossy UI.
class AppTheme {
  AppTheme._();

  // Official Metallic Teal Palette
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

  // Core & Semantic Aliases
  static const Color signatureEmerald = actionGreen;
  static const Color deepForest = deepEmerald;
  static const Color freshMint = lightMint;
  static const Color signatureAmber = signatureOrange;
  static const Color warmPorcelain = pearlGreen;
  static const Color emerald = actionGreen;
  static const Color emeraldDark = deepEmerald;
  static const Color forest = deepEmerald;
  static const Color forestDark = AbashyakaColors.darkOceanTeal;
  static const Color mint = actionGreen;
  static const Color mintLight = lightMint;
  static const Color canvas = pureWhite;
  static const Color amber = signatureOrange;
  static const Color amberLight = Color(0xFFFFF3E0);
  static const Color coral = signatureOrange;
  static const Color coralDark = Color(0xFFEA580C);
  static const Color coralLight = Color(0xFFFFF7ED);
  static const Color coralBorder = Color(0xFFFED7AA);
  static const Color merchantCoral = signatureOrange;
  static const Color merchantCoralLight = Color(0xFFFFF7ED);
  static const Color merchantCoralContainer = Color(0xFFFFF7ED);
  static const Color merchantCoralBorder = Color(0xFFFED7AA);
  static const Color plum = deepEmerald;
  static const Color plumDark = AbashyakaColors.darkOceanTeal;
  static const Color plumLight = lightMint;
  static const Color plumBorder = Color(0xFFE2E8F0);
  static const Color premiumGreen = vibrantGreen;
  static const Color premiumGreenDark = actionGreen;
  static const Color premiumGreenLight = lightMint;

  // Rider Amber Quick-Commerce Tokens
  static const Color riderAmber = signatureOrange;
  static const Color riderAmberDark = Color(0xFFD97706);
  static const Color riderAmberDeep = Color(0xFF92400E);
  static const Color riderAmberLight = Color(0xFFFFFBEB);
  static const Color riderAmberContainer = Color(0xFFFEF3C7);
  static const Color riderAmberBorder = Color(0xFFFDE68A);

  // Brand Surfaces & Layout
  static const Color brandMint = lightMint;
  static const Color brandCanvas = pearlGreen;
  static const Color brandBorder = AbashyakaColors.silverGlass;
  static const Color brandText = carbon;
  static const Color brandTextMuted = mutedSlate;

  // Core Color tokens
  static const Color primary = actionGreen;
  static const Color primaryContainer = lightMint;
  static const Color secondary = vibrantGreen;
  static const Color secondaryContainer = warmPeach;
  static const Color background = pearlGreen;
  static const Color surface = pureWhite;
  static const Color surfaceVariant = pearlGreen;
  static const Color mainText = carbon;
  static const Color textPrimary = mainText;
  static const Color secondaryText = mutedSlate;
  static const Color textSecondary = secondaryText;
  static const Color hintText = AbashyakaColors.placeholderText;
  static const Color textMuted = AbashyakaColors.mutedText;
  static const Color border = AbashyakaColors.silverGlass;
  static const Color divider = Color(0xFFF1F5F9);
  static const Color success = AbashyakaColors.success;
  static const Color successContainer = AbashyakaColors.successSurface;
  static const Color warning = AbashyakaColors.warning;
  static const Color warningContainer = AbashyakaColors.warningSurface;
  static const Color error = AbashyakaColors.error;
  static const Color errorContainer = AbashyakaColors.errorSurface;
  static const Color onPrimary = Color(0xFFFFFFFF);
  static const Color onSecondary = AbashyakaColors.primaryText;
  static const Color onSurface = AbashyakaColors.primaryText;
  static const double cardRadius = AbashyakaRadius.categoryCard;
  static const double buttonRadius = AbashyakaRadius.button;

  // Typography
  static TextTheme _textTheme(BuildContext context) {
    final baseTheme = Theme.of(context).textTheme;
    TextTheme jakartaBase;
    try {
      jakartaBase = GoogleFonts.plusJakartaSansTextTheme(baseTheme);
    } catch (_) {
      jakartaBase = baseTheme.apply(fontFamily: 'sans-serif');
    }
    return jakartaBase.copyWith(
          displayLarge: AbashyakaTypography.displayHeading(fontSize: 32),
          displayMedium: AbashyakaTypography.displayHeading(),
          headlineLarge: AbashyakaTypography.pageTitle(),
          headlineMedium: AbashyakaTypography.sectionTitle(),
          headlineSmall: AbashyakaTypography.cardTitle(fontSize: 18),
          titleLarge: AbashyakaTypography.cardTitle(),
          titleMedium: AbashyakaTypography.cardTitle(fontSize: 14),
          bodyLarge: AbashyakaTypography.bodyLarge(),
          bodyMedium: AbashyakaTypography.bodyMedium(),
          bodySmall: AbashyakaTypography.supportingText(),
        );
  }

  static ThemeData lightTheme(BuildContext context) {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      extensions: const [AbashyakaPalette.light],
      scaffoldBackgroundColor: background,
      colorScheme: const ColorScheme.light(
        primary: primary,
        onPrimary: AbashyakaColors.inverseText,
        primaryContainer: primaryContainer,
        secondary: secondary,
        onSecondary: onSecondary,
        secondaryContainer: secondaryContainer,
        surface: surface,
        onSurface: onSurface,
        onSurfaceVariant: AbashyakaColors.secondaryText,
        surfaceContainerHighest: surfaceVariant,
        outline: border,
        error: error,
        errorContainer: errorContainer,
      ),
      textTheme: _textTheme(context),
      primaryColor: primary,
      dividerTheme: const DividerThemeData(
        color: border,
        space: 1,
        thickness: 1,
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        shadowColor: const Color(0x0C003F46),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(cardRadius),
          side: const BorderSide(color: border),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 20,
          vertical: 16,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(buttonRadius),
          borderSide: const BorderSide(color: border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(buttonRadius),
          borderSide: const BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(buttonRadius),
          borderSide: const BorderSide(color: primary, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(buttonRadius),
          borderSide: const BorderSide(color: error),
        ),
        hintStyle: const TextStyle(
          color: AbashyakaColors.mutedText,
          fontSize: 14,
        ),
        labelStyle: const TextStyle(
          color: secondaryText,
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: actionGreen,
          foregroundColor: onPrimary,
          elevation: 0,
          minimumSize: const Size(double.infinity, 54),
          padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 24),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(buttonRadius),
          ),
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.1,
          ),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: actionGreen,
          foregroundColor: onPrimary,
          elevation: 0,
          minimumSize: const Size(double.infinity, 54),
          padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 24),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(buttonRadius),
          ),
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.1,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: primary,
          minimumSize: const Size(double.infinity, 50),
          padding: const EdgeInsets.symmetric(vertical: 14),
          side: const BorderSide(color: border, width: 1.5),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(buttonRadius),
          ),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: primary,
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        ),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: surface,
        elevation: 6,
        type: BottomNavigationBarType.fixed,
        selectedItemColor: actionGreen,
        unselectedItemColor: secondaryText,
        showSelectedLabels: true,
        showUnselectedLabels: true,
        selectedLabelStyle: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
        unselectedLabelStyle: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        scrolledUnderElevation: 0,
        systemOverlayStyle: SystemUiOverlayStyle.dark,
        iconTheme: const IconThemeData(color: mainText),
        titleTextStyle: AbashyakaTypography.pageTitle(
          color: mainText,
          fontSize: 18,
        ),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: secondary,
        foregroundColor: onSecondary,
        elevation: 4,
        shape: CircleBorder(),
      ),
    );
  }

  /// Option 2: Midnight Slate & Luminous Aqua Dark Mode theme.
  static ThemeData darkTheme(BuildContext context) {
    const p = AbashyakaPalette.dark;
    final baseText = _textTheme(context).apply(
      bodyColor: p.textPrimary,
      displayColor: p.textPrimary,
    );
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      extensions: const [AbashyakaPalette.dark],
      scaffoldBackgroundColor: p.canvas,
      colorScheme: ColorScheme.dark(
        primary: p.accent,
        onPrimary: const Color(0xFF071A1E),
        primaryContainer: p.accentSurface,
        secondary: p.accentSoft,
        onSecondary: const Color(0xFF071A1E),
        secondaryContainer: p.cardElevated,
        surface: p.card,
        onSurface: p.textPrimary,
        onSurfaceVariant: p.textSecondary,
        surfaceContainerHighest: p.cardElevated,
        outline: p.border,
        error: AbashyakaColors.error,
        errorContainer: const Color(0xFF4C0519),
      ),
      textTheme: baseText,
      primaryColor: p.accent,
      dividerTheme: DividerThemeData(
        color: p.border,
        space: 1,
        thickness: 1,
      ),
      cardTheme: CardThemeData(
        color: p.card,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(cardRadius),
          side: BorderSide(color: p.border),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: p.card,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 20,
          vertical: 16,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(buttonRadius),
          borderSide: BorderSide(color: p.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(buttonRadius),
          borderSide: BorderSide(color: p.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(buttonRadius),
          borderSide: BorderSide(color: p.accentSoft, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(buttonRadius),
          borderSide: const BorderSide(color: AbashyakaColors.error),
        ),
        hintStyle: TextStyle(color: p.textMuted, fontSize: 14),
        labelStyle: TextStyle(
          color: p.textSecondary,
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: p.accent,
          foregroundColor: const Color(0xFF071A1E),
          elevation: 0,
          minimumSize: const Size(double.infinity, 54),
          padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 24),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(buttonRadius),
          ),
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.1,
          ),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: p.accent,
          foregroundColor: const Color(0xFF071A1E),
          elevation: 0,
          minimumSize: const Size(double.infinity, 54),
          padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 24),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(buttonRadius),
          ),
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.1,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: p.accentSoft,
          minimumSize: const Size(double.infinity, 50),
          padding: const EdgeInsets.symmetric(vertical: 14),
          side: BorderSide(color: p.border, width: 1.5),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(buttonRadius),
          ),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: p.accentSoft,
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        ),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: p.navBackground,
        elevation: 6,
        type: BottomNavigationBarType.fixed,
        selectedItemColor: p.accentSoft,
        unselectedItemColor: p.textMuted,
        showSelectedLabels: true,
        showUnselectedLabels: true,
        selectedLabelStyle: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
        unselectedLabelStyle: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        scrolledUnderElevation: 0,
        systemOverlayStyle: SystemUiOverlayStyle.light,
        iconTheme: IconThemeData(color: p.textPrimary),
        titleTextStyle: AbashyakaTypography.pageTitle(
          color: p.textPrimary,
          fontSize: 18,
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: p.accent,
        foregroundColor: const Color(0xFF071A1E),
        elevation: 4,
        shape: const CircleBorder(),
      ),
    );
  }
}

/// Base spacing unit (4 px).
const double kGridUnit = 4.0;
const double kScreenPadding = 16.0;
const double kCardRadius = 18.0;
const double kInputHeight = 56.0;
const double kMinTouchTarget = 48.0;
