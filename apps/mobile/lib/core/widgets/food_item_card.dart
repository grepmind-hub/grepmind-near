import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:grepmind_mobile/core/network/api_client.dart';
import 'package:grepmind_mobile/core/theme/app_theme.dart';

/// Food item card for restaurant and dining feeds (inspired by Zomato & Swiggy).
/// Features prominent dish photography, vegetarian/non-vegetarian badging,
/// customization hints, and an inline quantity stepper with ≥48dp touch targets.
class FoodItemCard extends StatelessWidget {
  const FoodItemCard({
    super.key,
    required this.name,
    required this.priceMinor,
    this.description,
    this.imageUrl,
    this.isVeg = true,
    this.isBestseller = false,
    this.isCustomizable = false,
    this.quantityInCart = 0,
    this.inStock = true,
    this.onTap,
    this.onAdd,
    this.onIncrement,
    this.onDecrement,
  });

  final String name;
  final int priceMinor;
  final String? description;
  final String? imageUrl;
  final bool isVeg;
  final bool isBestseller;
  final bool isCustomizable;
  final int quantityInCart;
  final bool inStock;
  final VoidCallback? onTap;
  final VoidCallback? onAdd;
  final VoidCallback? onIncrement;
  final VoidCallback? onDecrement;

  String _formatPrice(int minor) => '₹${(minor / 100).toStringAsFixed(0)}';

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.brandBorder),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0817352C),
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
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Left details: Veg/Non-Veg icon, Name, Price, Description, Customization hint
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          _buildDietaryIndicator(),
                          if (isBestseller) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFEF3C7),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text(
                                '★ BESTSELLER',
                                style: TextStyle(
                                  color: Color(0xFFB45309),
                                  fontSize: 9,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.brandText,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _formatPrice(priceMinor),
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.brandText,
                        ),
                      ),
                      if (description != null && description!.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          description!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppTheme.brandTextMuted,
                            height: 1.3,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 12),

                // Right Image & Stepper column
                SizedBox(
                  width: 110,
                  child: Column(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: Container(
                          width: 110,
                          height: 95,
                          color: AppTheme.brandCanvas,
                          child: imageUrl != null && imageUrl!.isNotEmpty
                              ? CachedNetworkImage(
                                  imageUrl: apiClient.resolveMediaUrl(imageUrl!),
                                  fit: BoxFit.cover,
                                  placeholder: (_, _) => const Center(
                                    child: SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(strokeWidth: 2),
                                    ),
                                  ),
                                  errorWidget: (_, _, _) => const Icon(
                                    Icons.restaurant_rounded,
                                    size: 36,
                                    color: AppTheme.brandMint,
                                  ),
                                )
                              : const Icon(
                                  Icons.restaurant_rounded,
                                  size: 36,
                                  color: AppTheme.brandMint,
                                ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      if (!inStock)
                        const Text(
                          'Unavailable',
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
                      if (isCustomizable && inStock)
                        const Padding(
                          padding: EdgeInsets.only(top: 2),
                          child: Text(
                            'customisable',
                            style: TextStyle(
                              fontSize: 10,
                              color: AppTheme.brandTextMuted,
                            ),
                          ),
                        ),
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

  Widget _buildDietaryIndicator() {
    final color = isVeg ? const Color(0xFF16A34A) : const Color(0xFFDC2626);
    return Container(
      width: 14,
      height: 14,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        border: Border.all(color: color, width: 1.5),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Center(
        child: isVeg
            ? Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                ),
              )
            : CustomPaint(
                size: const Size(6, 6),
                painter: _TrianglePainter(color),
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
          width: 84,
          padding: const EdgeInsets.symmetric(vertical: 6),
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
          child: const Center(
            child: Text(
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
      ),
    );
  }

  Widget _buildStepper() {
    return Container(
      constraints: const BoxConstraints(minHeight: 48),
      alignment: Alignment.center,
      child: Container(
        width: 84,
        decoration: BoxDecoration(
          color: AppTheme.emerald,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            InkWell(
              onTap: onDecrement,
              borderRadius: const BorderRadius.horizontal(left: Radius.circular(8)),
              child: const SizedBox(
                width: 26,
                height: 30,
                child: Icon(Icons.remove, size: 15, color: Colors.white),
              ),
            ),
            Text(
              '$quantityInCart',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
            ),
            InkWell(
              onTap: onIncrement,
              borderRadius: const BorderRadius.horizontal(right: Radius.circular(8)),
              child: const SizedBox(
                width: 26,
                height: 30,
                child: Icon(Icons.add, size: 15, color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TrianglePainter extends CustomPainter {
  const _TrianglePainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    final path = Path()
      ..moveTo(size.width / 2, 0)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _TrianglePainter oldDelegate) => oldDelegate.color != color;
}
