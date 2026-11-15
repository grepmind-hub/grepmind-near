import 'package:flutter/material.dart';

/// Grepmind Near "Local Luxe" design system — 2026 Material Design 3.
///
/// Palette inspired by regional trust, Odisha heritage, and quick commerce clarity:
/// Forest Green (#123D36), Mint (#16A085), Canvas (#F5F6F2), Amber (#F4B544), Coral (#E66B55).
class AppTheme {
  AppTheme._();

  // ---------- GrepMind Local Luxe Tokens ----------
  static const Color forest = Color(0xFF123D36);
  static const Color forestDark = Color(0xFF0C2B26);
  static const Color mint = Color(0xFF16A085);
  static const Color mintLight = Color(0xFFE8F6F3);
  static const Color canvas = Color(0xFFF5F6F2);
  static const Color amber = Color(0xFFF4B544);
  static const Color amberLight = Color(0xFFFEF7E8);
  static const Color coral = Color(0xFFE66B55);
  static const Color coralLight = Color(0xFFFDF0ED);
  static const Color coralBorder = Color(0xFFFDC4BA);
  static const Color coralDark = Color(0xFFC84E3A);
  static const Color merchantCoral = Color(0xFFE66B55);
  static const Color merchantCoralLight = Color(0xFFFFF1EE);
  static const Color merchantCoralContainer = Color(0xFFFFF1EE);
  static const Color merchantCoralBorder = Color(0xFFFDC4BA);

  // ---------- Rider Amber Quick-Commerce Tokens (#F4B544) ----------
  static const Color riderAmber = Color(0xFFF4B544);
  static const Color riderAmberDark = Color(0xFFD97706);
  static const Color riderAmberDeep = Color(0xFF92400E);
  static const Color riderAmberLight = Color(0xFFFFFBEB);
  static const Color riderAmberContainer = Color(0xFFFEF3C7);
  static const Color riderAmberBorder = Color(0xFFFDE68A);

  // ---------- 2026 Mint + Emerald Quick-Commerce Tokens ----------
  static const Color emerald = Color(0xFF059669);
  static const Color emeraldDark = Color(0xFF047857);
  static const Color brandMint = Color(0xFFB8F2DC);
  static const Color brandCanvas = Color(0xFFF8FAF9);
  static const Color brandBorder = Color(0xFFE1EBE5);
  static const Color brandText = Color(0xFF17352C);
  static const Color brandTextMuted = Color(0xFF64748B);

  // ---------- Core Color tokens ----------
  static const Color primary = forest;
  static const Color primaryContainer = mintLight;
  static const Color secondary = mint;
  static const Color secondaryContainer = Color(0xFFE0F2F1);
  static const Color background = canvas;
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceVariant = Color(0xFFEBEFEA);
  static const Color mainText = Color(0xFF172033);
  static const Color textPrimary = mainText;
  static const Color secondaryText = Color(0xFF667085);
  static const Color textSecondary = secondaryText;
  static const Color hintText = Color(0xFF9AA5B1);
  static const Color textMuted = hintText;
  static const Color border = Color(0xFFE4E7EC);
  static const Color divider = Color(0xFFF2F4F7);
  static const Color success = mint;
  static const Color successContainer = mintLight;
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
          backgroundColor: emerald,
          foregroundColor: onPrimary,
          elevation: 0,
          minimumSize: const Size(double.infinity, 50),
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: emerald,
          foregroundColor: onPrimary,
          elevation: 0,
          minimumSize: const Size(double.infinity, 50),
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: primary,
          minimumSize: const Size(double.infinity, 50),
          padding: const EdgeInsets.symmetric(vertical: 14),
          side: const BorderSide(color: border),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
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
        elevation: 4,
        type: BottomNavigationBarType.fixed,
        selectedItemColor: emerald,
        unselectedItemColor: secondaryText,
        showSelectedLabels: true,
        showUnselectedLabels: true,
        selectedLabelStyle: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
        unselectedLabelStyle: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w400,
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
