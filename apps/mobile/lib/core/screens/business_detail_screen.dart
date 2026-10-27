import 'package:flutter/material.dart';
import 'package:grepmind_mobile/core/models/business.dart';
import 'package:grepmind_mobile/core/theme/app_theme.dart';
import 'package:grepmind_mobile/core/widgets/premium_card.dart';
import 'package:grepmind_mobile/core/widgets/status_chip.dart';
import 'package:url_launcher/url_launcher.dart';

/// Business detail screen.
class BusinessDetailScreen extends StatefulWidget {
  final String businessId;
  const BusinessDetailScreen({super.key, required this.businessId});

  @override
  State<BusinessDetailScreen> createState() => _BusinessDetailScreenState();
}

class _BusinessDetailScreenState extends State<BusinessDetailScreen> {
  bool _isFavorited = false;

  Future<void> _launchUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Stub business detail for MVP; connect to provider in Phase 3.
    final biz = _stubBusiness();
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
                    child: biz.coverPhotoUrl != null
                        ? Image.network(biz.coverPhotoUrl!, fit: BoxFit.cover)
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
                            if (biz.verificationStatus == 'verified')
                              const StatusChip(label: 'Verified', type: StatusChipType.success, size: StatusChipSize.small),
                            const SizedBox(width: 8),
                            StatusChip(
                              label: biz.isOpenNow ? 'Open now' : 'Closed',
                              type: biz.isOpenNow ? StatusChipType.success : StatusChipType.info,
                              size: StatusChipSize.small,
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Text(
                          biz.name,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            shadows: [Shadow(blurRadius: 8, color: Colors.black45)],
                          ),
                        ),
                        Text(
                          biz.displayAddress,
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
                                  biz.categoryName ?? biz.categorySlug,
                                  style: const TextStyle(
                                    color: AppTheme.primary,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  biz.phoneE164 ?? 'Phone not listed',
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
                              _actionButton('Call', Icons.phone_outlined, () => _launchUrl('tel:${biz.phoneE164 ?? ''}')),
                              const SizedBox(height: 10),
                              _actionButton('WhatsApp', Icons.message_outlined, () => _launchUrl('https://wa.me/${biz.whatsappE164 ?? biz.phoneE164 ?? ''}')),
                            ],
                          ),
                          const SizedBox(width: 12),
                          Column(
                            children: [
                              _actionButton('Directions', Icons.directions_outlined, () => _launchUrl('https://www.google.com/maps/search/?api=1&query=${biz.addressText}')),
                              const SizedBox(height: 10),
                              _actionButton('Request Service', Icons.handyman, () {}),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                // Hours.
                _sectionTitle('Opening hours'),
                PremiumCard(
                  margin: const EdgeInsets.fromLTRB(kScreenPadding, 10, kScreenPadding, 0),
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: const [
                      _HourRow(day: 'Mon', open: '9:00 AM', close: '8:00 PM'),
                      _HourRow(day: 'Tue', open: '9:00 AM', close: '8:00 PM'),
                      _HourRow(day: 'Wed', open: '9:00 AM', close: '8:00 PM'),
                      _HourRow(day: 'Thu', open: '9:00 AM', close: '8:00 PM'),
                      _HourRow(day: 'Fri', open: '9:00 AM', close: '8:00 PM'),
                      _HourRow(day: 'Sat', open: '10:00 AM', close: '6:00 PM'),
                      _HourRow(day: 'Sun', open: 'Closed', close: ''),
                    ],
                  ),
                ),

                // Offers.
                _sectionTitle('Offers & discounts'),
                PremiumCard(
                  margin: const EdgeInsets.fromLTRB(kScreenPadding, 10, kScreenPadding, 0),
                  padding: const EdgeInsets.all(16),
                  child: const Text(
                    'No active offers at the moment.',
                    style: TextStyle(color: AppTheme.secondaryText, fontSize: 14),
                  ),
                ),

                // Products.
                _sectionTitle('Products'),
                PremiumCard(
                  margin: const EdgeInsets.fromLTRB(kScreenPadding, 10, kScreenPadding, 0),
                  padding: const EdgeInsets.all(16),
                  child: const Text(
                    'Products coming soon.',
                    style: TextStyle(color: AppTheme.secondaryText, fontSize: 14),
                  ),
                ),

                const SizedBox(height: 24),
              ],
            ),
          ),
        ],
      ),
    );
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
      coverPhotoUrl: null,
      rating: 4.6,
      reviewCount: 124,
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
                Text('-', style: const TextStyle(fontSize: 14, color: AppTheme.hintText)),
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
