import 'package:flutter/material.dart';
import 'package:grepmind_mobile/core/models/business.dart';
import 'package:grepmind_mobile/core/theme/app_theme.dart';
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
      decoration: BoxDecoration(color: _bg, borderRadius: BorderRadius.circular(12)),
      child: Text(
        label,
        style: TextStyle(
          color: _fg,
          fontWeight: FontWeight.w600,
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
    final ratingVal = business.rating ?? 4.8;
    final reviewsCount = business.reviewCount ?? 128;
    final categoryText = business.categoryName ?? (business.categorySlug.isNotEmpty 
        ? '${business.categorySlug[0].toUpperCase()}${business.categorySlug.substring(1)}'
        : 'Store');

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE4E7EC)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
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
                    child: business.coverPhotoUrl != null && business.coverPhotoUrl!.isNotEmpty
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
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.mainText,
                          letterSpacing: -0.2,
                        ),
                      ),
                      const SizedBox(height: 4),
                      // Rating row: ★ 4.8 (128)
                      Row(
                        children: [
                          const Icon(Icons.star_rounded, size: 16, color: Color(0xFFF59E0B)),
                          const SizedBox(width: 3),
                          Text(
                            ratingVal.toStringAsFixed(1),
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.mainText,
                            ),
                          ),
                          const SizedBox(width: 3),
                          Text(
                            '($reviewsCount)',
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppTheme.secondaryText,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      // Category & Distance: Hardware • 0.8 km
                      Row(
                        children: [
                          Text(
                            categoryText,
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppTheme.secondaryText,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          if (business.distanceM != null) ...[
                            const Text(
                              ' • ',
                              style: TextStyle(
                                fontSize: 12,
                                color: AppTheme.secondaryText,
                              ),
                            ),
                            Text(
                              business.distanceText,
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppTheme.secondaryText,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 6),
                      // Status: Open pill
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: business.isOpenNow 
                                  ? const Color(0xFFECFDF3) 
                                  : const Color(0xFFF2F4F7),
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
                                        ? const Color(0xFF15803D) 
                                        : const Color(0xFF9AA5B1),
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  business.isOpenNow ? 'Open' : 'Closed',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    color: business.isOpenNow 
                                        ? const Color(0xFF15803D) 
                                        : const Color(0xFF667085),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (business.verificationStatus == 'verified') ...[
                            const SizedBox(width: 6),
                            const Icon(Icons.verified, size: 14, color: AppTheme.primary),
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
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
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
                        child: const Text(
                          'Call',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
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
                          isFavorited ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                          color: isFavorited ? AppTheme.error : const Color(0xFF9AA5B1),
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
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFFF2F4F7), Color(0xFFE4E7EC)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: const Center(
        child: Icon(Icons.storefront_rounded, color: Color(0xFF9AA5B1), size: 30),
      ),
    );
  }
}

