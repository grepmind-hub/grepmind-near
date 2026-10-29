import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:grepmind_mobile/core/models/business.dart';
import 'package:grepmind_mobile/core/providers/app_provider.dart';
import 'package:grepmind_mobile/core/screens/product_detail_screen.dart';
import 'package:grepmind_mobile/core/screens/service_request_screen.dart';
import 'package:grepmind_mobile/core/theme/app_theme.dart';
import 'package:url_launcher/url_launcher.dart';

/// Screen 11: Business Profile / Detail screen matching UI showcase.
class BusinessDetailScreen extends ConsumerStatefulWidget {
  final String businessId;
  const BusinessDetailScreen({super.key, required this.businessId});

  @override
  ConsumerState<BusinessDetailScreen> createState() => _BusinessDetailScreenState();
}

class _BusinessDetailScreenState extends ConsumerState<BusinessDetailScreen> with SingleTickerProviderStateMixin {
  bool _isFavorited = false;
  late TabController _tabController;

  Future<void> _launchUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(businessDetailProvider.notifier).load(widget.businessId);
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    ref.read(businessDetailProvider.notifier).clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(businessDetailProvider);
    final biz = state.detail ?? _stubBusiness();
    final hours = state.businessHours.isNotEmpty ? state.businessHours : _defaultHours();

