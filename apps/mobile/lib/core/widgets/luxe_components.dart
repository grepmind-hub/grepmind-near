import 'package:flutter/material.dart';
import 'package:grepmind_mobile/core/theme/app_theme.dart';

/// Base container for GrepMind Local Luxe design language.
/// 20px radius, 1px subtle neutral border, soft elevation.
class LuxeCard extends StatelessWidget {
  const LuxeCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.margin,
    this.onTap,
    this.backgroundColor = Colors.white,
    this.borderColor,
    this.borderRadius,
    this.clipBehavior = Clip.antiAlias,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;
  final VoidCallback? onTap;
  final Color backgroundColor;
  final Color? borderColor;
  final BorderRadius? borderRadius;
  final Clip clipBehavior;

  @override
  Widget build(BuildContext context) {
    final radius = borderRadius ?? BorderRadius.circular(20);
    final cardWidget = Container(
      margin: margin,
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: radius,
        border: Border.all(
          color: borderColor ?? AppTheme.border,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      clipBehavior: clipBehavior,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: radius,
          child: Padding(
            padding: padding,
            child: child,
          ),
        ),
      ),
    );

    return cardWidget;
  }
}

/// Status Pill Badge for verified badges, settlement status, and delivery states.
class LuxeStatusBadge extends StatelessWidget {
  const LuxeStatusBadge({
    super.key,
    required this.label,
    this.icon,
    this.color,
    this.backgroundColor,
    this.isSmall = false,
  });

  final String label;
  final IconData? icon;
  final Color? color;
  final Color? backgroundColor;
  final bool isSmall;

  factory LuxeStatusBadge.verified({String label = 'Verified'}) => LuxeStatusBadge(
        label: label,
        icon: Icons.verified_rounded,
        color: AppTheme.mint,
        backgroundColor: AppTheme.mintLight,
      );

  factory LuxeStatusBadge.pending({String label = 'Pending'}) => LuxeStatusBadge(
        label: label,
        icon: Icons.schedule_rounded,
        color: const Color(0xFFB45309),
        backgroundColor: AppTheme.amberLight,
      );

  factory LuxeStatusBadge.failed({String label = 'Failed'}) => LuxeStatusBadge(
        label: label,
        icon: Icons.error_outline_rounded,
        color: AppTheme.coral,
        backgroundColor: AppTheme.coralLight,
      );

  @override
  Widget build(BuildContext context) {
    final fg = color ?? AppTheme.mint;
    final bg = backgroundColor ?? AppTheme.mintLight;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isSmall ? 8 : 10,
        vertical: isSmall ? 3 : 5,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: isSmall ? 12 : 14, color: fg),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: isSmall ? 11 : 12,
              fontWeight: FontWeight.w700,
              color: fg,
            ),
          ),
        ],
      ),
    );
  }
}

/// 2-Column Quick Commerce Product Card ("Today's Essentials")
class LuxeProductCard extends StatelessWidget {
  const LuxeProductCard({
    super.key,
    required this.name,
    required this.priceMinor,
    this.mrpMinor,
    this.unitText,
    this.imageUrl,
    this.quantity = 0,
    this.onAdd,
    this.onIncrement,
    this.onDecrement,
    this.onTap,
  });

  final String name;
  final int priceMinor;
  final int? mrpMinor;
  final String? unitText;
  final String? imageUrl;
  final int quantity;
  final VoidCallback? onAdd;
  final VoidCallback? onIncrement;
  final VoidCallback? onDecrement;
  final VoidCallback? onTap;

  String _formatPrice(int minor) => '₹${(minor / 100).toStringAsFixed(minor % 100 == 0 ? 0 : 2)}';

