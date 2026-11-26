import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/abashyaka_colors.dart';
import '../theme/abashyaka_gradients.dart';
import '../theme/abashyaka_tokens.dart';
import '../theme/abashyaka_typography.dart';

/// The official metallic teal glossy primary button for Abashyaka.
///
/// Features:
/// - Three-stop metallic teal gradient (#00B3AE -> #008C95 -> #00545B)
/// - Top-edge specular glossy highlight
/// - Soft teal-tinted elevation shadow
/// - Minimum 48x48 touch target
/// - Asynchronous loading spinner & debounce protection
class MetallicButton extends StatelessWidget {
  final String text;
  final VoidCallback? onPressed;
  final bool isLoading;
  final Widget? trailingIcon;
  final Widget? leadingIcon;
  final double height;
  final double radius;
  final double? width;
  final Key? buttonKey;

  const MetallicButton({
    super.key,
    required this.text,
    this.onPressed,
    this.isLoading = false,
    this.trailingIcon,
    this.leadingIcon,
    this.height = 54.0,
    this.radius = AbashyakaRadius.button,
    this.width,
    this.buttonKey,
  });

  @override
  Widget build(BuildContext context) {
    final isDisabled = onPressed == null || isLoading;

    return Semantics(
      button: true,
      enabled: !isDisabled,
      child: Container(
        key: buttonKey,
        width: width ?? double.infinity,
        height: height,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(radius),
          gradient: isDisabled
              ? const LinearGradient(
                  colors: [
                    AbashyakaColors.softGrey,
                    AbashyakaColors.silverGlass,
                  ],
                )
              : AbashyakaGradients.metallicButton,
          boxShadow: isDisabled ? null : AbashyakaShadows.metallicButton,
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: isDisabled
                ? null
                : () {
                    HapticFeedback.lightImpact();
                    onPressed?.call();
                  },
            borderRadius: BorderRadius.circular(radius),
            splashColor: AbashyakaColors.aquaGlow.withValues(alpha: 0.2),
            highlightColor: AbashyakaColors.darkOceanTeal.withValues(
              alpha: 0.1,
            ),
            child: Stack(
              children: [
                // Glossy specular highlight along the upper half
                if (!isDisabled)
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    height: height * 0.45,
                    child: ClipRRect(
                      borderRadius: BorderRadius.vertical(
                        top: Radius.circular(radius),
                      ),
                      child: Container(
                        decoration: const BoxDecoration(
                          gradient: AbashyakaGradients.buttonGlassHighlight,
                        ),
                      ),
                    ),
                  ),

                // Button Content
                Center(
                  child: isLoading
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              AbashyakaColors.pureWhite,
                            ),
                          ),
                        )
                      : Row(
                          mainAxisSize: MainAxisSize.min,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            if (leadingIcon != null) ...[
                              leadingIcon!,
                              const SizedBox(width: 8),
                            ],
                            Flexible(
                              child: Text(
                                text,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AbashyakaTypography.buttonText(
                                  color: isDisabled
                                      ? AbashyakaColors.secondaryText
                                      : AbashyakaColors.pureWhite,
                                ),
                              ),
                            ),
                            if (trailingIcon != null) ...[
                              const SizedBox(width: 8),
                              trailingIcon!,
                            ],
                          ],
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Secondary glossy button (Pure White surface, Silver Glass border, Ink Black / Deep Teal text).
class PremiumSecondaryButton extends StatelessWidget {
  final String text;
  final VoidCallback? onPressed;
  final Widget? leadingIcon;
  final double height;
  final double radius;
  final double? width;
  final Key? buttonKey;

  const PremiumSecondaryButton({
    super.key,
    required this.text,
    this.onPressed,
    this.leadingIcon,
    this.height = 54.0,
    this.radius = AbashyakaRadius.button,
    this.width,
    this.buttonKey,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      key: buttonKey,
      width: width ?? double.infinity,
      height: height,
      decoration: BoxDecoration(
        color: AbashyakaColors.pureWhite,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: AbashyakaColors.silverGlass, width: 1.2),
        boxShadow: AbashyakaShadows.card,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed == null
              ? null
              : () {
                  HapticFeedback.lightImpact();
                  onPressed?.call();
                },
          borderRadius: BorderRadius.circular(radius),
          splashColor: AbashyakaColors.lightAqua.withValues(alpha: 0.3),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (leadingIcon != null) ...[
                      leadingIcon!,
                      const SizedBox(width: 10),
                    ],
                    Text(
                      text,
                      style: AbashyakaTypography.buttonText(
                        color: AbashyakaColors.inkBlack,
                      ).copyWith(fontSize: 15, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