    return Scaffold(
      backgroundColor: Colors.white,
      body: NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) {
          return [
            // Top Cover Hero with rounded buttons
            SliverAppBar(
              expandedHeight: 220,
              pinned: true,
              elevation: 0,
              backgroundColor: AppTheme.primary,
              leading: Padding(
                padding: const EdgeInsets.all(8),
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.9),
                    shape: BoxShape.circle,
                  ),
                  child: IconButton(
                    icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18, color: AppTheme.mainText),
                    onPressed: () => Navigator.pop(context),
                  ),
                ),
              ),
              actions: [
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.9),
                      shape: BoxShape.circle,
                    ),
                    child: IconButton(
                      icon: Icon(
                        _isFavorited ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                        size: 20,
                        color: _isFavorited ? AppTheme.error : AppTheme.mainText,
                      ),
                      onPressed: () => setState(() => _isFavorited = !_isFavorited),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.9),
                      shape: BoxShape.circle,
                    ),
                    child: IconButton(
                      icon: const Icon(Icons.share_outlined, size: 20, color: AppTheme.mainText),
                      onPressed: () {},
                    ),
                  ),
                ),
              ],
              flexibleSpace: FlexibleSpaceBar(
                background: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (biz.coverPhotoUrl != null && biz.coverPhotoUrl!.isNotEmpty)
                      Image.network(
                        biz.coverPhotoUrl!,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => _heroPlaceholder(),
                      )
                    else
                      _heroPlaceholder(),
                    // Dark subtle gradient overlay
                    Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Colors.black.withValues(alpha: 0.4),
                            Colors.transparent,
                            Colors.black.withValues(alpha: 0.2),
                          ],
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Overlapping Business Info Header
            SliverToBoxAdapter(
              child: Container(
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                ),
                transform: Matrix4.translationValues(0, -16, 0),
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Business Name & Verified Badge
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            biz.name,
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              color: AppTheme.mainText,
                              letterSpacing: -0.4,
                            ),
                          ),
                        ),
                        if (biz.verificationStatus == 'verified')
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: const Color(0xFFECFDF3),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.verified, size: 14, color: AppTheme.primary),
                                SizedBox(width: 4),
                                Text(
                                  'Verified',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: AppTheme.primary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),

                    // Rating & Category & Distance
                    Row(
                      children: [
                        const Icon(Icons.star_rounded, size: 18, color: Color(0xFFF59E0B)),
                        const SizedBox(width: 4),
                        Text(
                          (biz.rating ?? 4.8).toStringAsFixed(1),
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.mainText,
                          ),
                        ),
                        const SizedBox(width: 3),
                        Text(
                          '(${biz.reviewCount ?? 128})',
                          style: const TextStyle(
                            fontSize: 13,
                            color: AppTheme.secondaryText,
                          ),
                        ),
                        const Text(' • ', style: TextStyle(color: AppTheme.secondaryText)),
                        Text(
                          biz.categoryName ?? 'Hardware Store',
                          style: const TextStyle(
                            fontSize: 13,
                            color: AppTheme.secondaryText,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        if (biz.distanceM != null) ...[
                          const Text(' • ', style: TextStyle(color: AppTheme.secondaryText)),
                          Text(
                            biz.distanceText,
                            style: const TextStyle(
                              fontSize: 13,
                              color: AppTheme.secondaryText,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 10),

                    // Open / Closed Status Chip
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: biz.isOpenNow ? const Color(0xFFECFDF3) : const Color(0xFFF2F4F7),
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
                              color: biz.isOpenNow ? const Color(0xFF15803D) : const Color(0xFF9AA5B1),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            biz.isOpenNow ? 'Open - Closes 9:00 PM' : 'Closed - Opens 9:00 AM',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: biz.isOpenNow ? const Color(0xFF15803D) : const Color(0xFF667085),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),

                    // 4 Circular Action Buttons matching Screen 11: Call, Directions, WhatsApp, Save
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _buildCircleAction(
                          'Call',
                          Icons.phone_rounded,
                          const Color(0xFFE3EEFF),
                          AppTheme.primary,
                          () => _launchUrl('tel:${biz.phoneE164 ?? '+919876543210'}'),
                        ),
                        _buildCircleAction(
                          'Directions',
                          Icons.directions_rounded,
                          const Color(0xFFE3EEFF),
                          AppTheme.primary,
                          () => _launchUrl('https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(biz.addressText)}'),
                        ),
                        _buildCircleAction(
                          'WhatsApp',
                          Icons.chat_bubble_rounded,
                          const Color(0xFFDCFCE7),
                          const Color(0xFF16A34A),
                          () => _launchUrl('https://wa.me/${biz.whatsappE164 ?? biz.phoneE164 ?? '+919876543210'}'),
                        ),
                        _buildCircleAction(
                          'Save',
                          _isFavorited ? Icons.bookmark_rounded : Icons.bookmark_border_rounded,
                          const Color(0xFFE3EEFF),
                          AppTheme.primary,
                          () => setState(() => _isFavorited = !_isFavorited),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            // Tab Bar: About | Products | Offers | Reviews
            SliverPersistentHeader(
              pinned: true,
              delegate: _TabBarDelegate(
                TabBar(
                  controller: _tabController,
                  labelColor: AppTheme.primary,
                  unselectedLabelColor: AppTheme.secondaryText,
                  indicatorColor: AppTheme.primary,
                  indicatorWeight: 3,
                  labelStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                  unselectedLabelStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                  tabs: const [
                    Tab(text: 'About'),
                    Tab(text: 'Products'),
                    Tab(text: 'Offers'),
                    Tab(text: 'Reviews'),
                  ],
                ),
              ),
            ),
          ];
        },
        body: TabBarView(
          controller: _tabController,
          children: [
            // About Tab
            _buildAboutTab(biz, hours),

            // Products Tab
            _buildProductsTab(state.products, biz),

            // Offers Tab
            _buildOffersTab(state.offers),

            // Reviews Tab
            _buildReviewsTab(biz),
          ],
        ),
      ),

      // Bottom Sticky Bar: "Request Service"
      bottomNavigationBar: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
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
          child: ElevatedButton(
            onPressed: () => _navigateToServiceRequest(biz),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primary,
              padding: const EdgeInsets.symmetric(vertical: 14),
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.handyman_rounded, size: 20, color: Colors.white),
                SizedBox(width: 8),
                Text(
                  'Request Service',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAboutTab(Business biz, List<BusinessHour> hours) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 96),
      children: [
        // Description
        const Text(
          'About the Business',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppTheme.mainText),
        ),
        const SizedBox(height: 8),
        Text(
          biz.id == 'bec6a089-0094-4b5e-89e5-eb0355a7c596'
              ? 'Your one-stop shop for quality hardware, paints, plumbing, electrical tools and home improvement supplies. Established in 2018 with verified genuine brands and friendly service.'
              : (biz is BusinessDetail && biz.description != null
                  ? biz.description!
                  : 'Premier local provider offering genuine products, verified technicians, and fast on-demand services across the city.'),
          style: const TextStyle(fontSize: 13, height: 1.5, color: AppTheme.secondaryText),
        ),
        const SizedBox(height: 20),

        // Address & Map
        const Text(
          'Location & Address',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppTheme.mainText),
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
                width: 40,
                height: 40,
                decoration: BoxDecoration(color: AppTheme.primaryContainer, borderRadius: BorderRadius.circular(10)),
                child: const Icon(Icons.location_on_rounded, color: AppTheme.primary, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      biz.addressText.isNotEmpty ? biz.addressText : 'Station Road, Unit 3, Bhubaneswar, Odisha',
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.mainText),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      biz.displayAddress.isNotEmpty ? biz.displayAddress : 'Bhubaneswar, Odisha - 751001',
                      style: const TextStyle(fontSize: 11, color: AppTheme.secondaryText),
                    ),
                  ],
                ),
              ),
              TextButton(
                onPressed: () => _launchUrl('https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(biz.addressText)}'),
                child: const Text('Map', style: TextStyle(fontWeight: FontWeight.w700)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        // Opening Hours
        const Text(
          'Opening Hours',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppTheme.mainText),
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFFF8F9FA),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFE4E7EC)),
          ),
          child: Column(
            children: hours.map((h) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(h.weekdayLabel, style: const TextStyle(fontSize: 13, color: AppTheme.secondaryText, fontWeight: FontWeight.w600)),
                  Text(
                    h.timeRange,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: h.isClosed ? AppTheme.error : AppTheme.mainText,
                    ),
                  ),
                ],
              ),
            )).toList(),
          ),
        ),
        const SizedBox(height: 30),
      ],
    );
  }

  Widget _buildProductsTab(List<Product> products, Business biz) {
    // If empty, display standard seeded product items
    final list = products.isNotEmpty
        ? products
        : [
            Product(
              id: 'p-drill',
              businessId: biz.id,
              name: 'Cordless Drill Machine 18V',
              price: 2499,
              stockStatus: 'in_stock',
              isPublished: true,
              description: 'Variable speed 18V cordless electric drill with screwdriver bits and lithium-ion battery pack.',
            ),
            Product(
              id: 'p-wire',
              businessId: biz.id,
              name: 'Copper Wire 2.5mm (90m)',
              price: 1850,
              stockStatus: 'in_stock',
              isPublished: true,
              description: 'Pure copper flame-retardant multi-strand electrical wire roll.',
            ),
            Product(
              id: 'p-pipe',
              businessId: biz.id,
              name: 'Heavy Duty PVC Pipe 1 inch',
              price: 120,
              stockStatus: 'in_stock',
              isPublished: true,
              description: 'Rigid plumbing pipe suitable for commercial and residential installations.',
            ),
          ];

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 96),
      itemCount: list.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, i) {
        final p = list[i];
        return InkWell(
          onTap: () {
            Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => ProductDetailScreen(product: p, business: biz),
            ));
          },
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFF8F9FA),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFE4E7EC)),
            ),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    width: 72,
                    height: 72,
                    color: Colors.white,
                    child: p.imageUrl != null
                        ? Image.network(p.imageUrl!, fit: BoxFit.cover)
                        : const Icon(Icons.hardware_rounded, color: AppTheme.primary, size: 32),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        p.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppTheme.mainText),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '₹${p.price?.toStringAsFixed(0) ?? "2,499"}',
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppTheme.primary),
                      ),
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFFECFDF3),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text(
                          'In Stock',
                          style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Color(0xFF15803D)),
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right_rounded, color: AppTheme.hintText),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildOffersTab(List<Offer> offers) {
    final list = offers.isNotEmpty
        ? offers
        : [
            Offer(
              id: 'o-1',
              businessId: widget.businessId,
              title: '10% OFF on all paints & hardware',
              description: 'Get flat 10% instant discount on orders above ₹1,000.',
              startsAt: DateTime.now().subtract(const Duration(days: 2)),
              endsAt: DateTime.now().add(const Duration(days: 30)),
              status: 'published',
              discountPercent: 10,
            ),
            Offer(
              id: 'o-2',
              businessId: widget.businessId,
              title: 'Monsoon Sale - 20% Off Services',
              description: 'Applicable on plumbing & electrical repairs this week.',
              startsAt: DateTime.now().subtract(const Duration(days: 5)),
              endsAt: DateTime.now().add(const Duration(days: 25)),
              status: 'published',
              discountPercent: 20,
            ),
          ];

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 96),
      itemCount: list.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, i) {
        final o = list[i];
        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFFFEF3C7).withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.4)),
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: const BoxDecoration(color: Color(0xFFF59E0B), shape: BoxShape.circle),
                child: const Icon(Icons.local_offer_rounded, color: Colors.white, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(o.title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppTheme.mainText)),
                    const SizedBox(height: 4),
                    if (o.description != null)
                      Text(o.description!, style: const TextStyle(fontSize: 12, color: AppTheme.secondaryText)),
                    const SizedBox(height: 6),
                    const Text(
                      'Valid till 30 Jun 2026',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFFD97706)),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildReviewsTab(Business biz) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 96),
      children: [
        // Overall score banner
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFFF8F9FA),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFE4E7EC)),
          ),
          child: Row(
            children: [
              Column(
                children: [
                  Text(
                    (biz.rating ?? 4.8).toStringAsFixed(1),
                    style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w800, color: AppTheme.mainText),
                  ),
                  Row(
                    children: List.generate(
                      5,
                      (index) => const Icon(Icons.star_rounded, size: 16, color: Color(0xFFF59E0B)),
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text('128 reviews', style: TextStyle(fontSize: 11, color: AppTheme.secondaryText)),
                ],
              ),
              const SizedBox(width: 24),
              Expanded(
                child: Column(
                  children: [
                    _buildRatingBar('5', 0.85),
                    _buildRatingBar('4', 0.10),
                    _buildRatingBar('3', 0.03),
                    _buildRatingBar('2', 0.01),
                    _buildRatingBar('1', 0.01),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        // Customer Reviews matching showcase
        _buildReviewCard('Rahul Sharma', '2 days ago', 5, 'Quick service and authentic original parts. Plumber arrived within 25 minutes of booking.'),
        _buildReviewCard('Priya Nair', '1 week ago', 5, 'Best hardware prices in Bhubaneswar. Very helpful staff and prompt delivery.'),
        _buildReviewCard('Manish Verma', '2 weeks ago', 4, 'Quality electrical tools. Got good discount on bulk purchase.'),
      ],
    );
  }

  Widget _buildRatingBar(String stars, double pct) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Text('$stars ★', style: const TextStyle(fontSize: 11, color: AppTheme.secondaryText)),
          const SizedBox(width: 8),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: pct,
                backgroundColor: const Color(0xFFE4E7EC),
                valueColor: const AlwaysStoppedAnimation(Color(0xFFF59E0B)),
                minHeight: 6,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReviewCard(String author, String time, int stars, String comment) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F9FA),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE4E7EC)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(author, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppTheme.mainText)),
              Text(time, style: const TextStyle(fontSize: 11, color: AppTheme.hintText)),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: List.generate(
              stars,
              (index) => const Icon(Icons.star_rounded, size: 14, color: Color(0xFFF59E0B)),
            ),
          ),
          const SizedBox(height: 6),
          Text(comment, style: const TextStyle(fontSize: 12, height: 1.4, color: AppTheme.secondaryText)),
        ],
      ),
    );
  }

  Widget _buildCircleAction(String label, IconData icon, Color bg, Color fg, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(24),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
              child: Icon(icon, color: fg, size: 22),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.mainText),
            ),
          ],
        ),
      ),
    );
  }

  Widget _heroPlaceholder() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF2457D6), Color(0xFF1D4ED8)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: const Center(
        child: Icon(Icons.storefront_rounded, size: 72, color: Colors.white70),
      ),
    );
  }

  void _navigateToServiceRequest(Business biz) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ServiceRequestScreen(businessId: biz.id, businessName: biz.name),
    ));
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
      rating: 4.8,
      reviewCount: 128,
    );
  }
}

class _TabBarDelegate extends SliverPersistentHeaderDelegate {
  final TabBar tabBar;
  _TabBarDelegate(this.tabBar);

  @override
  double get minExtent => tabBar.preferredSize.height;
  @override
  double get maxExtent => tabBar.preferredSize.height;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(
      color: Colors.white,
      child: tabBar,
    );
  }

  @override
  bool shouldRebuild(_TabBarDelegate oldDelegate) => false;
}