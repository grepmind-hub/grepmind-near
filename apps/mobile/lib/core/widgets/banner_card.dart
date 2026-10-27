import 'package:flutter/material.dart';
import 'package:grepmind_mobile/core/theme/app_theme.dart';
import 'package:grepmind_mobile/core/widgets/premium_card.dart';

/// Offer / promotional banner card with a gradient accent.
class BannerCard extends StatelessWidget {
  const BannerCard({
    super.key,
    required this.title,
    required this.subtitle,
    this.imageUrl,
    this.gradient = AppTheme.primary,
    this.onTap,
    this.height = 150,
  });

  final String title;
  final String subtitle;
  final String? imageUrl;
  final Color gradient;
  final VoidCallback? onTap;
  final double height;

  @override
  Widget build(BuildContext context) {
    final content = PremiumCard(
      padding: const EdgeInsets.all(16),
      radius: kCardRadius,
      color: AppTheme.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(width: 4, height: 20, color: gradient),
          const SizedBox(height: 12),
          Text(
            title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: AppTheme.mainText,
                ),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppTheme.secondaryText,
                  height: 1.3,
                ),
          ),
        ],
      ),
    );

    if (imageUrl != null) {
      return Stack(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(kCardRadius),
            child: Image.network(imageUrl!, height: height, width: double.infinity, fit: BoxFit.cover),
          ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(kCardRadius),
                gradient: LinearGradient(
                  colors: [Colors.black.withValues(alpha: 0.35), Colors.transparent],
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                ),
              ),
            ),
          ),
          Positioned.fill(child: content),
        ],
      );
    }

    return onTap == null
        ? content
        : Material(
            color: Colors.transparent,
            child: InkWell(onTap: onTap, borderRadius: BorderRadius.circular(kCardRadius), child: content),
          );
  }
}
