import 'package:flutter/material.dart';
import 'package:grepmind_mobile/core/models/business.dart';
import 'package:grepmind_mobile/core/theme/app_theme.dart';
import 'package:url_launcher/url_launcher.dart';

/// Screen 12: Product Details screen from Grepmind Near UI showcase.
class ProductDetailScreen extends StatefulWidget {
  final Product product;
  final Business? business;

  const ProductDetailScreen({
    super.key,
    required this.product,
    this.business,
  });

  @override
  State<ProductDetailScreen> createState() => _ProductDetailScreenState();
}

class _ProductDetailScreenState extends State<ProductDetailScreen> {
  bool _isFavorited = false;

  Future<void> _makeCall(String? phone) async {
    if (phone == null || phone.isEmpty) return;
    final uri = Uri.parse('tel:$phone');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.product;
    final biz = widget.business;
    final priceStr = p.price != null ? '₹${p.price!.toStringAsFixed(0)}' : '₹2,499';
    final mrpStr = p.price != null ? '₹${(p.price! * 1.4).toStringAsFixed(0)}' : '₹3,499';

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: AppTheme.mainText, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: Icon(
              _isFavorited ? Icons.favorite_rounded : Icons.favorite_border_rounded,
              color: _isFavorited ? AppTheme.error : AppTheme.mainText,
            ),
            onPressed: () => setState(() => _isFavorited = !_isFavorited),
          ),
          IconButton(
            icon: const Icon(Icons.share_outlined, color: AppTheme.mainText),
            onPressed: () {},
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Product Hero Photo
                  Container(
                    width: double.infinity,
                    height: 260,
                    color: const Color(0xFFF8F9FA),
                    child: Center(
                      child: p.imageUrl != null && p.imageUrl!.isNotEmpty
                          ? Image.network(
                              p.imageUrl!,
                              fit: BoxFit.contain,
                              errorBuilder: (_, _, _) => _placeholder(),
                            )
                          : _placeholder(),
                    ),
                  ),

                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Title
                        Text(
                          p.name,
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            color: AppTheme.mainText,
                            letterSpacing: -0.3,
                          ),
                        ),
                        const SizedBox(height: 8),

                        // Rating row
                        Row(
                          children: [
                            Row(
                              children: List.generate(
                                5,
                                (index) => const Icon(Icons.star_rounded, size: 18, color: Color(0xFFF59E0B)),
                              ),
                            ),
                            const SizedBox(width: 8),
                            const Text(
                              '4.8 (94 reviews)',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: AppTheme.secondaryText,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),

                        // Pricing & Discount row
                        Row(
                          children: [
                            Text(
                              priceStr,
                              style: const TextStyle(
                                fontSize: 26,
                                fontWeight: FontWeight.w800,
                                color: AppTheme.mainText,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Text(
                              mrpStr,
                              style: const TextStyle(
                                fontSize: 16,
                                decoration: TextDecoration.lineThrough,
                                color: AppTheme.hintText,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: const Color(0xFFE6FFFA),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: const Color(0xFF38B2AC)),
                              ),
                              child: const Text(
                                '29% OFF',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF0F766E),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),

                        const Divider(height: 1, color: Color(0xFFE4E7EC)),
                        const SizedBox(height: 16),

                        // Features & Highlights checklist matching Screen 12
                        _buildFeatureRow(Icons.bolt_rounded, '20V Lithium-ion Power System'),
                        const SizedBox(height: 12),
                        _buildFeatureRow(Icons.verified_user_outlined, '1 Year Official Manufacturer Warranty'),
                        const SizedBox(height: 12),
                        _buildFeatureRow(Icons.local_shipping_outlined, 'Free Fast Home Delivery on orders > ₹500'),
                        const SizedBox(height: 12),
                        _buildFeatureRow(Icons.assignment_return_outlined, '7 Days Easy Replacement Policy'),

                        const SizedBox(height: 24),
                        const Divider(height: 1, color: Color(0xFFE4E7EC)),
                        const SizedBox(height: 16),

                        // Seller Store Card
                        const Text(
                          'Sold & verified by',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.secondaryText,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF8F9FA),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: const Color(0xFFE4E7EC)),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  color: AppTheme.primaryContainer,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Icon(Icons.storefront_rounded, color: AppTheme.primary, size: 24),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      biz?.name ?? 'Shree Hardware & Electricals',
                                      style: const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w700,
                                        color: AppTheme.mainText,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      biz?.displayAddress.isNotEmpty == true
                                          ? biz!.displayAddress
                                          : 'Location not provided',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: AppTheme.secondaryText,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.phone_rounded, color: AppTheme.primary),
                                onPressed: () => _makeCall(biz?.phoneE164 ?? '+919876543210'),
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 20),
                        // Description
                        const Text(
                          'Product Overview',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.mainText,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          p.description?.isNotEmpty == true
                              ? p.description!
                              : 'High performance industrial grade copper core motor. Engineered for durability with dual speed gearbox, variable speed trigger and integrated LED work light.',
                          style: const TextStyle(
                            fontSize: 13,
                            height: 1.5,
                            color: AppTheme.secondaryText,
                          ),
                        ),
                        const SizedBox(height: 96),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Bottom sticky CTA bar matching Screen 12
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.06),
                  blurRadius: 10,
                  offset: const Offset(0, -4),
                ),
              ],
            ),
            child: SafeArea(
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => _makeCall(biz?.phoneE164 ?? '+919876543210'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        side: const BorderSide(color: AppTheme.primary, width: 1.5),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.call_rounded, size: 18, color: AppTheme.primary),
                          SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              'Call Store',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: AppTheme.primary,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Order inquiry placed for ${p.name}!'),
                            backgroundColor: AppTheme.primary,
                          ),
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primary,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.bolt_rounded, size: 18, color: Colors.white),
                          SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              'Inquire / Buy',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFeatureRow(IconData icon, String text) {
    return Row(
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: const Color(0xFFF2F4F7),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 16, color: AppTheme.primary),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: AppTheme.mainText,
            ),
          ),
        ),
      ],
    );
  }

  Widget _placeholder() {
    return const Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.hardware_rounded, size: 72, color: Color(0xFF9AA5B1)),
        SizedBox(height: 8),
        Text(
          'Cordless Drill Machine 18V',
          style: TextStyle(color: Color(0xFF9AA5B1), fontSize: 13, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}
