import 'package:flutter/material.dart';
import 'package:grepmind_mobile/core/models/business.dart';
import 'package:grepmind_mobile/core/theme/app_theme.dart';
import 'package:grepmind_mobile/core/widgets/premium_card.dart';

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
        ? const EdgeInsets.symmetric(horizontal: 8, vertical: 4)
        : const EdgeInsets.symmetric(horizontal: 10, vertical: 5);
    return Container(
      padding: pad,
      decoration: BoxDecoration(color: _bg, borderRadius: BorderRadius.circular(20)),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
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

/// Compact business result card for lists.
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

  @override
  Widget build(BuildContext context) {
    return PremiumCard(
      padding: const EdgeInsets.all(14),
      onTap: onTap,
      margin: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Thumbnail / placeholder.
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: SizedBox(
              width: 72,
              height: 72,
              child: business.coverPhotoUrl != null
                  ? Image.network(
                      business.coverPhotoUrl!,
                      fit: BoxFit.cover,
                      width: 72,
                      height: 72,
                      errorBuilder: (_, __, ___) => _placeholder(),
                    )
                  : _placeholder(),
            ),
          ),
          const SizedBox(width: 12),
          // Details.
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        business.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: AppTheme.mainText,
                            ),
                      ),
                    ),
                    if (business.verificationStatus == 'verified')
                      const StatusChip(
                        label: 'Verified',
                        type: StatusChipType.success,
                        size: StatusChipSize.small,
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Icon(Icons.category_outlined, size: 14, color: AppTheme.hintText),
                    const SizedBox(width: 4),
                    Text(
                      business.categoryName ?? business.categorySlug,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppTheme.secondaryText,
                          ),
                    ),
                    const SizedBox(width: 10),
                    if (business.distanceM != null)
                      Text(
                        business.distanceText,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: AppTheme.secondaryText,
                            ),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    StatusChip(
                      label: business.isOpenNow ? 'Open now' : 'Closed',
                      type: business.isOpenNow ? StatusChipType.success : StatusChipType.info,
                      size: StatusChipSize.small,
                    ),
                    const SizedBox(width: 8),
                    if (business.acceptsRequests)
                      const StatusChip(
                        label: 'Accepting requests',
                        type: StatusChipType.success,
                        size: StatusChipSize.small,
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // Favorite toggle.
          InkWell(
            onTap: onFavoriteToggled,
            borderRadius: BorderRadius.circular(12),
            child: Icon(
              isFavorited ? Icons.favorite : Icons.favorite_border,
              color: isFavorited ? AppTheme.error : AppTheme.hintText,
              size: 22,
            ),
          ),
        ],
      ),
    );
  }

  Widget _placeholder() {
    return Container(
      color: AppTheme.surfaceVariant,
      child: const Icon(Icons.store_outlined, color: AppTheme.hintText, size: 24),
    );
  }
}
