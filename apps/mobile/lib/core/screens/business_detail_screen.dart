import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:grepmind_mobile/core/models/business.dart';
import 'package:grepmind_mobile/core/providers/app_provider.dart';
import 'package:grepmind_mobile/core/network/api_client.dart';
import 'package:grepmind_mobile/core/screens/service_request_screen.dart';
import 'package:grepmind_mobile/core/screens/booking_scheduler_screen.dart';
import 'package:grepmind_mobile/core/providers/customer_orders_provider.dart';
import 'package:grepmind_mobile/core/providers/cart_provider.dart';
import 'package:grepmind_mobile/core/screens/customer_cart_screen.dart';
import 'package:grepmind_mobile/core/screens/checkout_review_screen.dart';
import 'package:grepmind_mobile/core/theme/app_theme.dart';
import 'package:grepmind_mobile/core/utils/contact_actions.dart';
import 'package:grepmind_mobile/core/widgets/fluid_wave_background.dart';
import 'package:grepmind_mobile/core/widgets/fluid_wave_painter.dart';
import 'package:grepmind_mobile/core/widgets/premium_network_image.dart';


part 'business_detail/business_reviews_widgets.dart';
/// Screen 11: Business Profile & Tabs matching showcase with Hospitality, Food Delivery & Table Reservation
class BusinessDetailScreen extends ConsumerStatefulWidget {
  final String businessId;
  const BusinessDetailScreen({super.key, required this.businessId});

  @override
  ConsumerState<BusinessDetailScreen> createState() =>
      _BusinessDetailScreenState();
}

