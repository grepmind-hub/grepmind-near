import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:grepmind_mobile/core/models/business.dart';
import 'package:grepmind_mobile/core/providers/app_provider.dart';
import 'package:grepmind_mobile/core/screens/service_request_screen.dart';
import 'package:grepmind_mobile/core/theme/app_theme.dart';
import 'package:grepmind_mobile/core/widgets/premium_card.dart';
import 'package:grepmind_mobile/core/widgets/status_chip.dart';
import 'package:url_launcher/url_launcher.dart';

/// Business detail screen.
class BusinessDetailScreen extends ConsumerStatefulWidget {
  final String businessId;
  const BusinessDetailScreen({super.key, required this.businessId});

  @override
  ConsumerState<BusinessDetailScreen> createState() => _BusinessDetailScreenState();
}

class _BusinessDetailScreenState extends ConsumerState<BusinessDetailScreen> {
  bool _isFavorited = false;

  Future<void> _launchUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  @override
  void initState() {
    super.initState();
    // Load business detail when screen opens
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(businessDetailProvider.notifier).load(widget.businessId);
    });
  }

  @override
  void dispose() {
    ref.read(businessDetailProvider.notifier).clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(businessDetailProvider);
    final biz = state.detail;

    if (state.isLoading && biz == null) {
      return const Scaffold(
        backgroundColor: AppTheme.background,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (state.error != null && biz == null) {
      return Scaffold(
        backgroundColor: AppTheme.background,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 48, color: AppTheme.error),
              const SizedBox(height: 16),
              Text(state.error!, style: const TextStyle(color: AppTheme.error)),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => ref.read(businessDetailProvider.notifier).load(widget.businessId),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    // Use stub if no data (fallback)
    final displayBiz = biz ?? _stubBusiness();
    final hours = state.businessHours.isNotEmpty ? state.businessHours : _defaultHours();

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: CustomScrollView(
        slivers: [
          // Cover photo + identity.
          SliverAppBar(
            expandedHeight: 220,
            pinned: true,
            leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => Navigator.pop(context)),
            actions: [
              IconButton(icon: const Icon(Icons.share_outlined), onPressed: () {}),
              IconButton(
                icon: Icon(_isFavorited ? Icons.favorite : Icons.favorite_border, color: AppTheme.error),
                onPressed: () => setState(() => _isFavorited = !_isFavorited),
              ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: Stack(
                children: [
                  Container(color: AppTheme.surfaceVariant),
                  Positioned.fill(
                    child: displayBiz.coverPhotoUrl != null
                        ? Image.network(displayBiz.coverPhotoUrl!, fit: BoxFit.cover)
                        : const Icon(Icons.store_outlined, size: 64, color: AppTheme.hintText),
                  ),
                  Positioned(
                    bottom: 16,
                    left: 16,
                    right: 16,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            if (displayBiz.verificationStatus == 'verified')
                              const StatusChip(label: 'Verified', type: StatusChipType.success),
                            const SizedBox(width: 8),
                            StatusChip(
                              label: displayBiz.isOpenNow ? 'Open now' : 'Closed',
                              type: displayBiz.isOpenNow ? StatusChipType.success : StatusChipType.info,
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Text(
                          displayBiz.name,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            shadows: [Shadow(blurRadius: 8, color: Colors.black45)],
                          ),
                        ),
                        Text(
                          displayBiz.displayAddress,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 14,
                            shadows: [Shadow(blurRadius: 6, color: Colors.black45)],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Content.
          SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Identity & actions.
                PremiumCard(
                  margin: const EdgeInsets.fromLTRB(kScreenPadding, 12, kScreenPadding, 0),
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  displayBiz.categoryName ?? displayBiz.categorySlug,
                                  style: const TextStyle(
                                    color: AppTheme.primary,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  displayBiz.phoneE164 ?? 'Phone not listed',
                                  style: const TextStyle(
                                    color: AppTheme.secondaryText,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          Column(
                            children: [
                              _actionButton('Call', Icons.phone_outlined, () => _launchUrl('tel:${displayBiz.phoneE164 ?? ''}')),
                              const SizedBox(height: 10),
                              _actionButton('WhatsApp', Icons.message_outlined, () => _launchUrl('https://wa.me/${displayBiz.whatsappE164 ?? displayBiz.phoneE164 ?? ''}')),
                            ],
                          ),
                          const SizedBox(width: 12),
                          Column(
                            children: [
                              _actionButton('Directions', Icons.directions_outlined, () => _launchUrl('https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(displayBiz.addressText)}')),
                              const SizedBox(height: 10),
                              _actionButton('Request Service', Icons.handyman, () => _navigateToServiceRequest(displayBiz)),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                // Description.
                if (biz?.description != null && biz!.description!.isNotEmpty) ...[
                  _sectionTitle('About'),
                  PremiumCard(
                    margin: const EdgeInsets.fromLTRB(kScreenPadding, 10, kScreenPadding, 0),
                    child: Text(
                      biz.description!,
                      style: const TextStyle(color: AppTheme.mainText, fontSize: 14, height: 1.5),
                    ),
                  ),
                ],

                // Hours.
                _sectionTitle('Opening hours'),
                PremiumCard(
                  margin: const EdgeInsets.fromLTRB(kScreenPadding, 10, kScreenPadding, 0),
                  child: Column(
                    children: hours.map((h) => _HourRow(
                      day: h.weekdayLabel,
                      open: h.opensAt ?? '--:--',
                      close: h.closesAt ?? '',
                    )).toList(),
                  ),
                ),

                // Offers.
                if (state.offers.isNotEmpty) ...[
                  _sectionTitle('Offers & discounts'),
                  PremiumCard(
                    margin: const EdgeInsets.fromLTRB(kScreenPadding, 10, kScreenPadding, 0),
                    child: Column(
                      children: state.offers.map((o) => _OfferCard(offer: o)).toList(),
                    ),
                  ),
                ] else ...[
                  _sectionTitle('Offers & discounts'),
                  const PremiumCard(
                    margin: EdgeInsets.fromLTRB(kScreenPadding, 10, kScreenPadding, 0),
                    child: Text(
                      'No active offers at the moment.',
                      style: TextStyle(color: AppTheme.secondaryText, fontSize: 14),
                    ),
                  ),
                ],

                // Products.
                if (state.products.isNotEmpty) ...[
                  _sectionTitle('Products'),
                  PremiumCard(
                    margin: const EdgeInsets.fromLTRB(kScreenPadding, 10, kScreenPadding, 0),
                    child: Column(
                      children: state.products.map((p) => _ProductCard(product: p)).toList(),
                    ),
                  ),
                ] else ...[
                  _sectionTitle('Products'),
                  const PremiumCard(
                    margin: EdgeInsets.fromLTRB(kScreenPadding, 10, kScreenPadding, 0),
                    child: Text(
                      'No products listed.',
                      style: TextStyle(color: AppTheme.secondaryText, fontSize: 14),
                    ),
                  ),
                ],

                // Services.
                if (state.services.isNotEmpty) ...[
                  _sectionTitle('Services'),
                  PremiumCard(
                    margin: const EdgeInsets.fromLTRB(kScreenPadding, 10, kScreenPadding, 0),
                    child: Column(
                      children: state.services.map((s) => _ServiceCard(service: s)).toList(),
                    ),
                  ),
                ],

                const SizedBox(height: 24),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _navigateToServiceRequest(Business biz) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ServiceRequestScreen(businessId: biz.id, businessName: biz.name),
    ));
  }

  Widget _actionButton(String label, IconData icon, VoidCallback onTap) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: AppTheme.primaryContainer,
          shape: const CircleBorder(),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(24),
            child: Container(
              width: 48,
              height: 48,
              alignment: Alignment.center,
              child: Icon(icon, color: AppTheme.primary, size: 22),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppTheme.secondaryText)),
      ],
    );
  }

  Widget _sectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(kScreenPadding, 20, kScreenPadding, 8),
      child: Text(
        title,
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppTheme.mainText),
      ),
    );
  }

  List<BusinessHour> _defaultHours() {
    return [
      const BusinessHour(weekday: 1, opensAt: '9:00 AM', closesAt: '8:00 PM'),
      const BusinessHour(weekday: 2, opensAt: '9:00 AM', closesAt: '8:00 PM'),
      const BusinessHour(weekday: 3, opensAt: '9:00 AM', closesAt: '8:00 PM'),
      const BusinessHour(weekday: 4, opensAt: '9:00 AM', closesAt: '8:00 PM'),
      const BusinessHour(weekday: 5, opensAt: '9:00 AM', closesAt: '8:00 PM'),
      const BusinessHour(weekday: 6, opensAt: '10:00 AM', closesAt: '6:00 PM'),
      const BusinessHour(weekday: 0, isClosed: true),
    ];
  }

  Business _stubBusiness() {
    return Business(
      id: widget.businessId,
      name: 'Shree Hardware & Electricals',
      categorySlug: 'hardware',
      categoryName: 'Hardware',
      categoryIcon: 'build',
      addressText: 'Station Road, Unit 3, Bhubaneswar, Odisha',
      locality: 'Unit 3',
      city: 'Bhubaneswar',
      postalCode: '751001',
      status: 'approved',
      verificationStatus: 'verified',
      phoneE164: '+919876543210',
      whatsappE164: '+919876543210',
      isOpenNow: true,
      acceptsRequests: true,
      rating: 4.6,
      reviewCount: 124,
    );
  }
}

class _OfferCard extends StatelessWidget {
  final Offer offer;
  const _OfferCard({required this.offer});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.primaryContainer.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.primary.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          if (offer.imageUrl != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.network(offer.imageUrl!, width: 60, height: 60, fit: BoxFit.cover),
            )
          else
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(color: AppTheme.primaryContainer, borderRadius: BorderRadius.circular(8)),
              child: const Icon(Icons.local_offer, color: AppTheme.primary),
            ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(offer.title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.mainText)),
                    if (offer.discountPercent != null) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(color: AppTheme.error, borderRadius: BorderRadius.circular(4)),
                        child: Text('${offer.discountPercent}% OFF', style: const TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.w700)),
                      ),
                    ],
                  ],
                ),
                if (offer.description != null)
                  Text(offer.description!, style: const TextStyle(fontSize: 12, color: AppTheme.secondaryText), maxLines: 2, overflow: TextOverflow.ellipsis),
                Text('Valid: ${_formatDate(offer.startsAt)} - ${_formatDate(offer.endsAt)}', style: const TextStyle(fontSize: 11, color: AppTheme.hintText)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime dt) => '${dt.day}/${dt.month}/${dt.year}';
}

