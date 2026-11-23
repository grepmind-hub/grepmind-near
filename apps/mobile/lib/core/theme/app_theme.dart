import 'package:flutter/material.dart';

/// Grepmind Near "Local Luxe" design system — 2026 Material Design 3.
///
/// Palette inspired by regional trust, Odisha heritage, and quick commerce clarity:
/// Forest Green (#123D36), Mint (#16A085), Canvas (#F5F6F2), Amber (#F4B544), Coral (#E66B55).
class AppTheme {
  AppTheme._();

  // ---------- 2027 Palette: Action Green (#087F0D) & Vibrant Green (#09A110) ----------
  static const Color vibrantGreen = Color(0xFF09A110);
  static const Color actionGreen = Color(0xFF087F0D);
  static const Color deepEmerald = Color(0xFF064D3A);
  static const Color freshLeaf = Color(0xFF78CE65);
  static const Color softLime = Color(0xFFDDF5A6);
  static const Color lightMint = Color(0xFFE4F7E3);
  static const Color pearlGreen = Color(0xFFF3FAF0);
  static const Color signatureOrange = Color(0xFFFF8A00);
  static const Color warmPeach = Color(0xFFFFE4D1);
  static const Color skyBlue = Color(0xFFDFEEFF);
  static const Color pureWhite = Color(0xFFFFFFFF);
  static const Color carbon = Color(0xFF172820);
  static const Color mutedSlate = Color(0xFF64748B);

  // Core & Semantic Aliases
  static const Color signatureEmerald = actionGreen;
  static const Color deepForest = deepEmerald;
  static const Color freshMint = lightMint;
  static const Color signatureAmber = signatureOrange;
  static const Color warmPorcelain = pearlGreen;
  static const Color emerald = actionGreen;
  static const Color emeraldDark = deepEmerald;
  static const Color forest = deepEmerald;
  static const Color forestDark = Color(0xFF04382A);
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
  static const Color plumDark = Color(0xFF04382A);
  static const Color plumLight = lightMint;
  static const Color plumBorder = Color(0xFFE2E8F0);
  static const Color premiumGreen = vibrantGreen;
  static const Color premiumGreenDark = actionGreen;
  static const Color premiumGreenLight = lightMint;

  // ---------- Rider Amber Quick-Commerce Tokens (#F4B544) ----------
  static const Color riderAmber = signatureOrange;
  static const Color riderAmberDark = Color(0xFFD97706);
  static const Color riderAmberDeep = Color(0xFF92400E);
  static const Color riderAmberLight = Color(0xFFFFFBEB);
  static const Color riderAmberContainer = Color(0xFFFEF3C7);
  static const Color riderAmberBorder = Color(0xFFFDE68A);

  // ---------- Brand Surfaces & Layout ----------
  static const Color brandMint = lightMint;
  static const Color brandCanvas = pureWhite;
  static const Color brandBorder = Color(0xFFE2E8F0);
  static const Color brandText = carbon;
  static const Color brandTextMuted = mutedSlate;

  // ---------- Core Color tokens ----------
  static const Color primary = actionGreen;
  static const Color primaryContainer = lightMint;
  static const Color secondary = signatureOrange;
  static const Color secondaryContainer = warmPeach;
  static const Color background = pureWhite;
  static const Color surface = pureWhite;
  static const Color surfaceVariant = pearlGreen;
  static const Color mainText = carbon;
  static const Color textPrimary = mainText;
  static const Color secondaryText = mutedSlate;
  static const Color textSecondary = secondaryText;
  static const Color hintText = Color(0xFF94A3B8);
  static const Color textMuted = hintText;
  static const Color border = Color(0xFFE2E8F0);
  static const Color divider = Color(0xFFF1F5F9);
  static const Color success = actionGreen;
  static const Color successContainer = lightMint;
  static const Color warning = amber;
  static const Color warningContainer = amberLight;
  static const Color error = coral;
  static const Color errorContainer = coralLight;
  static const Color onPrimary = Color(0xFFFFFFFF);
  static const Color onSecondary = Color(0xFFFFFFFF);
  static const Color onSurface = Color(0xFF172033);
  static const double cardRadius = 20.0;
  static const double buttonRadius = 14.0;

