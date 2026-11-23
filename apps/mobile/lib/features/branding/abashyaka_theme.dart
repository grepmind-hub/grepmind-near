import 'package:flutter/material.dart';

/// 2027 Abashyaka Design System & Brand Identity Tokens.
///
/// Authoritative Palette:
/// - Vibrant Green (#09A110): Primary action accent
/// - Action Green (#087F0D): Accessible buttons with white text
/// - Deep Emerald (#064D3A): Branding and headings
/// - Fresh Leaf (#78CE65): Illustrations and highlights
/// - Soft Lime (#DDF5A6): Premium promotional banners
/// - Light Mint (#E4F7E3): Header and selected states
/// - Pearl Green (#F3FAF0): Subtle section backgrounds
/// - Signature Orange (#FF8A00): Offers and notification indicators
/// - Warm Peach (#FFE4D1): Food category
/// - Sky Blue (#DFEEFF): Healthcare category
/// - Pure White (#FFFFFF): Cards and main background
/// - Carbon (#172820): Primary text
abstract final class AbashyakaTheme {
  // --- Authoritative Color Tokens ---
  static const vibrantGreen = Color(0xFF09A110);
  static const actionGreen = Color(0xFF087F0D);
  static const deepEmerald = Color(0xFF064D3A);
  static const freshLeaf = Color(0xFF78CE65);
  static const softLime = Color(0xFFDDF5A6);
  static const lightMint = Color(0xFFE4F7E3);
  static const pearlGreen = Color(0xFFF3FAF0);
  static const signatureOrange = Color(0xFFFF8A00);
  static const warmPeach = Color(0xFFFFE4D1);
  static const skyBlue = Color(0xFFDFEEFF);
  static const pureWhite = Color(0xFFFFFFFF);
  static const carbon = Color(0xFF172820);
  static const mutedSlate = Color(0xFF64748B);
  static const border = Color(0xFFE2E8F0);

  // --- Convenience & Semantic Aliases ---
  static const green = actionGreen;
  static const darkGreen = deepEmerald;
  static const mint = lightMint;
  static const orange = signatureOrange;
  static const warmWhite = pureWhite;
  static const canvas = pearlGreen;
  static const surface = pureWhite;
  static const text = carbon;
  static const muted = mutedSlate;
  static const signatureEmerald = actionGreen;

  // --- Sizing, Radii & Motion ---
  static const space = 4.0;
  static const pagePadding = 24.0;
  static const cardRadius = 20.0;
  static const controlRadius = 18.0;
  static const pillRadius = 28.0;
  static const touchTarget = 48.0;
  static const elevation = 0.0;
  static const entrance = Duration(milliseconds: 400);
  static const transition = Duration(milliseconds: 200);

  // --- Brand Assets (Preserved without modification) ---
  static const logo = 'assets/abashyaka/app_icon_source.png';
  static const splashEmblem = 'assets/abashyaka/splash_emblem.png';
  static const splashLandscape = 'assets/abashyaka/splash_landscape.png';
  static const illustration = 'assets/abashyaka/onboarding_customer_hero.png';
  static const onboardingHero = 'assets/abashyaka/onboarding_customer_hero.png';

  // --- Button Styles ---

  /// Action Green Button Style (#087F0D - Accessible button with white text)
  static ButtonStyle actionGreenButtonStyle({
    double radius = pillRadius,
    double height = 54.0,
  }) => ElevatedButton.styleFrom(
    backgroundColor: actionGreen,
    foregroundColor: pureWhite,
    elevation: 0,
    minimumSize: Size(double.infinity, height),
    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 15),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(radius),
    ),
    textStyle: const TextStyle(
      fontSize: 16,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.1,
    ),
  );

  /// Vibrant Green Button Style (#09A110 - Primary action accent)
  static ButtonStyle vibrantGreenButtonStyle({
    double radius = pillRadius,
    double height = 54.0,
  }) => ElevatedButton.styleFrom(
    backgroundColor: vibrantGreen,
    foregroundColor: pureWhite,
    elevation: 0,
    minimumSize: Size(double.infinity, height),
    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 15),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(radius),
    ),
    textStyle: const TextStyle(
      fontSize: 16,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.1,
    ),
  );

  /// Signature Orange Button Style (#FF8A00 - Offers & highlights)
  static ButtonStyle orangeButtonStyle({
    double radius = pillRadius,
    double height = 54.0,
  }) => ElevatedButton.styleFrom(
    backgroundColor: signatureOrange,
    foregroundColor: pureWhite,
    elevation: 0,
    minimumSize: Size(double.infinity, height),
    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 15),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(radius),
    ),
    textStyle: const TextStyle(
      fontSize: 16,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.1,
    ),
  );

  static ThemeData theme(BuildContext context) {
    final base = Theme.of(context);
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(pillRadius),
    );
    return base.copyWith(
      scaffoldBackgroundColor: pureWhite,
      colorScheme: ColorScheme.fromSeed(
        seedColor: actionGreen,
      ).copyWith(
        primary: actionGreen,
        onPrimary: pureWhite,
        secondary: signatureOrange,
        onSecondary: pureWhite,
        surface: pureWhite,
      ),
      textTheme: base.textTheme.apply(bodyColor: carbon, displayColor: deepEmerald),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: actionGreen,
          foregroundColor: pureWhite,
          minimumSize: const Size.fromHeight(54),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          shape: shape,
          elevation: elevation,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: actionGreen,
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

/// Reusable Primary Action Button Widget (using Action Green #087F0D or Vibrant Green #09A110)
class AbashyakaPrimaryButton extends StatelessWidget {
  final String text;
  final VoidCallback? onPressed;
  final bool isLoading;
  final IconData? icon;
  final double height;
  final double radius;
  final bool useVibrantGreen;

  const AbashyakaPrimaryButton({
    super.key,
    required this.text,
    required this.onPressed,
    this.isLoading = false,
    this.icon,
    this.height = 54.0,
    this.radius = AbashyakaTheme.pillRadius,
    this.useVibrantGreen = false,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      width: double.infinity,
      child: ElevatedButton(
        style: useVibrantGreen
            ? AbashyakaTheme.vibrantGreenButtonStyle(radius: radius, height: height)
            : AbashyakaTheme.actionGreenButtonStyle(radius: radius, height: height),
        onPressed: isLoading ? null : onPressed,
        child: isLoading
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (icon != null) ...[
                    Icon(icon, size: 20, color: Colors.white),
                    const SizedBox(width: 8),
                  ],
                  Text(text),
                ],
              ),
      ),
    );
  }
}