class _ProductCard extends StatelessWidget {
  final Product product;
  const _ProductCard({required this.product});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.surfaceVariant,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        children: [
          if (product.imageUrl != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.network(product.imageUrl!, width: 60, height: 60, fit: BoxFit.cover),
            )
          else
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(color: AppTheme.primaryContainer, borderRadius: BorderRadius.circular(8)),
              child: const Icon(Icons.inventory, color: AppTheme.primary),
            ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(product.name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.mainText)),
                if (product.description != null)
                  Text(product.description!, style: const TextStyle(fontSize: 12, color: AppTheme.secondaryText), maxLines: 1, overflow: TextOverflow.ellipsis),
                Text(product.priceText, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppTheme.primary)),
              ],
            ),
          ),
          Text(product.stockStatus == 'in_stock' ? 'In Stock' : 'Out of Stock',
              style: TextStyle(fontSize: 11, color: product.stockStatus == 'in_stock' ? AppTheme.success : AppTheme.error)),
        ],
      ),
    );
  }
}

class _ServiceCard extends StatelessWidget {
  final Service service;
  const _ServiceCard({required this.service});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.surfaceVariant,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.build_circle_outlined, color: AppTheme.primary, size: 20),
              const SizedBox(width: 8),
              Expanded(child: Text(service.name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.mainText))),
              Text(service.priceText, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppTheme.primary)),
            ],
          ),
          if (service.description != null) ...[
            const SizedBox(height: 8),
            Text(service.description!, style: const TextStyle(fontSize: 12, color: AppTheme.secondaryText), maxLines: 2, overflow: TextOverflow.ellipsis),
          ],
        ],
      ),
    );
  }
}

class _HourRow extends StatelessWidget {
  final String day;
  final String open;
  final String close;
  const _HourRow({required this.day, required this.open, required this.close});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(width: 55, child: Text(day, style: const TextStyle(fontSize: 14, color: AppTheme.secondaryText))),
          const SizedBox(width: 10),
          Expanded(
            child: Row(
              children: [
                Text(open, style: const TextStyle(fontSize: 14, color: AppTheme.mainText, fontWeight: FontWeight.w500)),
                const SizedBox(width: 6),
                const Text('-', style: TextStyle(fontSize: 14, color: AppTheme.hintText)),
                const SizedBox(width: 6),
                if (close.isNotEmpty)
                  Text(close, style: const TextStyle(fontSize: 14, color: AppTheme.mainText)),
                if (close.isEmpty)
                  const Text('Closed', style: TextStyle(fontSize: 14, color: AppTheme.error, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}