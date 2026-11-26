import 'package:flutter/material.dart';
import 'package:grepmind_mobile/core/models/business.dart';
import 'package:grepmind_mobile/core/theme/app_theme.dart';
import 'package:grepmind_mobile/core/widgets/category_placeholder.dart';
import 'package:url_launcher/url_launcher.dart';

/// Verification / open-status badge chip.
class StatusChip extends StatelessWidget {
  const StatusChip({
    super.key,
    required this.label,
    this.type = StatusChipType.info,
    this.size = StatusChipSize.small,
  });

  final String label;
  final StatusChipType type;
  final StatusChipSize size;

  Color get _bg {
    switch (type) {
      case StatusChipType.success:
        return AppTheme.successContainer;
      case StatusChipType.warning:
        return AppTheme.warningContainer;
      case StatusChipType.error:
        return AppTheme.errorContainer;
      case StatusChipType.info:
        return AppTheme.surfaceVariant;
    }
  }

  Color get _fg {
    switch (type) {
      case StatusChipType.success:
        return AppTheme.success;
      case StatusChipType.warning:
        return AppTheme.warning;
      case StatusChipType.error:
        return AppTheme.error;
      case StatusChipType.info:
        return AppTheme.secondaryText;
    }
  }

  @override
  Widget build(BuildContext context) {
    final pad = size == StatusChipSize.small
        ? const EdgeInsets.symmetric(horizontal: 8, vertical: 3)
        : const EdgeInsets.symmetric(horizontal: 10, vertical: 5);
    return Container(
      padding: pad,
      decoration: BoxDecoration(
        color: _bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: AbashyakaTypography.categoryLabel(
          color: _fg,
          fontSize: size == StatusChipSize.small ? 10 : 11,
        ),
      ),
    );
  }
}

enum StatusChipType { info, success, warning, error }

enum StatusChipSize { small, medium }

/// Business card matching Screen 7 & Screen 9 in the UI showcase.
class BusinessCard extends StatelessWidget {
  const BusinessCard({
    super.key,
    required this.business,
    this.onTap,
    this.onFavoriteToggled,
    this.isFavorited = false,
  });

  final Business business;
  final VoidCallback? onTap;
  final VoidCallback? onFavoriteToggled;
  final bool isFavorited;

  Future<void> _makeCall(String? phone) async {
    if (phone == null || phone.isEmpty) return;
    final uri = Uri.parse('tel:$phone');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ratingVal = business.rating;
    final reviewsCount = business.reviewCount;
    final categoryText =
        business.categoryName ??
        (business.categorySlug.isNotEmpty
            ? '${business.categorySlug[0].toUpperCase()}${business.categorySlug.substring(1)}'
            : 'Store');

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AbashyakaColors.pureWhite,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AbashyakaColors.aquaSilverBorder),
        boxShadow: AbashyakaShadows.card,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                // Thumbnail
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: SizedBox(
                    width: 78,
                    height: 78,
                    child:
                        business.coverPhotoUrl != null &&
                            business.coverPhotoUrl!.isNotEmpty
                        ? Image.network(
                            business.coverPhotoUrl!,
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => _placeholder(),
                          )
                        : _placeholder(),
                  ),
                ),
                const SizedBox(width: 12),
                // Middle Details
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Name
                      Text(
                        business.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AbashyakaTypography.cardTitle(
                          color: AppTheme.mainText,
                        ).copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 4),
                      // Rating row: ★ 4.8 (128)
                      Row(
                        children: [
                          const Icon(
                            Icons.star_rounded,
                            size: 16,
                            color: AbashyakaColors.ratingStar,
                          ),
                          const SizedBox(width: 3),
                          Text(
                            ratingVal?.toStringAsFixed(1) ?? 'Not rated',
                            style: AbashyakaTypography.ratingText(
                              color: AppTheme.mainText,
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(width: 3),
                          Text(
                            reviewsCount == null ? '' : '($reviewsCount)',
                            style: AbashyakaTypography.supportingText(
                              color: AppTheme.secondaryText,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      // Category & Locality / Distance: Hardware • Badambadi • 0.8 km
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              business.locality != null &&
                                      business.locality!.isNotEmpty
                                  ? '$categoryText • ${business.locality}'
                                  : categoryText,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AbashyakaTypography.supportingText(
                                color: AppTheme.secondaryText,
                                fontSize: 12,
                              ),
                            ),
                          ),
                          if (business.distanceM != null) ...[
                            Text(
                              ' • ',
                              style: AbashyakaTypography.supportingText(
                                color: AppTheme.secondaryText,
                                fontSize: 12,
                              ),
                            ),
                            Text(
                              business.distanceText,
                              style: AbashyakaTypography.supportingText(
                                color: AppTheme.secondaryText,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 6),
                      // Status: Open pill + Delivery / Dine-in pill
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: business.isOpenNow
                                  ? AbashyakaColors.successSurface
                                  : AbashyakaColors.unavailableSurface,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 6,
                                  height: 6,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: business.isOpenNow
                                        ? AbashyakaColors.success
                                        : AbashyakaColors.disabledText,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  business.isOpenNow ? 'Open' : 'Closed',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    color: business.isOpenNow
                                        ? AbashyakaColors.success
                                        : AbashyakaColors.mutedText,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (business.categorySlug == 'restaurant' ||
                              business.categorySlug == 'cafe') ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: business.deliveryEnabled
                                    ? AbashyakaColors.successSurface
                                    : AbashyakaColors.unavailableSurface,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                business.deliveryEnabled
                                    ? 'Delivery'
                                    : 'Dine-in Only',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: business.deliveryEnabled
                                      ? AbashyakaColors.success
                                      : AbashyakaColors.secondaryText,
                                ),
                              ),
                            ),
                          ],
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: AbashyakaColors.iceAquaWhite,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: AbashyakaColors.metallicTeal.withValues(alpha: 0.25),
                              ),
                            ),
                            child: Text(
                              business.categoryNatureLabel,
                              style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: AbashyakaColors.signatureTeal,
                              ),
                            ),
                          ),
                          if (business.verificationStatus == 'verified') ...[
                            const SizedBox(width: 6),
                            const Icon(
                              Icons.verified,
                              size: 14,
                              color: AppTheme.primary,
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                // Action: Call Button
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    InkWell(
                      onTap: () => _makeCall(business.phoneE164),
                      borderRadius: BorderRadius.circular(18),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 7,
                        ),
                        decoration: BoxDecoration(
                          color: AppTheme.primary,
                          borderRadius: BorderRadius.circular(18),
                          boxShadow: [
                            BoxShadow(
                              color: AppTheme.primary.withValues(alpha: 0.25),
                              blurRadius: 6,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Text(
                          'Call',
                          style: AbashyakaTypography.buttonText(
                            color: AbashyakaColors.pureWhite,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    InkWell(
                      onTap: onFavoriteToggled,
                      borderRadius: BorderRadius.circular(14),
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: Icon(
                          isFavorited
                              ? Icons.favorite_rounded
                              : Icons.favorite_border_rounded,
                          color: isFavorited
                              ? AppTheme.error
                              : AbashyakaColors.disabledText,
                          size: 20,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _placeholder() {
    return CategoryThemedPlaceholder(
      categorySlug: business.categorySlug,
      categoryName: business.categoryName,
      businessName: business.name,
      isAvatar: true,
    );
  }
}