  // ---------- Typography ----------
  static TextTheme _textTheme(BuildContext context) {
    return Theme.of(context).textTheme
        .apply(fontFamily: 'sans-serif')
        .copyWith(
          displayLarge: const TextStyle(
            fontFamily: 'sans-serif',
            fontSize: 32,
            fontWeight: FontWeight.w700,
            color: mainText,
            letterSpacing: -0.5,
          ),
          displayMedium: const TextStyle(
            fontFamily: 'sans-serif',
            fontSize: 28,
            fontWeight: FontWeight.w700,
            color: mainText,
            letterSpacing: -0.4,
          ),
          headlineLarge: const TextStyle(
            fontFamily: 'sans-serif',
            fontSize: 24,
            fontWeight: FontWeight.w700,
            color: mainText,
            letterSpacing: -0.2,
          ),
          headlineMedium: const TextStyle(
            fontFamily: 'sans-serif',
            fontSize: 20,
            fontWeight: FontWeight.w600,
            color: mainText,
          ),
          headlineSmall: const TextStyle(
            fontFamily: 'sans-serif',
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: mainText,
          ),
          titleLarge: const TextStyle(
            fontFamily: 'sans-serif',
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: mainText,
          ),
          titleMedium: const TextStyle(
            fontFamily: 'sans-serif',
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: mainText,
          ),
          bodyLarge: const TextStyle(
            fontFamily: 'sans-serif',
            fontSize: 16,
            fontWeight: FontWeight.w400,
            color: mainText,
            height: 1.5,
          ),
          bodyMedium: const TextStyle(
            fontFamily: 'sans-serif',
            fontSize: 14,
            fontWeight: FontWeight.w400,
            color: mainText,
            height: 1.5,
          ),
          bodySmall: const TextStyle(
            fontFamily: 'sans-serif',
            fontSize: 12,
            fontWeight: FontWeight.w400,
            color: secondaryText,
            height: 1.4,
          ),
          labelLarge: const TextStyle(
            fontFamily: 'sans-serif',
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: mainText,
          ),
          labelMedium: const TextStyle(
            fontFamily: 'sans-serif',
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: secondaryText,
          ),
          labelSmall: const TextStyle(
            fontFamily: 'sans-serif',
            fontSize: 11,
            fontWeight: FontWeight.w500,
            color: hintText,
          ),
        );
  }

  static ThemeData lightTheme(BuildContext context) {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: background,
      colorScheme: const ColorScheme.light(
        primary: primary,
        primaryContainer: primaryContainer,
        secondary: secondary,
        onSecondary: onSecondary,
        secondaryContainer: secondaryContainer,
        onSurface: onSurface,
        surfaceContainerHighest: surfaceVariant,
        outline: border,
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
        shadowColor: Colors.black.withValues(alpha: 0.04),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: border),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: secondary, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: error),
        ),
        hintStyle: const TextStyle(color: hintText, fontSize: 14),
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
            borderRadius: BorderRadius.circular(28),
          ),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, letterSpacing: 0.1),
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
            borderRadius: BorderRadius.circular(28),
          ),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, letterSpacing: 0.1),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: primary,
          minimumSize: const Size(double.infinity, 50),
          padding: const EdgeInsets.symmetric(vertical: 14),
          side: const BorderSide(color: border, width: 1.5),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(28),
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
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        scrolledUnderElevation: 0,
        iconTheme: IconThemeData(color: mainText),
        titleTextStyle: TextStyle(
          color: mainText,
          fontSize: 18,
          fontWeight: FontWeight.w700,
          fontFamily: 'sans-serif',
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
}

/// Base spacing unit (4 px).
const double kGridUnit = 4.0;
const double kScreenPadding = 20.0;
const double kCardRadius = 14.0;
const double kInputHeight = 52.0;
const double kMinTouchTarget = 48.0;
