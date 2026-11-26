import 'package:flutter/material.dart';
import 'package:grepmind_mobile/core/theme/app_theme.dart';

/// Official Option 2 ("Commerce-A": Storefront Bar + A) vector brand mark.
///
/// Pure flat vector geometry (no gradients or raster bitmaps) so it scales
/// crisply from 20px header badges to 140px splash emblems.
class AbashyakaLogoMark extends StatelessWidget {
  const AbashyakaLogoMark({
    super.key,
    this.size = 40,
    this.showBadge = true,
    this.badgeColor,
    this.letterColor,
    this.accentColor,
    this.borderColor,
  });

  final double size;
  final bool showBadge;
  final Color? badgeColor;
  final Color? letterColor;
  final Color? accentColor;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    final palette = context.abashyaka;
    final resolvedBadge =
        badgeColor ??
        (palette.isDark
            ? const Color(0xFF152232)
            : AbashyakaColors.signatureTeal);
    final resolvedLetter =
        letterColor ??
        (showBadge ? AbashyakaColors.pureWhite : AbashyakaColors.signatureTeal);
    final resolvedAccent = accentColor ?? AbashyakaColors.saffronOrange;

    return Semantics(
      label: 'Abashyaka logo',
      image: true,
      child: SizedBox(
        width: size,
        height: size,
        child: CustomPaint(
          painter: _CommerceALogoPainter(
            showBadge: showBadge,
            badgeColor: resolvedBadge,
            letterColor: resolvedLetter,
            accentColor: resolvedAccent,
            borderColor: borderColor,
          ),
        ),
      ),
    );
  }
}

class _CommerceALogoPainter extends CustomPainter {
  const _CommerceALogoPainter({
    required this.showBadge,
    required this.badgeColor,
    required this.letterColor,
    required this.accentColor,
    this.borderColor,
  });

  final bool showBadge;
  final Color badgeColor;
  final Color letterColor;
  final Color accentColor;
  final Color? borderColor;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final h = size.height;

    if (showBadge) {
      final rect = Rect.fromLTWH(0, 0, s, h);
      final rrect = RRect.fromRectAndRadius(rect, Radius.circular(s * 0.25));
      canvas.drawRRect(rrect, Paint()..color = badgeColor);
      if (borderColor != null) {
        canvas.drawRRect(
          rrect.deflate(0.75),
          Paint()
            ..color = borderColor!
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5,
        );
      }
    }

    // Geometric "A" chevron legs (matching Option 2 Commerce-A SVG proportions).
    final scaleX = s / 88.0;
    final scaleY = h / 88.0;

    final aPath = Path()
      ..moveTo(44 * scaleX, 18 * scaleY)
      ..lineTo(23 * scaleX, 69 * scaleY)
      ..lineTo(33.2 * scaleX, 69 * scaleY)
      ..lineTo(44 * scaleX, 41.2 * scaleY)
      ..lineTo(54.8 * scaleX, 69 * scaleY)
      ..lineTo(65 * scaleX, 69 * scaleY)
      ..close();

    canvas.drawPath(aPath, Paint()..color = letterColor);

    // Sleek horizontal storefront / parcel crossbar in Saffron Orange.
    final barRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(32 * scaleX, 51.5 * scaleY, 24 * scaleX, 8 * scaleY),
      Radius.circular(4 * scaleY),
    );
    canvas.drawRRect(barRect, Paint()..color = accentColor);
  }

  @override
  bool shouldRepaint(covariant _CommerceALogoPainter oldDelegate) =>
      oldDelegate.showBadge != showBadge ||
      oldDelegate.badgeColor != badgeColor ||
      oldDelegate.letterColor != letterColor ||
      oldDelegate.accentColor != accentColor ||
      oldDelegate.borderColor != borderColor;
}

/// Compact horizontal brand lockup: [Commerce-A Mark] + "Abashyaka" wordmark.
class AbashyakaBrandLockup extends StatelessWidget {
  const AbashyakaBrandLockup({
    super.key,
    this.iconSize = 32,
    this.fontSize = 20,
    this.onTealHeader = true,
  });

  final double iconSize;
  final double fontSize;
  final bool onTealHeader;

  @override
  Widget build(BuildContext context) {
    final palette = context.abashyaka;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        AbashyakaLogoMark(
          size: iconSize,
          badgeColor: onTealHeader
              ? AbashyakaColors.pureWhite
              : AbashyakaColors.signatureTeal,
          letterColor: onTealHeader
              ? AbashyakaColors.signatureTeal
              : AbashyakaColors.pureWhite,
        ),
        const SizedBox(width: 8),
        Text(
          'Abashyaka',
          style: AbashyakaTypography.brandWordmark(
            fontSize: fontSize,
            color: onTealHeader
                ? AbashyakaColors.pureWhite
                : palette.textPrimary,
          ).copyWith(fontWeight: FontWeight.w800),
        ),
      ],
    );
  }
}
