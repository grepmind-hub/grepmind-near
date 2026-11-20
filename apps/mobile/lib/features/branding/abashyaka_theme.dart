import 'package:flutter/material.dart';

/// Scoped branding for entry screens. Other workspaces keep their own theme.
abstract final class AbashyakaTheme {
  static const green = Color(0xFF0B6B4A);
  static const orange = Color(0xFFFF8A00);
  static const mint = Color(0xFFE8F5E9);
  static const warmWhite = Color(0xFFFFF9F2);
  static const darkGreen = Color(0xFF064D3A);
  static const text = Color(0xFF153D30);
  static const muted = Color(0xFF52675D);
  static const border = Color(0xFFD9E7DC);
  static const space = 4.0;
  static const pagePadding = 24.0;
  static const cardRadius = 24.0;
  static const controlRadius = 16.0;
  static const touchTarget = 48.0;
  static const elevation = 0.0;
  static const entrance = Duration(milliseconds: 500);
  static const transition = Duration(milliseconds: 220);
  static const logo = 'assets/abashyaka/app_icon_source.png';
  static const splashEmblem = 'assets/abashyaka/splash_emblem.png';
  static const splashLandscape = 'assets/abashyaka/splash_landscape.png';
  static const illustration = 'assets/abashyaka/onboarding_customer_hero.png';
  static const onboardingHero = 'assets/abashyaka/onboarding_customer_hero.png';

  static ThemeData theme(BuildContext context) {
    final base = Theme.of(context);
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(controlRadius),
    );
    return base.copyWith(
      scaffoldBackgroundColor: warmWhite,
      colorScheme: ColorScheme.fromSeed(
        seedColor: green,
      ).copyWith(primary: green, onPrimary: Colors.white, surface: warmWhite),
      textTheme: base.textTheme.apply(bodyColor: text, displayColor: darkGreen),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: green,
          foregroundColor: Colors.white,
          minimumSize: const Size.fromHeight(56),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          shape: shape,
          elevation: elevation,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: green,
          minimumSize: const Size(touchTarget, touchTarget),
          shape: shape,
        ),
      ),
    );
  }
}

class AbashyakaLogo extends StatelessWidget {
  const AbashyakaLogo({super.key, this.size = 96});
  final double size;

  @override
  Widget build(BuildContext context) => Image.asset(
    AbashyakaTheme.logo,
    width: size,
    height: size,
    fit: BoxFit.contain,
    excludeFromSemantics: true,
    cacheWidth: (size * MediaQuery.devicePixelRatioOf(context)).ceil(),
  );
}
