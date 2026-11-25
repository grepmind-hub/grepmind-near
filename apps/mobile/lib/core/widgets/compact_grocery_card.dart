import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:grepmind_mobile/core/network/api_client.dart';
import 'package:grepmind_mobile/core/theme/app_theme.dart';

/// Compact grocery product card for 2-column quick-commerce grids (inspired by Blinkit & Zepto).
/// Features 18-20dp rounded corners, pure white surface, high-contrast imagery, unit labels,
/// and an inline quantity stepper with ≥48dp touch targets.
class CompactGroceryCard extends StatelessWidget {
  const CompactGroceryCard({
    super.key,
    required this.name,
    required this.unit,
    required this.priceMinor,
    this.mrpMinor,
    this.imageUrl,
    this.quantityInCart = 0,
    this.inStock = true,
    this.badgeText,
    this.onTap,
    this.onAdd,
    this.onIncrement,
    this.onDecrement,
  });

  final String name;
  final String unit;
  final int priceMinor;
  final int? mrpMinor;
  final String? imageUrl;
  final int quantityInCart;
  final bool inStock;
  final String? badgeText;
  final VoidCallback? onTap;
  final VoidCallback? onAdd;
  final VoidCallback? onIncrement;
  final VoidCallback? onDecrement;

  String _formatPrice(int minor) => '₹${(minor / 100).toStringAsFixed(0)}';

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.brandBorder),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A17352C),
            blurRadius: 6,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Product Image Area with optional Discount Badge
                Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        height: 110,
                        width: double.infinity,
                        color: AppTheme.brandCanvas,
                        child: imageUrl != null && imageUrl!.isNotEmpty
                            ? CachedNetworkImage(
                                imageUrl: apiClient.resolveMediaUrl(imageUrl!),
                                fit: BoxFit.contain,
                                placeholder: (_, _) => const Center(
                                  child: SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  ),
                                ),
                                errorWidget: (_, _, _) => const Icon(
                                  Icons.eco_rounded,
                                  size: 40,
                                  color: AppTheme.brandMint,
                                ),
                              )
                            : const Icon(
                                Icons.eco_rounded,
                                size: 40,
                                color: AppTheme.brandMint,
                              ),
                      ),
                    ),
                    if (badgeText != null && badgeText!.isNotEmpty)
                      Positioned(
                        top: 6,
                        left: 6,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: AppTheme.emerald,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            badgeText!,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),

                // Product Name
                Text(
                  name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.brandText,
                    height: 1.25,
                  ),
                ),
                const SizedBox(height: 3),

                // Unit / Pack Size
                Text(
                  unit,
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppTheme.brandTextMuted,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const Spacer(),

                // Price and Quantity Stepper Row
                Row(
                  children: [
                    // Price display
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _formatPrice(priceMinor),
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.brandText,
                            ),
                          ),
                          if (mrpMinor != null && mrpMinor! > priceMinor)
                            Text(
                              _formatPrice(mrpMinor!),
                              style: const TextStyle(
                                fontSize: 11,
                                decoration: TextDecoration.lineThrough,
                                color: AppTheme.brandTextMuted,
                              ),
                            ),
                        ],
                      ),
                    ),

                    // Stepper / Add button
                    if (!inStock)
                      const Text(
                        'Out of stock',
                        style: TextStyle(
                          color: AppTheme.error,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      )
                    else if (quantityInCart <= 0)
                      _buildAddButton()
                    else
                      _buildStepper(),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAddButton() {
    return InkWell(
      onTap: onAdd,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
        alignment: Alignment.center,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppTheme.emerald, width: 1.5),
            boxShadow: const [
              BoxShadow(
                color: Color(0x0A059669),
                blurRadius: 4,
                offset: Offset(0, 1),
              ),
            ],
          ),
          child: const Text(
            'ADD',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppTheme.emerald,
              letterSpacing: 0.2,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStepper() {
    return Container(
      constraints: const BoxConstraints(minHeight: 48),
      alignment: Alignment.center,
      child: Container(
        decoration: BoxDecoration(
          color: AppTheme.emerald,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            InkWell(
              onTap: onDecrement,
              borderRadius: const BorderRadius.horizontal(
                left: Radius.circular(8),
              ),
              child: const SizedBox(
                width: 28,
                height: 32,
                child: Icon(Icons.remove, size: 16, color: Colors.white),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                '$quantityInCart',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
            ),
            InkWell(
              onTap: onIncrement,
              borderRadius: const BorderRadius.horizontal(
                right: Radius.circular(8),
              ),
              child: const SizedBox(
                width: 28,
                height: 32,
                child: Icon(Icons.add, size: 16, color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