class _BusinessDetailScreenState extends ConsumerState<BusinessDetailScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _profileViewRecorded = false;

  // Cart State for Food & Multi-Item Ordering
  String _selectedFoodCategory = 'All';
  bool _vegOnly = false;

  // Custom User Submitted Reviews
  final List<Map<String, dynamic>> _customReviews = [];

  // Returns only user-submitted reviews (no fake static data).
  List<Map<String, dynamic>> _getAllReviews(Business biz) {
    return List.unmodifiable(_customReviews);
  }

  void _addCustomReview(Map<String, dynamic> review) {
    setState(() {
      _customReviews.insert(0, review);
    });
  }

  Future<void> _launchUrl(String url) async {
    final uri = Uri.parse(url);
    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!launched && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No compatible app could open this link.'),
        ),
      );
    }
  }

  Future<void> _launchContact(Future<bool> Function() launch) async {
    final launched = await launch();
    if (!launched && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Contact details are unavailable for this business.'),
        ),
      );
    }
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final userId = ref.read(authProvider).user?.id;
      if (userId != null) ref.read(cartProvider.notifier).loadForUser(userId);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(businessDetailProvider.notifier).load(widget.businessId);
      ref.read(favoritesProvider.notifier).load();
    });
  }

  Future<void> _recordView(String viewType) async {
    if (ref.read(authProvider).user?.isCustomer != true) return;
    try {
      await apiClient.post(
        '/analytics/businesses/${widget.businessId}/views',
        data: {'view_type': viewType},
      );
    } catch (_) {
      // View telemetry is best-effort and must never block discovery.
    }
  }

  Future<void> _toggleFavorite(String businessId) async {
    final wasSaved = ref
        .read(favoritesProvider)
        .items
        .any((business) => business.id == businessId);
    final isSaved = await ref
        .read(favoritesProvider.notifier)
        .toggle(businessId);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          isSaved == null || isSaved == wasSaved
              ? 'Could not update saved places. Please try again.'
              : isSaved
              ? 'Business saved to your list.'
              : 'Business removed from your saved list.',
        ),
      ),
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  bool _isFoodBusiness(Business biz) {
    return biz.deliveryEnabled &&
        (biz.categorySlug == 'restaurant' || biz.categorySlug == 'cafe');
  }

  bool _isHotelBusiness(Business biz) {
    return biz.categorySlug == 'hotel' || biz.roomBookingEnabled;
  }

  Map<String, int> get _cart => {
    for (final entry in ref.read(cartProvider).lines.entries)
      entry.key: entry.value.quantity,
  };

  int get _cartItemCount => ref.read(cartProvider).itemCount;

  double _getCartTotal(List<Product> products) {
    double total = 0.0;
    for (final p in products) {
      final line = ref.read(cartProvider).lines[p.id];
      if (line != null) total += line.priceHintMinor * line.quantity / 100;
    }
    return total;
  }

  Future<void> _addToCart(Product product, Business business) async {
    final userId = ref.read(authProvider).user?.id;
    if (userId == null) return;
    final cart = ref.read(cartProvider);
    var replaceExisting = false;
    if (cart.hasLines && cart.businessId != business.id) {
      replaceExisting =
          await showDialog<bool>(
            context: context,
            builder: (dialogContext) => AlertDialog(
              title: const Text('Start a new cart?'),
              content: Text(
                'Your cart has items from ${cart.businessName ?? 'another business'}. Replace it with items from ${business.name}?',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: const Text('Keep current cart'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(dialogContext, true),
                  child: const Text('Replace cart'),
                ),
              ],
            ),
          ) ??
          false;
      if (!replaceExisting) return;
    }
    final added = await ref
        .read(cartProvider.notifier)
        .addProduct(
          userId: userId,
          businessId: business.id,
          businessName: business.name,
          product: product,
          replaceExisting: replaceExisting,
        );
    if (!added && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'This item is unavailable or the stock limit has been reached.',
          ),
        ),
      );
    }
  }

  Future<void> _removeFromCart(String productId) async {
    final quantity = ref.read(cartProvider).lines[productId]?.quantity ?? 0;
    if (quantity <= 1) return ref.read(cartProvider.notifier).remove(productId);
    await ref.read(cartProvider.notifier).setQuantity(productId, quantity - 1);
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(cartProvider);
    ref.listen<BusinessDetailState>(businessDetailProvider, (previous, next) {
      if (!_profileViewRecorded &&
          next.detail?.id == widget.businessId &&
          previous?.detail?.id != widget.businessId) {
        _profileViewRecorded = true;
        _recordView('profile');
      }
    });
    final state = ref.watch(businessDetailProvider);
    final biz = state.detail;
    if (biz == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Business')),
        body: Center(
          child: state.isLoading
              ? const CircularProgressIndicator()
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Business details are unavailable.'),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: () => ref
                          .read(businessDetailProvider.notifier)
                          .load(widget.businessId),
                      child: const Text('Try again'),
                    ),
                  ],
                ),
        ),
      );
    }
    final hours = state.businessHours;
    final products = state.products;
    final contactPhone = biz.phoneE164?.trim().isNotEmpty == true
        ? biz.phoneE164
        : null;
    final whatsappPhone = biz.whatsappE164?.trim().isNotEmpty == true
        ? biz.whatsappE164
        : contactPhone;
    final isFood = _isFoodBusiness(biz);
    final isHotel = _isHotelBusiness(biz);
    final deliveryDetails = <String>[
      if (biz.deliveryTimeMins > 0) '🛵 ${biz.deliveryTimeMins} mins',
      if (biz.minOrderAmount > 0) 'Min ₹${biz.minOrderAmount.toInt()}',
    ];
    final isFavorited = ref
        .watch(favoritesProvider)
        .items
        .any((business) => business.id == biz.id);

    return Scaffold(
      backgroundColor: AbashyakaColors.pureWhite,
      body: NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) {
          return [
            // Top Cover Hero
            SliverAppBar(
              expandedHeight: 220,
              pinned: true,
              elevation: 0,
              backgroundColor: AppTheme.primary,
              leading: Padding(
                padding: const EdgeInsets.all(8),
                child: Container(
                  decoration: BoxDecoration(
                    color: AbashyakaColors.pureWhite.withValues(alpha: 0.9),
                    shape: BoxShape.circle,
                  ),
                  child: IconButton(
                    icon: const Icon(
                      Icons.arrow_back_ios_new_rounded,
                      size: 18,
                      color: AppTheme.mainText,
                    ),
                    onPressed: () => Navigator.pop(context),
                  ),
                ),
              ),
              actions: [
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Container(
                    decoration: BoxDecoration(
                      color: AbashyakaColors.pureWhite.withValues(alpha: 0.9),
                      shape: BoxShape.circle,
                    ),
                    child: IconButton(
                      icon: Icon(
                        isFavorited
                            ? Icons.favorite_rounded
                            : Icons.favorite_border_rounded,
                        size: 20,
                        color: isFavorited ? AppTheme.error : AppTheme.mainText,
                      ),
                      onPressed: () => _toggleFavorite(biz.id),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: Container(
                    decoration: BoxDecoration(
                      color: AbashyakaColors.pureWhite.withValues(alpha: 0.9),
                      shape: BoxShape.circle,
                    ),
                    child: IconButton(
                      icon: const Icon(
                        Icons.share_outlined,
                        size: 20,
                        color: AppTheme.mainText,
                      ),
                      onPressed: () {},
                    ),
                  ),
                ),
              ],
              flexibleSpace: FlexibleSpaceBar(
                background: Stack(
                  fit: StackFit.expand,
                  children: [
                    const FluidWaveBackground(
                      variant: FluidWaveVariant.discovery,
                    ),
                    if (biz.coverPhotoUrl != null &&
                        biz.coverPhotoUrl!.isNotEmpty)
                      PremiumNetworkImage(
                        imageUrl: biz.coverPhotoUrl!,
                        errorWidget: const SizedBox.shrink(),
                      ),
                    Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Colors.black.withValues(alpha: 0.45),
                            Colors.black.withValues(alpha: 0.15),
                            Colors.black.withValues(alpha: 0.7),
                          ],
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                        ),
                      ),
                    ),
                    Positioned(
                      left: 20,
                      bottom: 28,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: AbashyakaColors.signatureTeal.withValues(alpha: 0.9),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: AbashyakaColors.pureWhite.withValues(alpha: 0.35),
                            width: 1,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.verified_user_rounded,
                              size: 14,
                              color: AbashyakaColors.pureWhite,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              biz.categoryNatureLabel.toUpperCase(),
                              style: const TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w800,
                                color: AbashyakaColors.pureWhite,
                                letterSpacing: 0.5,
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

            // Business Info Header
            SliverToBoxAdapter(
              child: Container(
                decoration: const BoxDecoration(
                  color: AbashyakaColors.pureWhite,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                ),
                transform: Matrix4.translationValues(0, -16, 0),
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Name & Verification Badge
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            biz.name,
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              color: AbashyakaColors.premiumObsidian,
                              letterSpacing: -0.4,
                            ),
                          ),
                        ),
                        if (biz.verificationStatus == 'verified')
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: AbashyakaColors.iceAquaWhite,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: AbashyakaColors.metallicTeal.withValues(alpha: 0.3),
                              ),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.verified,
                                  size: 14,
                                  color: AbashyakaColors.signatureTeal,
                                ),
                                SizedBox(width: 4),
                                Text(
                                  'Verified',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: AbashyakaColors.signatureTeal,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),

                    // Rating & Category & Distance
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 4,
                      runSpacing: 4,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.star_rounded,
                              size: 18,
                              color: AbashyakaColors.ratingStar,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              biz.rating?.toStringAsFixed(1) ?? '4.8',
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: AbashyakaColors.premiumObsidian,
                              ),
                            ),
                            const SizedBox(width: 3),
                            Text(
                              '(${biz.reviewCount ?? _customReviews.length})',
                              style: const TextStyle(
                                fontSize: 13,
                                color: AbashyakaColors.graphiteCharcoal,
                              ),
                            ),
                          ],
                        ),
                        const Text(
                          ' • ',
                          style: TextStyle(color: AbashyakaColors.graphiteCharcoal),
                        ),
                        Text(
                          biz.categoryName ??
                              (isHotel
                                  ? 'Hotels & Stays'
                                  : (isFood
                                        ? 'Restaurant & Food'
                                        : 'Local Business')),
                          style: const TextStyle(
                            fontSize: 13,
                            color: AbashyakaColors.graphiteCharcoal,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        Container(
                          margin: const EdgeInsets.only(left: 4),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: AbashyakaColors.iceAquaWhite,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            biz.categoryNatureLabel,
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: AbashyakaColors.signatureTeal,
                            ),
                          ),
                        ),
                        if (biz.distanceM != null) ...[
                          const Text(
                            ' • ',
                            style: TextStyle(color: AbashyakaColors.graphiteCharcoal),
                          ),
                          Text(
                            biz.distanceText,
                            style: const TextStyle(
                              fontSize: 13,
                              color: AbashyakaColors.graphiteCharcoal,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 10),

                    // Open / Closed & Hospitality Chips
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFECFDF3),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.circle,
                                size: 8,
                                color: AbashyakaColors.success,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                biz.isOpenNow ? 'Open now' : 'Closed now',
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: AbashyakaColors.success,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (isFood)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFEFF6FF),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: const Color(0xFFBFDBFE),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.delivery_dining_rounded,
                                  size: 14,
                                  color: AppTheme.primary,
                                ),
                                const SizedBox(width: 5),
                                Text(
                                  deliveryDetails.isEmpty
                                      ? 'Delivery available'
                                      : deliveryDetails.join(' • '),
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: AppTheme.primary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        if (isHotel)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: AbashyakaColors.successSurface,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: const Color(0xFFBBF7D0),
                              ),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.hotel_rounded,
                                  size: 14,
                                  color: AppTheme.emerald,
                                ),
                                SizedBox(width: 5),
                                Text(
                                  'Hotel services and amenities',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: AppTheme.emerald,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 18),

                    // Circular Action Buttons (Multi-color 2027 Styling)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _buildCircleAction(
                          'Call',
                          Icons.phone_rounded,
                          AbashyakaColors.iceAquaWhite,
                          AbashyakaColors.signatureTeal,
                          contactPhone != null
                              ? () => _launchContact(
                                  () => ref
                                      .read(contactActionsProvider)
                                      .call(contactPhone),
                                )
                              : () => _launchContact(() async => false),
                        ),
                        _buildCircleAction(
                          'Directions',
                          Icons.directions_rounded,
                          const Color(0xFFDFEEFF),
                          AbashyakaColors.information,
                          () => _launchUrl(
                            'https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(biz.addressText)}',
                          ),
                        ),
                        _buildCircleAction(
                          'WhatsApp',
                          Icons.chat_bubble_rounded,
                          AbashyakaColors.successSurface,
                          AbashyakaColors.success,
                          whatsappPhone != null
                              ? () => _launchContact(
                                  () => ref
                                      .read(contactActionsProvider)
                                      .whatsapp(whatsappPhone),
                                )
                              : () => _launchContact(() async => false),
                        ),
                        _buildCircleAction(
                          'Save',
                          isFavorited
                              ? Icons.bookmark_rounded
                              : Icons.bookmark_border_rounded,
                          const Color(0xFFFFF3E0),
                          isFavorited
                              ? const Color(0xFFFF8A00)
                              : AbashyakaColors.warning,
                          () => _toggleFavorite(biz.id),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            // Tab Bar: About | Menu/Rooms/Products | Offers | Reviews
            SliverPersistentHeader(
              pinned: true,
              delegate: _TabBarDelegate(
                TabBar(
                  controller: _tabController,
                  onTap: (index) {
                    if (index == 1) _recordView('catalog');
                  },
                  labelColor: AbashyakaColors.signatureTeal,
                  unselectedLabelColor: AbashyakaColors.graphiteCharcoal,
                  indicatorColor: AbashyakaColors.signatureTeal,
                  indicatorWeight: 3,
                  labelStyle: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                  unselectedLabelStyle: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                  tabs: [
                    const Tab(text: 'About'),
                    Tab(
                      key: const Key('business_catalog_tab'),
                      text: biz.catalogTabLabel,
                    ),
                    const Tab(text: 'Offers'),
                    const Tab(text: 'Reviews'),
                  ],
                ),
              ),
            ),
          ];
        },
        body: TabBarView(
          controller: _tabController,
          children: [
            _buildAboutTab(biz, hours, isFood, isHotel),
            _buildProductsOrMenuTab(products, biz, isFood, isHotel),
            _buildOffersTab(state.offers),
            _buildReviewsTab(biz),
          ],
        ),
      ),

      // Sticky Bottom Navigation with Floating Cart and Dynamic Category CTAs
      bottomNavigationBar: _buildBottomBar(biz, products, isFood, isHotel),
    );
  }

  Widget _buildBottomBar(
    Business biz,
    List<Product> products,
    bool isFood,
    bool isHotel,
  ) {
    final contactPhone = biz.phoneE164?.trim().isNotEmpty == true
        ? biz.phoneE164
        : null;
    if (ref.read(cartProvider).businessId == biz.id && _cart.isNotEmpty) {
      final total = _getCartTotal(products);
      return Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
        decoration: BoxDecoration(
          color: AbashyakaColors.pureWhite,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.12),
              blurRadius: 16,
              offset: const Offset(0, -6),
            ),
          ],
        ),
        child: SafeArea(
          child: ElevatedButton(
            onPressed: () async {
              final ready = await Navigator.of(context).push<bool>(
                MaterialPageRoute(builder: (_) => const CustomerCartScreen()),
              );
              if (ready == true && mounted) _openFoodDeliverySheet(biz);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AbashyakaColors.signatureTeal,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: AbashyakaColors.pureWhite.withValues(alpha: 0.25),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '$_cartItemCount items',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: AbashyakaColors.pureWhite,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      '₹${total.toStringAsFixed(0)}',
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                        color: AbashyakaColors.pureWhite,
                      ),
                    ),
                  ],
                ),
                const Row(
                  children: [
                    Text(
                      'View Cart & Order',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AbashyakaColors.pureWhite,
                      ),
                    ),
                    SizedBox(width: 6),
                    Icon(
                      Icons.arrow_forward_rounded,
                      size: 18,
                      color: AbashyakaColors.pureWhite,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    }

    final slug = biz.categorySlug.toLowerCase().trim().replaceAll('-', '_');
    final isTransport = slug == 'cab_auto' ||
        slug == 'transport' ||
        slug == 'cab' ||
        slug == 'auto';
    final isDoctor = slug == 'doctors' ||
        slug == 'doctor' ||
        slug == 'clinic' ||
        slug == 'hospital';
    final isBeauty =
        slug == 'beauty_salon' || slug == 'salon' || slug == 'beauty';
    final isFitness =
        slug == 'fitness_wellness' || slug == 'fitness' || slug == 'gym';
    final isEducation = slug == 'education' ||
        slug == 'coaching' ||
        slug == 'school' ||
        slug == 'college';
    final isService = biz.isServiceProvider ||
        slug == 'services' ||
        slug == 'service' ||
        slug == 'automobile' ||
        slug == 'construction' ||
        slug == 'home_painting_decor' ||
        slug == 'events_catering';

    // Dynamic Category CTAs
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AbashyakaColors.pureWhite,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 10,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        child: isFood
            ? Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _openTableReservationSheet(biz),
                      icon: const Icon(
                        Icons.table_restaurant_rounded,
                        size: 18,
                        color: AbashyakaColors.signatureTeal,
                      ),
                      label: const Text(
                        'Reserve Table',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: AbashyakaColors.signatureTeal,
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(
                          color: AbashyakaColors.signatureTeal,
                          width: 1.5,
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () {
                        _tabController.animateTo(1);
                      },
                      icon: const Icon(
                        Icons.delivery_dining_rounded,
                        size: 20,
                        color: AbashyakaColors.pureWhite,
                      ),
                      label: const Text(
                        'Order Delivery',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: AbashyakaColors.pureWhite,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AbashyakaColors.signatureTeal,
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                ],
              )
            : isHotel
                ? Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: contactPhone == null
                              ? null
                              : () => _launchContact(
                                    () => ref
                                        .read(contactActionsProvider)
                                        .call(contactPhone),
                                  ),
                          icon: const Icon(
                            Icons.phone_in_talk_rounded,
                            size: 18,
                            color: AbashyakaColors.signatureTeal,
                          ),
                          label: Text(
                            biz.contactActionLabel,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: AbashyakaColors.signatureTeal,
                            ),
                          ),
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(
                              color: AbashyakaColors.signatureTeal,
                              width: 1.5,
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 13),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: ElevatedButton.icon(
                          onPressed: products.isEmpty
                              ? null
                              : () => _openHotelRoomBookingSheet(biz, products),
                          icon: const Icon(
                            Icons.calendar_month_rounded,
                            size: 19,
                            color: AbashyakaColors.pureWhite,
                          ),
                          label: const Text(
                            'Book Stay / Room',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: AbashyakaColors.pureWhite,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AbashyakaColors.signatureTeal,
                            padding: const EdgeInsets.symmetric(vertical: 13),
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                    ],
                  )
                : isTransport
                    ? Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: contactPhone == null
                                  ? null
                                  : () => _launchContact(
                                        () => ref
                                            .read(contactActionsProvider)
                                            .call(contactPhone),
                                      ),
                              icon: const Icon(
                                Icons.phone_in_talk_rounded,
                                size: 18,
                                color: AbashyakaColors.signatureTeal,
                              ),
                              label: Text(
                                biz.contactActionLabel,
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: AbashyakaColors.signatureTeal,
                                ),
                              ),
                              style: OutlinedButton.styleFrom(
                                side: const BorderSide(
                                  color: AbashyakaColors.signatureTeal,
                                  width: 1.5,
                                ),
                                padding:
                                    const EdgeInsets.symmetric(vertical: 13),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            flex: 2,
                            child: ElevatedButton.icon(
                              key: const ValueKey('book_ride_button'),
                              onPressed: () => _openRideBookingModal(biz),
                              icon: const Icon(
                                Icons.local_taxi_rounded,
                                size: 19,
                                color: AbashyakaColors.pureWhite,
                              ),
                              label: const Text(
                                'Book Ride',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: AbashyakaColors.pureWhite,
                                ),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AbashyakaColors.signatureTeal,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 13),
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                          ),
                        ],
                      )
                    : isDoctor
                        ? Row(
                            children: [
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: contactPhone == null
                                      ? null
                                      : () => _launchContact(
                                            () => ref
                                                .read(contactActionsProvider)
                                                .call(contactPhone),
                                          ),
                                  icon: const Icon(
                                    Icons.phone_in_talk_rounded,
                                    size: 18,
                                    color: AbashyakaColors.signatureTeal,
                                  ),
                                  label: Text(
                                    biz.contactActionLabel,
                                    style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700,
                                      color: AbashyakaColors.signatureTeal,
                                    ),
                                  ),
                                  style: OutlinedButton.styleFrom(
                                    side: const BorderSide(
                                      color: AbashyakaColors.signatureTeal,
                                      width: 1.5,
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 13),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                flex: 2,
                                child: ElevatedButton.icon(
                                  key: const ValueKey('book_appointment_button'),
                                  onPressed: () =>
                                      _navigateToBookingScheduler(biz),
                                  icon: const Icon(
                                    Icons.calendar_month_rounded,
                                    size: 19,
                                    color: AbashyakaColors.pureWhite,
                                  ),
                                  label: const Text(
                                    'Book Appointment',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700,
                                      color: AbashyakaColors.pureWhite,
                                    ),
                                  ),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor:
                                        AbashyakaColors.signatureTeal,
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 13),
                                    elevation: 0,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          )
                        : (isBeauty || isFitness)
                            ? Row(
                                children: [
                                  Expanded(
                                    child: OutlinedButton.icon(
                                      onPressed: contactPhone == null
                                          ? null
                                          : () => _launchContact(
                                                () => ref
                                                    .read(
                                                        contactActionsProvider)
                                                    .call(contactPhone),
                                              ),
                                      icon: const Icon(
                                        Icons.phone_in_talk_rounded,
                                        size: 18,
                                        color: AbashyakaColors.signatureTeal,
                                      ),
                                      label: Text(
                                        biz.contactActionLabel,
                                        style: const TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w700,
                                          color: AbashyakaColors.signatureTeal,
                                        ),
                                      ),
                                      style: OutlinedButton.styleFrom(
                                        side: const BorderSide(
                                          color: AbashyakaColors.signatureTeal,
                                          width: 1.5,
                                        ),
                                        padding: const EdgeInsets.symmetric(
                                            vertical: 13),
                                        shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(12),
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    flex: 2,
                                    child: ElevatedButton.icon(
                                      onPressed: () =>
                                          _navigateToBookingScheduler(biz),
                                      icon: Icon(
                                        isBeauty
                                            ? Icons.spa_rounded
                                            : Icons.fitness_center_rounded,
                                        size: 19,
                                        color: AbashyakaColors.pureWhite,
                                      ),
                                      label: Text(
                                        biz.primaryActionLabel,
                                        style: const TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w700,
                                          color: AbashyakaColors.pureWhite,
                                        ),
                                      ),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor:
                                            AbashyakaColors.signatureTeal,
                                        padding: const EdgeInsets.symmetric(
                                            vertical: 13),
                                        elevation: 0,
                                        shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(12),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              )
                            : isService
                                ? Row(
                                    children: [
                                      Expanded(
                                        child: OutlinedButton.icon(
                                          onPressed: contactPhone == null
                                              ? null
                                              : () => _launchContact(
                                                    () => ref
                                                        .read(
                                                            contactActionsProvider)
                                                        .call(contactPhone),
                                                  ),
                                          icon: const Icon(
                                            Icons.phone_in_talk_rounded,
                                            size: 18,
                                            color:
                                                AbashyakaColors.signatureTeal,
                                          ),
                                          label: Text(
                                            biz.contactActionLabel,
                                            style: const TextStyle(
                                              fontSize: 14,
                                              fontWeight: FontWeight.w700,
                                              color:
                                                  AbashyakaColors.signatureTeal,
                                            ),
                                          ),
                                          style: OutlinedButton.styleFrom(
                                            side: const BorderSide(
                                              color:
                                                  AbashyakaColors.signatureTeal,
                                              width: 1.5,
                                            ),
                                            padding: const EdgeInsets.symmetric(
                                                vertical: 13),
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        flex: 2,
                                        child: ElevatedButton.icon(
                                          key: const ValueKey(
                                              'book_service_button'),
                                          onPressed: () =>
                                              _navigateToServiceRequest(biz),
                                          icon: const Icon(
                                            Icons.handyman_rounded,
                                            size: 19,
                                            color: AbashyakaColors.pureWhite,
                                          ),
                                          label: Text(
                                            biz.primaryActionLabel,
                                            style: const TextStyle(
                                              fontSize: 14,
                                              fontWeight: FontWeight.w700,
                                              color: AbashyakaColors.pureWhite,
                                            ),
                                          ),
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor:
                                                AbashyakaColors.signatureTeal,
                                            padding: const EdgeInsets.symmetric(
                                                vertical: 13),
                                            elevation: 0,
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  )
                                : isEducation
                                    ? Row(
                                        children: [
                                          Expanded(
                                            child: OutlinedButton.icon(
                                              onPressed: contactPhone == null
                                                  ? null
                                                  : () => _launchContact(
                                                        () => ref
                                                            .read(
                                                                contactActionsProvider)
                                                            .call(contactPhone),
                                                      ),
                                              icon: const Icon(
                                                Icons.phone_in_talk_rounded,
                                                size: 18,
                                                color: AbashyakaColors
                                                    .signatureTeal,
                                              ),
                                              label: Text(
                                                biz.contactActionLabel,
                                                style: const TextStyle(
                                                  fontSize: 14,
                                                  fontWeight: FontWeight.w700,
                                                  color: AbashyakaColors
                                                      .signatureTeal,
                                                ),
                                              ),
                                              style: OutlinedButton.styleFrom(
                                                side: const BorderSide(
                                                  color: AbashyakaColors
                                                      .signatureTeal,
                                                  width: 1.5,
                                                ),
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                        vertical: 13),
                                                shape: RoundedRectangleBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(12),
                                                ),
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            flex: 2,
                                            child: ElevatedButton.icon(
                                              onPressed: () =>
                                                  _navigateToServiceRequest(
                                                      biz),
                                              icon: const Icon(
                                                Icons.school_rounded,
                                                size: 19,
                                                color: AbashyakaColors.pureWhite,
                                              ),
                                              label: const Text(
                                                'Enquire Now',
                                                style: TextStyle(
                                                  fontSize: 14,
                                                  fontWeight: FontWeight.w700,
                                                  color: AbashyakaColors.pureWhite,
                                                ),
                                              ),
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor:
                                                    AbashyakaColors
                                                        .signatureTeal,
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                        vertical: 13),
                                                elevation: 0,
                                                shape: RoundedRectangleBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(12),
                                                ),
                                              ),
                                            ),
                                          ),
                                        ],
                                      )
                                    : Row(
                                        children: [
                                          if (contactPhone != null) ...[
                                            Expanded(
                                              child: OutlinedButton.icon(
                                                onPressed: () => _launchContact(
                                                  () => ref
                                                      .read(
                                                          contactActionsProvider)
                                                      .call(contactPhone),
                                                ),
                                                icon: const Icon(
                                                  Icons.phone_in_talk_rounded,
                                                  size: 18,
                                                  color: AbashyakaColors
                                                      .signatureTeal,
                                                ),
                                                label: Text(
                                                  biz.contactActionLabel,
                                                  style: const TextStyle(
                                                    fontSize: 14,
                                                    fontWeight: FontWeight.w700,
                                                    color: AbashyakaColors
                                                        .signatureTeal,
                                                  ),
                                                ),
                                                style: OutlinedButton.styleFrom(
                                                  side: const BorderSide(
                                                    color: AbashyakaColors
                                                        .signatureTeal,
                                                    width: 1.5,
                                                  ),
                                                  padding: const EdgeInsets
                                                      .symmetric(
                                                    vertical: 13,
                                                  ),
                                                  shape: RoundedRectangleBorder(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            12),
                                                  ),
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 12),
                                          ],
                                          Expanded(
                                            flex: 2,
                                            child: ElevatedButton.icon(
                                              onPressed: () {
                                                _tabController.animateTo(1);
                                              },
                                              icon: Icon(
                                                biz.deliveryEnabled
                                                    ? Icons
                                                        .shopping_bag_outlined
                                                    : Icons
                                                        .storefront_outlined,
                                                size: 19,
                                                color: AbashyakaColors.pureWhite,
                                              ),
                                              label: Text(
                                                biz.primaryActionLabel,
                                                style: const TextStyle(
                                                  fontSize: 14,
                                                  fontWeight: FontWeight.w700,
                                                  color: AbashyakaColors.pureWhite,
                                                ),
                                              ),
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor:
                                                    AbashyakaColors
                                                        .signatureTeal,
                                                padding: const EdgeInsets
                                                    .symmetric(vertical: 13),
                                                elevation: 0,
                                                shape: RoundedRectangleBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(12),
                                                ),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
      ),
    );
  }

  Widget _buildAboutTab(
    Business biz,
    List<BusinessHour> hours,
    bool isFood,
    bool isHotel,
  ) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 110),
      children: [
        // About Section
        const Text(
          'About the Business',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: AppTheme.mainText,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          biz.description != null && biz.description!.isNotEmpty
              ? biz.description!
              : 'Business description has not been provided.',
          style: const TextStyle(
            fontSize: 13,
            height: 1.5,
            color: AppTheme.secondaryText,
          ),
        ),
        const SizedBox(height: 20),

        // Amenities & Highlights
        if (biz.amenities.isNotEmpty || isFood || isHotel) ...[
          Text(
            isHotel
                ? 'Resort Amenities & Features'
                : (isFood
                      ? 'Dining & Kitchen Highlights'
                      : 'Features & Facilities'),
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: AppTheme.mainText,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: biz.amenities.map((amenity) {
              return Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: AbashyakaColors.successSurface,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AbashyakaColors.successSurface),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.check_circle_rounded,
                      size: 14,
                      color: AbashyakaColors.success,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      amenity,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AbashyakaColors.success,
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 20),
        ],

        // Address & Map
        const Text(
          'Location & Address',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: AppTheme.mainText,
          ),
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AbashyakaColors.pearlWhite,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AbashyakaColors.aquaSilverBorder),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppTheme.primaryContainer,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.location_on_rounded,
                  color: AppTheme.primary,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      biz.addressText.isNotEmpty
                          ? biz.addressText
                          : 'Address not provided',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.mainText,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      biz.displayAddress.isNotEmpty
                          ? biz.displayAddress
                          : 'City not provided',
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppTheme.secondaryText,
                      ),
                    ),
                  ],
                ),
              ),
              TextButton(
                onPressed: () => _launchUrl(
                  'https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(biz.addressText)}',
                ),
                child: const Text(
                  'Map',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        // Opening Hours
        const Text(
          'Operating Schedule',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: AppTheme.mainText,
          ),
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AbashyakaColors.pearlWhite,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AbashyakaColors.aquaSilverBorder),
          ),
          child: hours.isEmpty
              ? const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Operating hours have not been provided by this business.',
                    style: TextStyle(
                      fontSize: 13,
                      color: AppTheme.secondaryText,
                    ),
                  ),
                )
              : Column(children: hours.map((h) => _buildHourRow(h)).toList()),
        ),
      ],
    );
  }

  Widget _buildProductsOrMenuTab(
    List<Product> products,
    Business biz,
    bool isFood,
    bool isHotel,
  ) {
    if (isHotel) {
      return ListView.separated(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 110),
        itemCount: products.length,
        separatorBuilder: (_, _) => const SizedBox(height: 16),
        itemBuilder: (context, i) {
          final room = products[i];
          return _buildHotelRoomCard(biz, room);
        },
      );
    }

    // Food & Grocery Menu View with Course Filter Pills & Dietary Toggle
    final categories = <String>['All'];
    for (final p in products) {
      final cat = p.foodCategory ?? p.groceryCategory;
      if (cat != null && cat.isNotEmpty && !categories.contains(cat)) {
        categories.add(cat);
      }
    }

    final filtered = products.where((p) {
      final cat = p.foodCategory ?? p.groceryCategory;
      if (_selectedFoodCategory != 'All' && cat != _selectedFoodCategory) {
        return false;
      }
      if (_vegOnly && !p.isVeg) {
        return false;
      }
      return true;
    }).toList();

    return Column(
      children: [
        // Category Pills & Veg-Only Filter
        Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: const BoxDecoration(
            color: AbashyakaColors.pureWhite,
            border: Border(bottom: BorderSide(color: Color(0xFFF2F4F7))),
          ),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                // Veg Only Toggle Chip
                if (isFood) ...[
                  FilterChip(
                    avatar: Container(
                      width: 14,
                      height: 14,
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: AbashyakaColors.success,
                          width: 1.5,
                        ),
                        borderRadius: BorderRadius.circular(3),
                      ),
                      child: const Center(
                        child: CircleAvatar(
                          radius: 3,
                          backgroundColor: AbashyakaColors.success,
                        ),
                      ),
                    ),
                    label: const Text(
                      'Veg Only',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    selected: _vegOnly,
                    onSelected: (val) => setState(() => _vegOnly = val),
                    backgroundColor: AbashyakaColors.pearlWhite,
                    selectedColor: AbashyakaColors.successSurface,
                    checkmarkColor: AbashyakaColors.success,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                      side: const BorderSide(color: AbashyakaColors.aquaSilverBorder),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                ...categories.map((cat) {
                  final isSelected = _selectedFoodCategory == cat;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(cat),
                      selected: isSelected,
                      onSelected: (selected) {
                        if (selected) {
                          setState(() => _selectedFoodCategory = cat);
                        }
                      },
                      labelStyle: TextStyle(
                        fontSize: 12,
                        fontWeight: isSelected
                            ? FontWeight.w700
                            : FontWeight.w500,
                        color: isSelected ? AbashyakaColors.pureWhite : AppTheme.mainText,
                      ),
                      backgroundColor: AbashyakaColors.pearlWhite,
                      selectedColor: AppTheme.primary,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                        side: BorderSide(
                          color: isSelected
                              ? AppTheme.primary
                              : AbashyakaColors.aquaSilverBorder,
                        ),
                      ),
                    ),
                  );
                }),
              ],
            ),
          ),
        ),

        // Catalog Items List
        Expanded(
          child: filtered.isEmpty
              ? _buildEmptyCatalogState(biz)
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 110),
                  itemCount: filtered.length,
                  separatorBuilder: (_, _) =>
                      const Divider(height: 24, color: Color(0xFFF2F4F7)),
                  itemBuilder: (context, i) {
                    final item = filtered[i];
                    return _buildFoodItemRow(biz, item);
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildFoodItemRow(Business biz, Product p) {
    final qty = _cart[p.id] ?? 0;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Left Column: Dietary badge, Name, Price, Description
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Veg / Non-Veg Icon
              Row(
                children: [
                  Container(
                    width: 16,
                    height: 16,
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: p.isVeg
                            ? AbashyakaColors.success
                            : AbashyakaColors.error,
                        width: 1.5,
                      ),
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: Center(
                      child: Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: p.isVeg
                              ? AbashyakaColors.success
                              : AbashyakaColors.error,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  if ((p.foodCategory ?? p.groceryCategory) != null &&
                      (p.foodCategory ?? p.groceryCategory)!.isNotEmpty)
                    Text(
                      (p.foodCategory ?? p.groceryCategory)!,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.secondaryText,
                      ),
                    ),
                  if (p.preparationTimeMin != null &&
                      p.preparationTimeMin! > 0) ...[
                    const Text(
                      ' • ',
                      style: TextStyle(color: AppTheme.hintText),
                    ),
                    Text(
                      '⏱️ ${p.preparationTimeMin}m',
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppTheme.secondaryText,
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 6),
              Text(
                p.name,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.mainText,
                ),
              ),
              const SizedBox(height: 4),
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    p.priceText,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.mainText,
                    ),
                  ),
                  if (p.unitLabel != null && p.unitLabel!.isNotEmpty) ...[
                    const SizedBox(width: 4),
                    Text(
                      '· ${p.unitLabel}',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: AppTheme.secondaryText,
                      ),
                    ),
                  ],
                  if (p.mrp != null && p.mrp! > (p.price ?? 0)) ...[
                    const SizedBox(width: 6),
                    Text(
                      '₹${p.mrp!.round()}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppTheme.hintText,
                        decoration: TextDecoration.lineThrough,
                      ),
                    ),
                  ],
                  if (p.discountPercent != null && p.discountPercent! > 0) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 1.5,
                      ),
                      decoration: BoxDecoration(
                        color: AbashyakaColors.successSurface,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        '${p.discountPercent}% OFF',
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: AbashyakaColors.success,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              if (p.description != null && p.description!.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  p.description!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    height: 1.4,
                    color: AppTheme.secondaryText,
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(width: 16),

        // Right Column: Food Image Placeholder & Add to Cart button
        Column(
          children: [
            Container(
              width: 88,
              height: 80,
              decoration: BoxDecoration(
                color: AbashyakaColors.pearlWhite,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AbashyakaColors.aquaSilverBorder),
              ),
              child: Center(
                child: Icon(
                  p.isVeg ? Icons.eco_rounded : Icons.restaurant_rounded,
                  color: p.isVeg
                      ? AbashyakaColors.success
                      : AbashyakaColors.error,
                  size: 32,
                ),
              ),
            ),
            const SizedBox(height: 8),
            // Quantity Modifier / Add Button
            qty == 0
                ? SizedBox(
                    height: 32,
                    width: 88,
                    child: OutlinedButton(
                      onPressed: () => _addToCart(p, biz),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(
                          color: AbashyakaColors.success,
                          width: 1.5,
                        ),
                        padding: EdgeInsets.zero,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: const Text(
                        '+ ADD',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: AbashyakaColors.success,
                        ),
                      ),
                    ),
                  )
                : Container(
                    height: 32,
                    width: 88,
                    decoration: BoxDecoration(
                      color: AbashyakaColors.success,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        InkWell(
                          onTap: () => _removeFromCart(p.id),
                          child: const Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 4,
                            ),
                            child: Icon(
                              Icons.remove,
                              size: 16,
                              color: AbashyakaColors.pureWhite,
                            ),
                          ),
                        ),
                        Text(
                          '$qty',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: AbashyakaColors.pureWhite,
                          ),
                        ),
                        InkWell(
                          onTap: () => _addToCart(p, biz),
                          child: const Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 4,
                            ),
                            child: Icon(
                              Icons.add,
                              size: 16,
                              color: AbashyakaColors.pureWhite,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
          ],
        ),
      ],
    );
  }

  Widget _buildHotelRoomCard(Business biz, Product room) {
    return Container(
      decoration: BoxDecoration(
        color: AbashyakaColors.pureWhite,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AbashyakaColors.aquaSilverBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Room Header Banner
          Container(
            height: 120,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [AppTheme.emerald, AppTheme.emeraldDark],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.vertical(top: Radius.circular(15)),
            ),
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: AbashyakaColors.pureWhite.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Row(
                    children: [
                      Icon(
                        Icons.king_bed_rounded,
                        size: 14,
                        color: AbashyakaColors.pureWhite,
                      ),
                      SizedBox(width: 4),
                      Text(
                        'King Deluxe Stay',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: AbashyakaColors.pureWhite,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: AbashyakaColors.pureWhite,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    'Complimentary Breakfast',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.emerald,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  room.name,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.mainText,
                  ),
                ),
                const SizedBox(height: 6),
                if (room.description != null)
                  Text(
                    room.description!,
                    style: const TextStyle(
                      fontSize: 12,
                      height: 1.4,
                      color: AppTheme.secondaryText,
                    ),
                  ),
                const SizedBox(height: 14),
                // Price & Reserve CTA
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '₹${room.price?.toStringAsFixed(0) ?? "4,800"}',
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                            color: AppTheme.primary,
                          ),
                        ),
                        const Text(
                          '/ night + taxes',
                          style: TextStyle(
                            fontSize: 11,
                            color: AppTheme.secondaryText,
                          ),
                        ),
                      ],
                    ),
                    ElevatedButton.icon(
                      onPressed: () =>
                          _openHotelRoomBookingSheet(biz, [room], room),
                      icon: const Icon(
                        Icons.bookmark_add_rounded,
                        size: 16,
                        color: AbashyakaColors.pureWhite,
                      ),
                      label: const Text(
                        'Reserve Room',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: AbashyakaColors.pureWhite,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.emerald,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 11,
                        ),
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Phase 2C checkout: request a server quote and submit with an idempotency key.
  Future<void> _openFoodDeliverySheet(Business biz) async {
    final submitted = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) =>
            CheckoutReviewScreen(businessId: biz.id, businessName: biz.name),
      ),
    );
    if (submitted != true || !mounted) return;
    await ref
        .read(customerOrdersProvider.notifier)
        .load(userId: ref.read(currentUserProvider)?.id);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Order request received. No payment was collected.'),
      ),
    );
  }

  // --- Interactive Sheet 2: Table Reservation ---
  void _openTableReservationSheet(Business biz) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        int guests = 2;
        String selectedDate = 'Today';
        String selectedSlot = '07:30 PM (Dinner)';
        String seatingArea = 'Indoor AC Lounge';

        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Container(
              height: MediaQuery.of(context).size.height * 0.78,
              decoration: const BoxDecoration(
                color: AbashyakaColors.pureWhite,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 44,
                      height: 5,
                      decoration: BoxDecoration(
                        color: AbashyakaColors.aquaSilverBorder,
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          'Reserve a Table • ${biz.name}',
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            color: AppTheme.mainText,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                  const Divider(height: 16),
                  Expanded(
                    child: ListView(
                      children: [
                        // Number of Guests
                        const Text(
                          'Number of Guests',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.mainText,
                          ),
                        ),
                        const SizedBox(height: 8),
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [1, 2, 4, 6, 8].map((count) {
                              final isSel = guests == count;
                              return Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: ChoiceChip(
                                  label: Text(
                                    '$count ${count == 1 ? "Guest" : "Guests"}',
                                  ),
                                  selected: isSel,
                                  onSelected: (val) =>
                                      setSheetState(() => guests = count),
                                  selectedColor: AppTheme.emerald,
                                  labelStyle: TextStyle(
                                    color: isSel
                                        ? AbashyakaColors.pureWhite
                                        : AppTheme.mainText,
                                    fontWeight: isSel
                                        ? FontWeight.w700
                                        : FontWeight.w500,
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Dining Date
                        const Text(
                          'Dining Date',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.mainText,
                          ),
                        ),
                        const SizedBox(height: 8),
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children:
                                [
                                  'Today',
                                  'Tomorrow',
                                  'Fri, 30 Oct',
                                  'Sat, 31 Oct',
                                ].map((d) {
                                  final isSel = selectedDate == d;
                                  return Padding(
                                    padding: const EdgeInsets.only(right: 8),
                                    child: ChoiceChip(
                                      label: Text(d),
                                      selected: isSel,
                                      onSelected: (val) =>
                                          setSheetState(() => selectedDate = d),
                                      selectedColor: AppTheme.emerald,
                                      labelStyle: TextStyle(
                                        color: isSel
                                            ? AbashyakaColors.pureWhite
                                            : AppTheme.mainText,
                                        fontWeight: isSel
                                            ? FontWeight.w700
                                            : FontWeight.w500,
                                      ),
                                    ),
                                  );
                                }).toList(),
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Time Slot
                        const Text(
                          'Dining Time Slot',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.mainText,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children:
                              [
                                '12:30 PM (Lunch)',
                                '01:15 PM (Lunch)',
                                '07:30 PM (Dinner)',
                                '08:15 PM (Dinner)',
                                '09:00 PM (Dinner)',
                              ].map((slot) {
                                final isSel = selectedSlot == slot;
                                return ChoiceChip(
                                  label: Text(slot),
                                  selected: isSel,
                                  onSelected: (val) =>
                                      setSheetState(() => selectedSlot = slot),
                                  selectedColor: AppTheme.emerald,
                                  labelStyle: TextStyle(
                                    color: isSel
                                        ? AbashyakaColors.pureWhite
                                        : AppTheme.mainText,
                                    fontWeight: isSel
                                        ? FontWeight.w700
                                        : FontWeight.w500,
                                  ),
                                );
                              }).toList(),
                        ),
                        const SizedBox(height: 16),

                        // Seating Area
                        const Text(
                          'Seating Preference',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.mainText,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          children:
                              [
                                'Indoor AC Lounge',
                                'Rooftop Terrace',
                                'Family Garden Cabin',
                              ].map((area) {
                                final isSel = seatingArea == area;
                                return ChoiceChip(
                                  label: Text(area),
                                  selected: isSel,
                                  onSelected: (val) =>
                                      setSheetState(() => seatingArea = area),
                                  selectedColor: AppTheme.emerald,
                                  labelStyle: TextStyle(
                                    color: isSel
                                        ? AbashyakaColors.pureWhite
                                        : AppTheme.mainText,
                                    fontWeight: isSel
                                        ? FontWeight.w700
                                        : FontWeight.w500,
                                  ),
                                );
                              }).toList(),
                        ),
                      ],
                    ),
                  ),

                  // Confirm Reservation Button
                  SafeArea(
                    child: ElevatedButton(
                      onPressed: () async {
                        final reservationAt = _reservationDateTime(
                          selectedDate,
                          selectedSlot,
                        );
                        try {
                          final tableOrder = await ref
                              .read(customerOrdersProvider.notifier)
                              .createOrder(biz.id, {
                                'order_type': 'table_reservation',
                                'reservation_at': reservationAt
                                    .toUtc()
                                    .toIso8601String(),
                                'guest_count': guests,
                                'seating_area': seatingArea,
                              });
                          if (!ctx.mounted || !context.mounted) return;
                          Navigator.pop(ctx);
                          final voucher =
                              tableOrder.voucherCode ?? tableOrder.id;

                          showDialog(
                            context: context,
                            builder: (c) => AlertDialog(
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(20),
                              ),
                              content: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.table_restaurant_rounded,
                                    size: 54,
                                    color: AppTheme.emerald,
                                  ),
                                  const SizedBox(height: 12),
                                  const Text(
                                    'Table Reserved!',
                                    style: TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    '$guests Guests • $selectedDate at $selectedSlot\n$seatingArea',
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      fontSize: 13,
                                      color: AppTheme.secondaryText,
                                    ),
                                  ),
                                  const SizedBox(height: 14),
                                  Container(
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFF2F4F7),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      'Booking Reference: $voucher',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  ElevatedButton(
                                    onPressed: () => Navigator.pop(c),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: AppTheme.emerald,
                                    ),
                                    child: const Text(
                                      'Awesome, Done!',
                                      style: TextStyle(color: AbashyakaColors.pureWhite),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        } catch (error) {
                          if (!ctx.mounted) return;
                          ScaffoldMessenger.of(ctx).showSnackBar(
                            SnackBar(
                              content: Text('Reservation failed: $error'),
                            ),
                          );
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.emerald,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: const Center(
                        child: Text(
                          'Confirm Table Reservation (Zero Fee)',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: AbashyakaColors.pureWhite,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // --- Interactive Sheet 3: Hotel Room Booking ---
  void _openHotelRoomBookingSheet(
    Business biz,
    List<Product> products, [
    Product? preselectedRoom,
  ]) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        int nights = 2;
        int guests = 2;
        final room =
            preselectedRoom ?? (products.isNotEmpty ? products.first : null);
        String roomName = room?.name ?? 'Room unavailable';
        double pricePerNight = room?.price ?? 0;

        return StatefulBuilder(
          builder: (context, setSheetState) {
            final total = pricePerNight * nights;
            const tax = 0.0;
            final finalTotal = total + tax;

            return Container(
              height: MediaQuery.of(context).size.height * 0.78,
              decoration: const BoxDecoration(
                color: AbashyakaColors.pureWhite,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 44,
                      height: 5,
                      decoration: BoxDecoration(
                        color: AbashyakaColors.aquaSilverBorder,
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          'Book Stay • ${biz.name}',
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            color: AppTheme.mainText,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                  const Divider(height: 16),
                  Expanded(
                    child: ListView(
                      children: [
                        // Room Name & Banner
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFEFF6FF),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFFBFDBFE)),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.hotel_class_rounded,
                                color: AppTheme.primary,
                                size: 28,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      roomName,
                                      style: const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w800,
                                        color: AppTheme.mainText,
                                      ),
                                    ),
                                    const Text(
                                      'Complimentary Breakfast & Ocean View',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: AppTheme.secondaryText,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Stay Duration
                        const Text(
                          'Duration of Stay',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.mainText,
                          ),
                        ),
                        const SizedBox(height: 8),
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [1, 2, 3, 5].map((n) {
                              final isSel = nights == n;
                              return Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: ChoiceChip(
                                  label: Text(
                                    '$n ${n == 1 ? "Night" : "Nights"}',
                                  ),
                                  selected: isSel,
                                  onSelected: (val) =>
                                      setSheetState(() => nights = n),
                                  selectedColor: AppTheme.primary,
                                  labelStyle: TextStyle(
                                    color: isSel
                                        ? AbashyakaColors.pureWhite
                                        : AppTheme.mainText,
                                    fontWeight: isSel
                                        ? FontWeight.w700
                                        : FontWeight.w500,
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Guests
                        const Text(
                          'Guests',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.mainText,
                          ),
                        ),
                        const SizedBox(height: 8),
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [1, 2, 3, 4].map((g) {
                              final isSel = guests == g;
                              return Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: ChoiceChip(
                                  label: Text(
                                    '$g ${g == 1 ? "Adult" : "Adults"}',
                                  ),
                                  selected: isSel,
                                  onSelected: (val) =>
                                      setSheetState(() => guests = g),
                                  selectedColor: AppTheme.primary,
                                  labelStyle: TextStyle(
                                    color: isSel
                                        ? AbashyakaColors.pureWhite
                                        : AppTheme.mainText,
                                    fontWeight: isSel
                                        ? FontWeight.w700
                                        : FontWeight.w500,
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Price Breakdown
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: AbashyakaColors.pearlWhite,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: AbashyakaColors.aquaSilverBorder),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Stay Price Summary',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: AppTheme.mainText,
                                ),
                              ),
                              const SizedBox(height: 8),
                              _buildBillRow(
                                '₹${pricePerNight.toStringAsFixed(0)} x $nights Nights',
                                '₹${total.toStringAsFixed(0)}',
                              ),
                              _buildBillRow(
                                'GST & Tourism Cess (12%)',
                                '₹${tax.toStringAsFixed(0)}',
                              ),
                              const Divider(height: 16),
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text(
                                    'Total Reservation Amount',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w800,
                                      color: AppTheme.mainText,
                                    ),
                                  ),
                                  Text(
                                    '₹${finalTotal.toStringAsFixed(0)}',
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w900,
                                      color: AppTheme.primary,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Confirm Reservation CTA
                  SafeArea(
                    child: ElevatedButton(
                      onPressed: room == null
                          ? null
                          : () async {
                              try {
                                final checkIn = DateTime.now().add(
                                  const Duration(days: 1),
                                );
                                final hotelOrder = await ref
                                    .read(customerOrdersProvider.notifier)
                                    .createOrder(biz.id, {
                                      'order_type': 'hotel_booking',
                                      'reservation_at': checkIn
                                          .toUtc()
                                          .toIso8601String(),
                                      'reservation_end_at': checkIn
                                          .add(Duration(days: nights))
                                          .toUtc()
                                          .toIso8601String(),
                                      'guest_count': guests,
                                      'room_product_id': room.id,
                                    });
                                if (!ctx.mounted || !context.mounted) return;
                                Navigator.pop(ctx);
                                final voucher =
                                    hotelOrder.voucherCode ?? hotelOrder.id;
                                roomName = hotelOrder.hotelRoomName ?? roomName;

                                showDialog(
                                  context: context,
                                  builder: (c) => AlertDialog(
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    content: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(
                                          Icons.beach_access_rounded,
                                          size: 54,
                                          color: AppTheme.primary,
                                        ),
                                        const SizedBox(height: 12),
                                        const Text(
                                          'Stay Confirmed!',
                                          style: TextStyle(
                                            fontSize: 20,
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                        const SizedBox(height: 6),
                                        Text(
                                          '$roomName\n$nights Nights • $guests Guests\nPay upon check-in at hotel desk.',
                                          textAlign: TextAlign.center,
                                          style: const TextStyle(
                                            fontSize: 13,
                                            color: AppTheme.secondaryText,
                                          ),
                                        ),
                                        const SizedBox(height: 14),
                                        Container(
                                          padding: const EdgeInsets.all(10),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFEFF6FF),
                                            borderRadius: BorderRadius.circular(
                                              8,
                                            ),
                                          ),
                                          child: Text(
                                            'Voucher: $voucher',
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w800,
                                              color: AppTheme.primary,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(height: 16),
                                        ElevatedButton(
                                          onPressed: () => Navigator.pop(c),
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: AppTheme.emerald,
                                          ),
                                          child: const Text(
                                            'View Booking Receipt',
                                            style: TextStyle(
                                              color: AbashyakaColors.pureWhite,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              } catch (error) {
                                if (!ctx.mounted) return;
                                ScaffoldMessenger.of(ctx).showSnackBar(
                                  SnackBar(
                                    content: Text('Booking failed: $error'),
                                  ),
                                );
                              }
                            },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.emerald,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: Center(
                        child: Text(
                          'Confirm Room Voucher • ₹${finalTotal.toStringAsFixed(0)} (Pay at Hotel)',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: AbashyakaColors.pureWhite,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildBillRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 12, color: AppTheme.secondaryText),
          ),
          Text(
            value,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppTheme.mainText,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOffersTab(List<Offer> offers) {
    if (offers.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'No active offers are available from this business.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppTheme.secondaryText),
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 110),
      itemCount: offers.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, i) {
        final o = offers[i];
        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AbashyakaColors.warningSurface.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: AbashyakaColors.ratingStar.withValues(alpha: 0.4),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: const BoxDecoration(
                  color: AbashyakaColors.ratingStar,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.local_offer_rounded,
                  color: AbashyakaColors.pureWhite,
                  size: 24,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      o.title,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.mainText,
                      ),
                    ),
                    const SizedBox(height: 4),
                    if (o.description != null)
                      Text(
                        o.description!,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppTheme.secondaryText,
                        ),
                      ),
                    const SizedBox(height: 6),
                    Text(
                      'Valid till ${DateFormat('d MMM yyyy').format(o.endsAt.toLocal())}',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: AbashyakaColors.warning,
                      ),
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

  Widget _buildCircleAction(
    String label,
    IconData icon,
    Color bg,
    Color fg,
    VoidCallback onTap,
  ) {
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
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppTheme.mainText,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHourRow(BusinessHour h) {
    const days = [
      'Sunday',
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
    ];
    final name = days[h.weekday % 7];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            name,
            style: const TextStyle(fontSize: 12, color: AppTheme.secondaryText),
          ),
          Text(
            h.isClosed
                ? 'Closed'
                : '${_formatBusinessTime(h.opensAt)} - ${_formatBusinessTime(h.closesAt)}',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: h.isClosed ? AppTheme.error : AppTheme.mainText,
            ),
          ),
        ],
      ),
    );
  }

  String _formatBusinessTime(String? value) {
    if (value == null || value.isEmpty) return '—';
    final parsed =
        DateFormat('HH:mm:ss').tryParse(value) ??
        DateFormat('HH:mm').tryParse(value);
    return parsed == null ? value : DateFormat('h:mm a').format(parsed);
  }

  Widget _heroPlaceholder(Business biz) {
    return Image.asset(
      'assets/backgrounds/premium/role_selection_background.webp',
      fit: BoxFit.cover,
    );
  }

  void _navigateToServiceRequest(Business biz) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            ServiceRequestScreen(businessId: biz.id, businessName: biz.name),
      ),
    );
  }

  void _navigateToBookingScheduler(Business biz) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => BookingSchedulerScreen(
          business: biz,
          businessId: biz.id,
          businessName: biz.name,
        ),
      ),
    );
  }

  void _openRideBookingModal(Business biz) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          decoration: const BoxDecoration(
            color: AbashyakaColors.pureWhite,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AbashyakaColors.softGrey,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: AbashyakaColors.warningSurface,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.local_taxi_rounded,
                      color: AbashyakaColors.warning,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Book Ride · Cab & Auto',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            color: AbashyakaColors.premiumObsidian,
                          ),
                        ),
                        Text(
                          '${biz.name} • ${biz.locality}',
                          style: const TextStyle(
                            fontSize: 13,
                            color: AbashyakaColors.graphiteCharcoal,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              const Divider(height: 24, color: AbashyakaColors.softGrey),
              // Option 1: Instant Driver Call
              Material(
                type: MaterialType.transparency,
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: AbashyakaColors.iceAquaWhite,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.phone_in_talk_rounded,
                      color: AbashyakaColors.signatureTeal,
                      size: 20,
                    ),
                  ),
                  title: const Text(
                    'Call Stand / Driver Directly',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AbashyakaColors.premiumObsidian,
                    ),
                  ),
                  subtitle: Text(
                    biz.phoneE164 != null
                        ? 'Instant direct call to ${biz.phoneE164}'
                        : 'Connect with driver stand in ${biz.locality}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AbashyakaColors.graphiteCharcoal,
                    ),
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () {
                    Navigator.pop(ctx);
                    if (biz.phoneE164 != null) {
                      _launchContact(() => ref
                          .read(contactActionsProvider)
                          .call(biz.phoneE164!));
                    }
                  },
                ),
              ),
              const SizedBox(height: 8),
              // Option 2: Schedule / Request Ride
              Material(
                type: MaterialType.transparency,
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: AbashyakaColors.successSurface,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.schedule_rounded,
                      color: AbashyakaColors.success,
                      size: 20,
                    ),
                  ),
                  title: const Text(
                    'Schedule Pickup / Request Cab',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AbashyakaColors.premiumObsidian,
                    ),
                  ),
                  subtitle: const Text(
                    'Enter pickup location, destination & preferred time',
                    style: TextStyle(
                      fontSize: 12,
                      color: AbashyakaColors.graphiteCharcoal,
                    ),
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () {
                    Navigator.pop(ctx);
                    _navigateToServiceRequest(biz);
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildEmptyCatalogState(Business biz) {
    final slug = biz.categorySlug.toLowerCase().trim().replaceAll('-', '_');
    IconData icon = Icons.inventory_2_outlined;
    Color iconColor = AbashyakaColors.signatureTeal;
    String title = 'Catalog Updating';
    String message =
        'Products and stock items are being curated by the merchant.';

    if (slug == 'cab_auto' ||
        slug == 'transport' ||
        slug == 'cab' ||
        slug == 'auto') {
      icon = Icons.local_taxi_rounded;
      iconColor = AbashyakaColors.warning;
      title = 'On-Demand Rides & Fares';
      message =
          'Auto-rickshaw and cab services are active in ${biz.locality}. Tap "Book Ride" below or call the driver stand directly.';
    } else if (slug == 'doctors' ||
        slug == 'doctor' ||
        slug == 'clinic' ||
        slug == 'hospital') {
      icon = Icons.medical_services_rounded;
      iconColor = AbashyakaColors.information;
      title = 'Doctor Consultations & Care';
      message =
          'Clinic consultations and specialist appointments are active in ${biz.locality}. Tap "Book Appointment" below.';
    } else if (biz.isServiceProvider ||
        slug == 'services' ||
        slug == 'service' ||
        slug == 'automobile' ||
        slug == 'construction' ||
        slug == 'home_painting_decor') {
      icon = Icons.handyman_rounded;
      iconColor = AbashyakaColors.signatureTeal;
      title = 'Doorstep Services & Rates';
      message =
          'Verified service professionals cover ${biz.locality} and nearby areas. Tap "Book Service" below to request assistance.';
    } else if (slug == 'education' ||
        slug == 'coaching' ||
        slug == 'school' ||
        slug == 'college') {
      icon = Icons.school_rounded;
      iconColor = const Color(0xFF7C3AED);
      title = 'Courses & Batches';
      message =
          'Admissions and batch inquiries are open in ${biz.locality}. Tap "Enquire Now" or call the institute.';
    } else if (slug == 'beauty_salon' || slug == 'salon' || slug == 'beauty') {
      icon = Icons.spa_rounded;
      iconColor = const Color(0xFFDB2777);
      title = 'Salon & Grooming Slots';
      message =
          'Hair, styling, and beauty services are available in ${biz.locality}. Tap "Book Slot" below.';
    } else if (slug == 'fitness_wellness' ||
        slug == 'fitness' ||
        slug == 'gym') {
      icon = Icons.fitness_center_rounded;
      iconColor = AbashyakaColors.success;
      title = 'Fitness & Memberships';
      message =
          'Gym memberships, personal training, and wellness slots in ${biz.locality}. Tap "Join Now" below.';
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 36, color: iconColor),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: AbashyakaColors.premiumObsidian,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13,
                height: 1.5,
                color: AbashyakaColors.graphiteCharcoal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  DateTime _reservationDateTime(String dateLabel, String slotLabel) {
    final now = DateTime.now();
    final day = dateLabel == 'Tomorrow'
        ? DateTime(now.year, now.month, now.day + 1)
        : DateTime(now.year, now.month, now.day);
    final match = RegExp(r'^(\d{1,2}):(\d{2})\s*(AM|PM)').firstMatch(slotLabel);
    if (match == null) return day.add(const Duration(days: 1, hours: 12));
    var hour = int.parse(match.group(1)!);
    final minute = int.parse(match.group(2)!);
    final period = match.group(3)!;
    if (period == 'PM' && hour != 12) hour += 12;
    if (period == 'AM' && hour == 12) hour = 0;
    var result = DateTime(day.year, day.month, day.day, hour, minute);
    if (!result.isAfter(now)) result = result.add(const Duration(days: 1));
    return result;
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
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return Container(color: AbashyakaColors.pureWhite, child: tabBar);
  }

  @override
  bool shouldRebuild(_TabBarDelegate oldDelegate) => false;
}