  @override
  Widget build(BuildContext context) {
    return LuxeCard(
      padding: const EdgeInsets.all(12),
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Image container
          Container(
            height: 110,
            width: double.infinity,
            decoration: BoxDecoration(
              color: AppTheme.canvas,
              borderRadius: BorderRadius.circular(14),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: imageUrl != null && imageUrl!.startsWith('http')
                  ? Image.network(
                      imageUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) => _placeholderIcon(),
                    )
                  : _placeholderIcon(),
            ),
          ),
          const SizedBox(height: 10),
          // Product Name
          Text(
            name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: AppTheme.textPrimary,
              height: 1.25,
            ),
          ),
          if (unitText != null && unitText!.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              unitText!,
              style: const TextStyle(
                fontSize: 12,
                color: AppTheme.textSecondary,
              ),
            ),
          ],
          const Spacer(),
          // Price and Add Button row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (mrpMinor != null && mrpMinor! > priceMinor)
                    Text(
                      _formatPrice(mrpMinor!),
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppTheme.textMuted,
                        decoration: TextDecoration.lineThrough,
                      ),
                    ),
                  Text(
                    _formatPrice(priceMinor),
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                ],
              ),
              // Add CTA / Stepper
              if (quantity > 0)
                Container(
                  height: 36,
                  decoration: BoxDecoration(
                    color: AppTheme.mint,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.remove, size: 16, color: Colors.white),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 32, minHeight: 36),
                        onPressed: onDecrement,
                      ),
                      Text(
                        '$quantity',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.add, size: 16, color: Colors.white),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 32, minHeight: 36),
                        onPressed: onIncrement,
                      ),
                    ],
                  ),
                )
              else
                SizedBox(
                  height: 36,
                  child: OutlinedButton(
                    onPressed: onAdd,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.mint,
                      side: const BorderSide(color: AppTheme.mint, width: 1.5),
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: const Text(
                      '+ Add',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _placeholderIcon() => const Center(
        child: Icon(Icons.shopping_bag_outlined, color: AppTheme.mint, size: 38),
      );
}

/// Horizontal Service Professional Card
class LuxeServiceCard extends StatelessWidget {
  const LuxeServiceCard({
    super.key,
    required this.tradeTitle,
    required this.rating,
    required this.jobCountText,
    required this.availabilityText,
    required this.distanceText,
    required this.startingPriceMinor,
    this.photoUrl,
    this.isVerified = true,
    this.onBook,
    this.onTap,
  });

  final String tradeTitle;
  final double rating;
  final String jobCountText;
  final String availabilityText;
  final String distanceText;
  final int startingPriceMinor;
  final String? photoUrl;
  final bool isVerified;
  final VoidCallback? onBook;
  final VoidCallback? onTap;

  String _formatPrice(int minor) => '₹${(minor / 100).toStringAsFixed(0)}';

  @override
  Widget build(BuildContext context) {
    return LuxeCard(
      padding: const EdgeInsets.all(14),
      onTap: onTap,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Professional photo / avatar
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: AppTheme.canvas,
              borderRadius: BorderRadius.circular(14),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: photoUrl != null && photoUrl!.startsWith('http')
                  ? Image.network(
                      photoUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) => _avatarFallback(),
                    )
                  : _avatarFallback(),
            ),
          ),
          const SizedBox(width: 14),
          // Info section
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        tradeTitle,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                    ),
                    if (isVerified) ...[
                      const SizedBox(width: 6),
                      const Icon(Icons.verified, size: 16, color: AppTheme.mint),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                // Rating and jobs
                Row(
                  children: [
                    const Icon(Icons.star_rounded, size: 16, color: AppTheme.amber),
                    const SizedBox(width: 3),
                    Text(
                      rating.toStringAsFixed(1),
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '($jobCountText)',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                // Availability & distance
                Row(
                  children: [
                    const Icon(Icons.bolt_rounded, size: 14, color: AppTheme.mint),
                    const SizedBox(width: 3),
                    Text(
                      availabilityText,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.mint,
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Text('·', style: TextStyle(color: AppTheme.textMuted)),
                    const SizedBox(width: 8),
                    Text(
                      distanceText,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // Price and Book button
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              const Text(
                'From',
                style: TextStyle(fontSize: 11, color: AppTheme.textSecondary),
              ),
              Text(
                _formatPrice(startingPriceMinor),
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.coral,
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 34,
                child: ElevatedButton(
                  onPressed: onBook,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.mint,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: const Text(
                    'Book Now',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _avatarFallback() => const Center(
        child: Icon(Icons.handyman_rounded, color: AppTheme.forest, size: 32),
      );
}

/// Nearby Local Shop Card
class LuxeShopCard extends StatelessWidget {
  const LuxeShopCard({
    super.key,
    required this.name,
    required this.categoryText,
    required this.distanceText,
    required this.rating,
    this.photoUrl,
    this.onTap,
  });

  final String name;
  final String categoryText;
  final String distanceText;
  final double rating;
  final String? photoUrl;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 170,
      margin: const EdgeInsets.only(right: 12),
      child: LuxeCard(
        padding: EdgeInsets.zero,
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Image with rating pill
            Stack(
              children: [
                Container(
                  height: 100,
                  width: double.infinity,
                  color: AppTheme.canvas,
                  child: photoUrl != null && photoUrl!.startsWith('http')
                      ? Image.network(
                          photoUrl!,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) => _coverFallback(),
                        )
                      : _coverFallback(),
                ),
                Positioned(
                  bottom: 6,
                  right: 6,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(6),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.1),
                          blurRadius: 4,
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.star_rounded, size: 13, color: AppTheme.amber),
                        const SizedBox(width: 2),
                        Text(
                          rating.toStringAsFixed(1),
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '$categoryText · $distanceText',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _coverFallback() => const Center(
        child: Icon(Icons.storefront_rounded, color: AppTheme.mint, size: 36),
      );
}

/// Bank Beneficiary Display Card with Masked Account and Status
class LuxeBeneficiaryCard extends StatelessWidget {
  const LuxeBeneficiaryCard({
    super.key,
    required this.accountHolderName,
    required this.accountNumberMasked,
    required this.ifscCode,
    this.bankName,
    required this.verificationStatus,
    this.onEdit,
  });

  final String accountHolderName;
  final String accountNumberMasked;
  final String ifscCode;
  final String? bankName;
  final String verificationStatus;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final isVerified = verificationStatus == 'verified';
    final isFailed = verificationStatus == 'rejected';

    return LuxeCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppTheme.mintLight,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.account_balance_rounded,
                      color: AppTheme.forest,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    bankName ?? 'Bank Account',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                ],
              ),
              if (isVerified)
                LuxeStatusBadge.verified()
              else if (isFailed)
                LuxeStatusBadge.failed(label: 'Rejected')
              else
                LuxeStatusBadge.pending(label: 'Pending Penny-Drop'),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Account Number',
                    style: TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    accountNumberMasked,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const Text(
                    'IFSC Code',
                    style: TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    ifscCode,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Holder: $accountHolderName',
                style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
              ),
              if (onEdit != null)
                TextButton.icon(
                  onPressed: onEdit,
                  icon: const Icon(Icons.edit_outlined, size: 14),
                  label: const Text('Update'),
                  style: TextButton.styleFrom(
                    foregroundColor: AppTheme.mint,
                    padding: EdgeInsets.zero,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 2x4 Quick Category Tile
class LuxeCategoryTile extends StatelessWidget {
  const LuxeCategoryTile({
    super.key,
    required this.label,
    required this.icon,
    required this.backgroundColor,
    required this.iconColor,
    this.onTap,
  });

  final String label;
  final IconData icon;
  final Color backgroundColor;
  final Color iconColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              color: backgroundColor,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(icon, color: iconColor, size: 26),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: AppTheme.textPrimary,
              height: 1.2,
            ),
          ),
        ],
      ),
    );
  }
}
