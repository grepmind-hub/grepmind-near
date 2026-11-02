import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:grepmind_mobile/core/models/business.dart';
import 'package:grepmind_mobile/core/network/api_client.dart';
import 'package:grepmind_mobile/core/providers/app_provider.dart';
import 'package:grepmind_mobile/core/screens/service_request_screen.dart';
import 'package:grepmind_mobile/core/screens/order_tracking_screen.dart';
import 'package:grepmind_mobile/core/models/customer_order.dart';
import 'package:grepmind_mobile/core/providers/customer_orders_provider.dart';
import 'package:grepmind_mobile/core/theme/app_theme.dart';

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
  bool _isFavorited = false;
  late TabController _tabController;

  // Cart State for Food & Multi-Item Ordering
  final Map<String, int> _cart = {};
  String _selectedFoodCategory = 'All';
  bool _vegOnly = false;

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

  bool _isFoodBusiness(Business biz) {
    return biz.categorySlug == 'restaurant' ||
        biz.categorySlug == 'cafe' ||
        biz.deliveryEnabled;
  }

  bool _isHotelBusiness(Business biz) {
    return biz.categorySlug == 'hotel' || biz.roomBookingEnabled;
  }

  int get _cartItemCount => _cart.values.fold(0, (sum, count) => sum + count);

  double _getCartTotal(List<Product> products) {
    double total = 0.0;
    for (final p in products) {
      final qty = _cart[p.id] ?? 0;
      if (qty > 0 && p.price != null) {
        total += p.price! * qty;
      }
    }
    return total;
  }

  void _addToCart(String productId) {
    setState(() {
      _cart[productId] = (_cart[productId] ?? 0) + 1;
    });
  }

  void _removeFromCart(String productId) {
    setState(() {
      if ((_cart[productId] ?? 0) > 1) {
        _cart[productId] = _cart[productId]! - 1;
      } else {
        _cart.remove(productId);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
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
    final isFood = _isFoodBusiness(biz);
    final isHotel = _isHotelBusiness(biz);

    return Scaffold(
      backgroundColor: Colors.white,
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
                    color: Colors.white.withValues(alpha: 0.9),
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
                      color: Colors.white.withValues(alpha: 0.9),
                      shape: BoxShape.circle,
                    ),
                    child: IconButton(
                      icon: Icon(
                        _isFavorited
                            ? Icons.favorite_rounded
                            : Icons.favorite_border_rounded,
                        size: 20,
                        color: _isFavorited
                            ? AppTheme.error
                            : AppTheme.mainText,
                      ),
                      onPressed: () =>
                          setState(() => _isFavorited = !_isFavorited),
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
                    if (biz.coverPhotoUrl != null &&
                        biz.coverPhotoUrl!.isNotEmpty)
                      Image.network(
                        biz.coverPhotoUrl!,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => _heroPlaceholder(biz),
                      )
                    else
                      _heroPlaceholder(biz),
                    Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Colors.black.withValues(alpha: 0.4),
                            Colors.transparent,
                            Colors.black.withValues(alpha: 0.3),
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

            // Business Info Header
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
                              color: AppTheme.mainText,
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
                              color: const Color(0xFFECFDF3),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.verified,
                                  size: 14,
                                  color: AppTheme.primary,
                                ),
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
                        const Icon(
                          Icons.star_rounded,
                          size: 18,
                          color: Color(0xFFF59E0B),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          biz.rating?.toStringAsFixed(1) ?? 'Not rated',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.mainText,
                          ),
                        ),
                        const SizedBox(width: 3),
                        Text(
                          biz.reviewCount == null ? '' : '(${biz.reviewCount})',
                          style: const TextStyle(
                            fontSize: 13,
                            color: AppTheme.secondaryText,
                          ),
                        ),
                        const Text(
                          ' • ',
                          style: TextStyle(color: AppTheme.secondaryText),
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
                            color: AppTheme.secondaryText,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        if (biz.distanceM != null) ...[
                          const Text(
                            ' • ',
                            style: TextStyle(color: AppTheme.secondaryText),
                          ),
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
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.circle,
                                size: 8,
                                color: Color(0xFF15803D),
                              ),
                              SizedBox(width: 6),
                              Text(
                                'Open Now • Closes 10:30 PM',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF15803D),
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
                                  '🛵 ${biz.deliveryTimeMins > 0 ? biz.deliveryTimeMins : 35} mins • Min ₹${biz.minOrderAmount > 0 ? biz.minOrderAmount.toInt() : 149}',
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
                              color: const Color(0xFFF0FDF4),
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
                                  color: Color(0xFF0F766E),
                                ),
                                SizedBox(width: 5),
                                Text(
                                  'Check-in 12:00 PM • 24/7 Front Desk',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF0F766E),
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 18),

                    // Circular Action Buttons
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _buildCircleAction(
                          'Call',
                          Icons.phone_rounded,
                          const Color(0xFFE3EEFF),
                          AppTheme.primary,
                          () => _launchUrl(
                            'tel:${biz.phoneE164 ?? '+919861000008'}',
                          ),
                        ),
                        _buildCircleAction(
                          'Directions',
                          Icons.directions_rounded,
                          const Color(0xFFE3EEFF),
                          AppTheme.primary,
                          () => _launchUrl(
                            'https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(biz.addressText)}',
                          ),
                        ),
                        _buildCircleAction(
                          'WhatsApp',
                          Icons.chat_bubble_rounded,
                          const Color(0xFFDCFCE7),
                          const Color(0xFF16A34A),
                          () => _launchUrl(
                            'https://wa.me/${biz.whatsappE164 ?? biz.phoneE164 ?? '+919861000008'}',
                          ),
                        ),
                        _buildCircleAction(
                          'Save',
                          _isFavorited
                              ? Icons.bookmark_rounded
                              : Icons.bookmark_border_rounded,
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

            // Tab Bar: About | Menu/Rooms/Products | Offers | Reviews
            SliverPersistentHeader(
              pinned: true,
              delegate: _TabBarDelegate(
                TabBar(
                  controller: _tabController,
                  labelColor: AppTheme.primary,
                  unselectedLabelColor: AppTheme.secondaryText,
                  indicatorColor: AppTheme.primary,
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
                      text: isFood
                          ? 'Menu & Food'
                          : (isHotel ? 'Rooms & Stays' : 'Products'),
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
    if (_cart.isNotEmpty) {
      final total = _getCartTotal(products);
      return Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
        decoration: BoxDecoration(
          color: Colors.white,
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
            onPressed: () => _openFoodDeliverySheet(biz, products),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF15803D),
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
                        color: Colors.white.withValues(alpha: 0.25),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '$_cartItemCount items',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      '₹${total.toStringAsFixed(0)}',
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
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
                        color: Colors.white,
                      ),
                    ),
                    SizedBox(width: 6),
                    Icon(
                      Icons.arrow_forward_rounded,
                      size: 18,
                      color: Colors.white,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    }

    // Dynamic Category CTAs
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
        child: isFood
            ? Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _openTableReservationSheet(biz),
                      icon: const Icon(
                        Icons.table_restaurant_rounded,
                        size: 18,
                        color: Color(0xFF0F766E),
                      ),
                      label: const Text(
                        'Reserve Table',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF0F766E),
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(
                          color: Color(0xFF0F766E),
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
                        color: Colors.white,
                      ),
                      label: const Text(
                        'Order Delivery',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primary,
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
            : (isHotel
                  ? Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => _launchUrl(
                              'tel:${biz.phoneE164 ?? '+919861000008'}',
                            ),
                            icon: const Icon(
                              Icons.phone_in_talk_rounded,
                              size: 18,
                              color: AppTheme.primary,
                            ),
                            label: const Text(
                              'Call Desk',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: AppTheme.primary,
                              ),
                            ),
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(
                                color: AppTheme.primary,
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
                            onPressed: () => _openHotelRoomBookingSheet(biz),
                            icon: const Icon(
                              Icons.calendar_month_rounded,
                              size: 19,
                              color: Colors.white,
                            ),
                            label: const Text(
                              'Book Stay / Room',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.primary,
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
                  : ElevatedButton(
                      onPressed: () => _navigateToServiceRequest(biz),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primary,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.handyman_rounded,
                            size: 20,
                            color: Colors.white,
                          ),
                          SizedBox(width: 8),
                          Text(
                            'Request Service / Book Pro',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    )),
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
              : (isHotel
                    ? 'Business description not provided.'
                    : (isFood
                          ? 'Authentic Odia cuisine, Mughlai specialties, and tandoor delicacies with clean hygiene standards and speedy home delivery.'
                          : 'Premier local provider offering genuine products, verified technicians, and fast on-demand services across the city.')),
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
                  color: const Color(0xFFF0FDF4),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFDCFCE7)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.check_circle_rounded,
                      size: 14,
                      color: Color(0xFF16A34A),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      amenity,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF15803D),
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
            color: const Color(0xFFF8F9FA),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFE4E7EC)),
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
            color: const Color(0xFFF8F9FA),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFE4E7EC)),
          ),
          child: Column(children: hours.map((h) => _buildHourRow(h)).toList()),
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

    // Food Menu View with Course Filter Pills & Dietary Toggle
    final categories = <String>['All'];
    for (final p in products) {
      if (p.foodCategory != null &&
          p.foodCategory!.isNotEmpty &&
          !categories.contains(p.foodCategory)) {
        categories.add(p.foodCategory!);
      }
    }

    final filtered = products.where((p) {
      if (_selectedFoodCategory != 'All' &&
          p.foodCategory != _selectedFoodCategory) {
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
            color: Colors.white,
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
                          color: const Color(0xFF16A34A),
                          width: 1.5,
                        ),
                        borderRadius: BorderRadius.circular(3),
                      ),
                      child: const Center(
                        child: CircleAvatar(
                          radius: 3,
                          backgroundColor: Color(0xFF16A34A),
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
                    backgroundColor: const Color(0xFFF8F9FA),
                    selectedColor: const Color(0xFFDCFCE7),
                    checkmarkColor: const Color(0xFF16A34A),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                      side: const BorderSide(color: Color(0xFFE4E7EC)),
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
                        if (selected)
                          setState(() => _selectedFoodCategory = cat);
                      },
                      labelStyle: TextStyle(
                        fontSize: 12,
                        fontWeight: isSelected
                            ? FontWeight.w700
                            : FontWeight.w500,
                        color: isSelected ? Colors.white : AppTheme.mainText,
                      ),
                      backgroundColor: const Color(0xFFF8F9FA),
                      selectedColor: AppTheme.primary,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                        side: BorderSide(
                          color: isSelected
                              ? AppTheme.primary
                              : const Color(0xFFE4E7EC),
                        ),
                      ),
                    ),
                  );
                }),
              ],
            ),
          ),
        ),

        // Food Items List
        Expanded(
          child: filtered.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.restaurant_menu_rounded,
                        size: 48,
                        color: AppTheme.hintText,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'No items found in $_selectedFoodCategory',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.secondaryText,
                        ),
                      ),
                    ],
                  ),
                )
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
                            ? const Color(0xFF16A34A)
                            : const Color(0xFFDC2626),
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
                              ? const Color(0xFF16A34A)
                              : const Color(0xFFDC2626),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (p.foodCategory != null && p.foodCategory!.isNotEmpty)
                    Text(
                      p.foodCategory!,
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
              Text(
                p.priceText,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.mainText,
                ),
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
                color: const Color(0xFFF8F9FA),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE4E7EC)),
              ),
              child: Center(
                child: Icon(
                  p.isVeg ? Icons.eco_rounded : Icons.restaurant_rounded,
                  color: p.isVeg
                      ? const Color(0xFF16A34A)
                      : const Color(0xFFDC2626),
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
                      onPressed: () => _addToCart(p.id),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(
                          color: Color(0xFF16A34A),
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
                          color: Color(0xFF16A34A),
                        ),
                      ),
                    ),
                  )
                : Container(
                    height: 32,
                    width: 88,
                    decoration: BoxDecoration(
                      color: const Color(0xFF16A34A),
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
                              color: Colors.white,
                            ),
                          ),
                        ),
                        Text(
                          '$qty',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                        InkWell(
                          onTap: () => _addToCart(p.id),
                          child: const Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 4,
                            ),
                            child: Icon(
                              Icons.add,
                              size: 16,
                              color: Colors.white,
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
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE4E7EC)),
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
                colors: [Color(0xFF0F766E), Color(0xFF115E59)],
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
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Row(
                    children: [
                      Icon(
                        Icons.king_bed_rounded,
                        size: 14,
                        color: Colors.white,
                      ),
                      SizedBox(width: 4),
                      Text(
                        'King Deluxe Stay',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
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
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    'Complimentary Breakfast',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF0F766E),
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
                      onPressed: () => _openHotelRoomBookingSheet(biz, room),
                      icon: const Icon(
                        Icons.bookmark_add_rounded,
                        size: 16,
                        color: Colors.white,
                      ),
                      label: const Text(
                        'Reserve Room',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primary,
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

  // --- Interactive Sheet 1: Food Home Delivery & Checkout ---
  void _openFoodDeliverySheet(Business biz, List<Product> products) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        bool isDelivery = true;
        final addressController = TextEditingController(
          text: '',
        );
        final instructionsController = TextEditingController();

        return StatefulBuilder(
          builder: (context, setSheetState) {
            final cartItems = products
                .where((p) => (_cart[p.id] ?? 0) > 0)
                .toList();
            final itemTotal = _getCartTotal(products);
            final deliveryFee = isDelivery
                ? (itemTotal >= 500 ? 0.0 : 30.0)
                : 0.0;
            final taxes = 18.0;
            final grandTotal = itemTotal + deliveryFee + taxes;

            return Container(
              height: MediaQuery.of(context).size.height * 0.85,
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Grab handle & title
                  Center(
                    child: Container(
                      width: 44,
                      height: 5,
                      decoration: BoxDecoration(
                        color: const Color(0xFFE4E7EC),
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Order from ${biz.name}',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.mainText,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),

                  // Delivery Mode Toggle: Home Delivery vs Takeaway
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF2F4F7),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: InkWell(
                            onTap: () => setSheetState(() => isDelivery = true),
                            borderRadius: BorderRadius.circular(10),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              decoration: BoxDecoration(
                                color: isDelivery
                                    ? Colors.white
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(10),
                                boxShadow: isDelivery
                                    ? [
                                        BoxShadow(
                                          color: Colors.black.withValues(
                                            alpha: 0.05,
                                          ),
                                          blurRadius: 4,
                                          offset: const Offset(0, 2),
                                        ),
                                      ]
                                    : null,
                              ),
                              child: Center(
                                child: Text(
                                  '🛵 Home Delivery (35m)',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: isDelivery
                                        ? FontWeight.w800
                                        : FontWeight.w500,
                                    color: isDelivery
                                        ? AppTheme.primary
                                        : AppTheme.secondaryText,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        Expanded(
                          child: InkWell(
                            onTap: () =>
                                setSheetState(() => isDelivery = false),
                            borderRadius: BorderRadius.circular(10),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              decoration: BoxDecoration(
                                color: !isDelivery
                                    ? Colors.white
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(10),
                                boxShadow: !isDelivery
                                    ? [
                                        BoxShadow(
                                          color: Colors.black.withValues(
                                            alpha: 0.05,
                                          ),
                                          blurRadius: 4,
                                          offset: const Offset(0, 2),
                                        ),
                                      ]
                                    : null,
                              ),
                              child: Center(
                                child: Text(
                                  '🥡 Takeaway Pickup',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: !isDelivery
                                        ? FontWeight.w800
                                        : FontWeight.w500,
                                    color: !isDelivery
                                        ? AppTheme.primary
                                        : AppTheme.secondaryText,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Scrollable Cart & Address Area
                  Expanded(
                    child: ListView(
                      children: [
                        // Items List
                        const Text(
                          'Items Ordered',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.mainText,
                          ),
                        ),
                        const SizedBox(height: 8),
                        ...cartItems.map((item) {
                          final qty = _cart[item.id] ?? 0;
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            child: Row(
                              children: [
                                Icon(
                                  item.isVeg ? Icons.circle : Icons.circle,
                                  size: 10,
                                  color: item.isVeg
                                      ? const Color(0xFF16A34A)
                                      : const Color(0xFFDC2626),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    item.name,
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: AppTheme.mainText,
                                    ),
                                  ),
                                ),
                                Container(
                                  height: 28,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF2F4F7),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Row(
                                    children: [
                                      InkWell(
                                        onTap: () {
                                          _removeFromCart(item.id);
                                          setSheetState(() {});
                                          setState(() {});
                                        },
                                        child: const Icon(
                                          Icons.remove,
                                          size: 14,
                                        ),
                                      ),
                                      Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                        ),
                                        child: Text(
                                          '$qty',
                                          style: const TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ),
                                      InkWell(
                                        onTap: () {
                                          _addToCart(item.id);
                                          setSheetState(() {});
                                          setState(() {});
                                        },
                                        child: const Icon(Icons.add, size: 14),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 14),
                                Text(
                                  '₹${((item.price ?? 0) * qty).toStringAsFixed(0)}',
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: AppTheme.mainText,
                                  ),
                                ),
                              ],
                            ),
                          );
                        }),
                        const Divider(height: 24),

                        // Delivery Address Card
                        if (isDelivery) ...[
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                'Delivery Address',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: AppTheme.mainText,
                                ),
                              ),
                              TextButton(
                                onPressed: () {},
                                child: const Text(
                                  'Change',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF8F9FA),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: const Color(0xFFE4E7EC),
                              ),
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.home_rounded,
                                  color: AppTheme.primary,
                                  size: 20,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    addressController.text,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: AppTheme.mainText,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 14),
                        ],

                        // Cooking / Delivery Notes
                        const Text(
                          'Special Instructions',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.mainText,
                          ),
                        ),
                        const SizedBox(height: 6),
                        TextField(
                          controller: instructionsController,
                          decoration: InputDecoration(
                            hintText: 'e.g. Leave with guard, make it less spicy, extra tissues',
                            hintStyle: const TextStyle(
                              fontSize: 12,
                              color: AppTheme.hintText,
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: const BorderSide(
                                color: Color(0xFFE4E7EC),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Bill Details Card
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF8F9FA),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFFE4E7EC)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Bill Summary',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: AppTheme.mainText,
                                ),
                              ),
                              const SizedBox(height: 10),
                              _buildBillRow(
                                'Item Total',
                                '₹${itemTotal.toStringAsFixed(0)}',
                              ),
                              _buildBillRow(
                                'Delivery Fee',
                                deliveryFee == 0
                                    ? 'FREE'
                                    : '₹${deliveryFee.toStringAsFixed(0)}',
                              ),
                              _buildBillRow(
                                'Taxes & Restaurant Packaging',
                                '₹${taxes.toStringAsFixed(0)}',
                              ),
                              const Divider(height: 16),
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text(
                                    'To Pay',
                                    style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w800,
                                      color: AppTheme.mainText,
                                    ),
                                  ),
                                  Text(
                                    '₹${grandTotal.toStringAsFixed(0)}',
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

                  // Bottom Place Order CTA
                  SafeArea(
                    child: ElevatedButton(
                      onPressed: cartItems.isEmpty
                          ? null
                          : () async {
                              Navigator.pop(ctx);

                              final newOrderId =
                                  'GN-FD-${DateTime.now().millisecondsSinceEpoch.toString().substring(8)}';
                              final orderItems = cartItems.map((p) {
                                return CustomerOrderItem(
                                  id: p.id,
                                  name: p.name,
                                  price: p.price ?? 0.0,
                                  quantity: _cart[p.id] ?? 1,
                                  isVeg: p.isVeg,
                                  course: p.foodCategory,
                                );
                              }).toList();

                              final newOrder = CustomerOrder(
                                id: newOrderId,
                                businessId: biz.id,
                                businessName: biz.name,
                                businessLocality: biz.locality ?? biz.city ?? '',
                                businessPhone: biz.phoneE164,
                                businessCoverUrl: biz.coverPhotoUrl,
                                orderType: OrderType.foodDelivery,
                                status: OrderStatus.preparing,
                                createdAt: DateTime.now(),
                                isDelivery: isDelivery,
                                deliveryAddress: addressController.text,
                                specialInstructions:
                                    instructionsController.text.isNotEmpty
                                    ? instructionsController.text
                                    : null,
                                items: orderItems,
                                itemTotal: itemTotal,
                                deliveryFee: deliveryFee,
                                tax: taxes,
                                grandTotal: grandTotal,
                                etaMinutes: isDelivery ? 35 : 20,
                                riderName: 'Bikram Mohanty',
                                riderPhone: '+919437108922',
                                riderVehicle: 'TVS Raider 125 • OD 02 AB 4921',
                                riderRating: 4.9,
                              );

                              ref
                                  .read(customerOrdersProvider.notifier)
                                  .addOrder(newOrder);

                              // Broadcast synthetic event to Go SSE hub
                              try {
                                await apiClient.post(
                                  '/notifications/broadcast-test',
                                  data: {
                                    'business_id': biz.id,
                                    'title':
                                        'New Food Delivery Order (${isDelivery ? "Home Delivery" : "Takeaway"})',
                                    'body':
                                        'Customer Debabrata Sahu ordered $_cartItemCount items (₹${grandTotal.toStringAsFixed(0)}).',
                                    'event_type': 'service_request.created',
                                  },
                                );
                              } catch (_) {}

                              setState(() => _cart.clear());
                              _showOrderConfirmedCelebration(biz, newOrder);
                            },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF15803D),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.check_circle_rounded,
                            color: Colors.white,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Place Order • ₹${grandTotal.toStringAsFixed(0)}',
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                            ),
                          ),
                        ],
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

  void _showOrderConfirmedCelebration(Business biz, CustomerOrder order) {
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: const BoxDecoration(
                  color: Color(0xFFDCFCE7),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.restaurant_rounded,
                  color: Color(0xFF15803D),
                  size: 36,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Order Confirmed!',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.mainText,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Kitchen is preparing your food at ${biz.name}.',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 13,
                  color: AppTheme.secondaryText,
                ),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8F9FA),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Order ID',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppTheme.secondaryText,
                          ),
                        ),
                        Text(
                          order.id,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.mainText,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Estimated Time',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppTheme.secondaryText,
                          ),
                        ),
                        Text(
                          order.isDelivery
                              ? '30–35 mins'
                              : '15–20 mins (Pickup)',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF15803D),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pop(ctx);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => OrderTrackingScreen(orderId: order.id),
                      ),
                    );
                  },
                  icon: const Icon(
                    Icons.navigation_rounded,
                    size: 18,
                    color: Colors.white,
                  ),
                  label: const Text(
                    'Done & Track Order',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
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
                color: Colors.white,
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
                        color: const Color(0xFFE4E7EC),
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
                                  selectedColor: const Color(0xFF0F766E),
                                  labelStyle: TextStyle(
                                    color: isSel
                                        ? Colors.white
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
                                      selectedColor: const Color(0xFF0F766E),
                                      labelStyle: TextStyle(
                                        color: isSel
                                            ? Colors.white
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
                                  selectedColor: const Color(0xFF0F766E),
                                  labelStyle: TextStyle(
                                    color: isSel
                                        ? Colors.white
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
                                  selectedColor: const Color(0xFF0F766E),
                                  labelStyle: TextStyle(
                                    color: isSel
                                        ? Colors.white
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
                      onPressed: () {
                        Navigator.pop(ctx);

                        final voucher =
                            '#TB-GN-${(DateTime.now().millisecondsSinceEpoch.toString().substring(9))}';
                        final tableOrder = CustomerOrder(
                          id: voucher,
                          businessId: biz.id,
                          businessName: biz.name,
                          businessLocality: biz.locality ?? biz.city ?? '',
                          businessPhone: biz.phoneE164,
                          businessCoverUrl: biz.coverPhotoUrl,
                          orderType: OrderType.tableReservation,
                          status: OrderStatus.confirmed,
                          createdAt: DateTime.now(),
                          grandTotal: 0.0,
                          tableGuests: guests,
                          tableDate: selectedDate,
                          tableSlot: selectedSlot,
                          seatingArea: seatingArea,
                          voucherCode: voucher,
                        );
                        ref
                            .read(customerOrdersProvider.notifier)
                            .addOrder(tableOrder);

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
                                  color: Color(0xFF0F766E),
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
                                    backgroundColor: const Color(0xFF0F766E),
                                  ),
                                  child: const Text(
                                    'Awesome, Done!',
                                    style: TextStyle(color: Colors.white),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0F766E),
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
                            color: Colors.white,
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
  void _openHotelRoomBookingSheet(Business biz, [Product? preselectedRoom]) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        int nights = 2;
        int guests = 2;
        String roomName =
            preselectedRoom?.name ?? 'Deluxe Sea-Facing King Room';
        double pricePerNight = preselectedRoom?.price ?? 4800.0;

        return StatefulBuilder(
          builder: (context, setSheetState) {
            final total = pricePerNight * nights;
            final tax = total * 0.12;
            final finalTotal = total + tax;

            return Container(
              height: MediaQuery.of(context).size.height * 0.78,
              decoration: const BoxDecoration(
                color: Colors.white,
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
                        color: const Color(0xFFE4E7EC),
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
                                        ? Colors.white
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
                                        ? Colors.white
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
                            color: const Color(0xFFF8F9FA),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFFE4E7EC)),
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
                      onPressed: () {
                        Navigator.pop(ctx);

                        final voucher =
                            '#STAY-${(DateTime.now().millisecondsSinceEpoch.toString().substring(9))}';
                        final hotelOrder = CustomerOrder(
                          id: voucher,
                          businessId: biz.id,
                          businessName: biz.name,
                          businessLocality: biz.locality ?? biz.city ?? '',
                          businessPhone: biz.phoneE164,
                          businessCoverUrl: biz.coverPhotoUrl,
                          orderType: OrderType.hotelBooking,
                          status: OrderStatus.confirmed,
                          createdAt: DateTime.now(),
                          grandTotal: finalTotal,
                          hotelRoomName: roomName,
                          hotelNights: nights,
                          hotelGuests: guests,
                          voucherCode: voucher,
                        );
                        ref
                            .read(customerOrdersProvider.notifier)
                            .addOrder(hotelOrder);

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
                                    borderRadius: BorderRadius.circular(8),
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
                                    backgroundColor: AppTheme.primary,
                                  ),
                                  child: const Text(
                                    'View Booking Receipt',
                                    style: TextStyle(color: Colors.white),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primary,
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
                            color: Colors.white,
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
    final list = offers.isNotEmpty
        ? offers
        : [
            Offer(
              id: 'o-1',
              businessId: widget.businessId,
              title: '15% OFF on Food Orders above ₹500',
              description:
                  'Use code NEARFEAST at checkout for instant 15% discount.',
              startsAt: DateTime.now().subtract(const Duration(days: 2)),
              endsAt: DateTime.now().add(const Duration(days: 30)),
              status: 'published',
              discountPercent: 15,
            ),
            Offer(
              id: 'o-2',
              businessId: widget.businessId,
              title: 'Complimentary Dessert on Table Booking',
              description: 'Get free authentic Chhena Poda with every dinner reservation.',
              startsAt: DateTime.now().subtract(const Duration(days: 5)),
              endsAt: DateTime.now().add(const Duration(days: 25)),
              status: 'published',
              discountPercent: 20,
            ),
          ];

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 110),
      itemCount: list.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, i) {
        final o = list[i];
        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFFFEF3C7).withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: const Color(0xFFF59E0B).withValues(alpha: 0.4),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: const BoxDecoration(
                  color: Color(0xFFF59E0B),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.local_offer_rounded,
                  color: Colors.white,
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
                    const Text(
                      'Valid till 30 Jun 2026',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFFD97706),
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

  Widget _buildReviewsTab(Business biz) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 110),
      children: [
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
                    biz.rating?.toStringAsFixed(1) ?? 'Not rated',
                    style: const TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.mainText,
                    ),
                  ),
                  Row(
                    children: List.generate(
                      5,
                      (index) => const Icon(
                        Icons.star_rounded,
                        size: 16,
                        color: Color(0xFFF59E0B),
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    biz.reviewCount == null ? 'Review count unavailable' : '${biz.reviewCount} reviews',
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppTheme.secondaryText,
                    ),
                  ),
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
        _buildReviewCard(
          'Debabrata Sahu',
          '2 days ago',
          5,
          'The Biryani and Paneer Butter Masala are fantastic! Hot food arrived in 25 minutes.',
        ),
        _buildReviewCard(
          'Ananya Patnaik',
          '1 week ago',
          5,
          'Superb hospitality and clean ocean view rooms. The staff went above and beyond.',
        ),
        _buildReviewCard(
          'Rajesh Mohanty',
          '2 weeks ago',
          4,
          'Very good food and prompt service. Authentic Odia Chhena Poda dessert was rich and tasty.',
        ),
      ],
    );
  }

  Widget _buildRatingBar(String stars, double pct) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Text(
            '$stars ★',
            style: const TextStyle(fontSize: 11, color: AppTheme.secondaryText),
          ),
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

  Widget _buildReviewCard(
    String author,
    String time,
    int stars,
    String comment,
  ) {
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
              Text(
                author,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.mainText,
                ),
              ),
              Text(
                time,
                style: const TextStyle(fontSize: 11, color: AppTheme.hintText),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: List.generate(
              stars,
              (index) => const Icon(
                Icons.star_rounded,
                size: 14,
                color: Color(0xFFF59E0B),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            comment,
            style: const TextStyle(
              fontSize: 12,
              height: 1.4,
              color: AppTheme.secondaryText,
            ),
          ),
        ],
      ),
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
                : '${h.opensAt ?? "9:00 AM"} - ${h.closesAt ?? "10:00 PM"}',
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

  Widget _heroPlaceholder(Business biz) {
    final isHotel = _isHotelBusiness(biz);
    final isFood = _isFoodBusiness(biz);
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isHotel
              ? [const Color(0xFF0F766E), const Color(0xFF134E4A)]
              : (isFood
                    ? [const Color(0xFFEA580C), const Color(0xFFC2410C)]
                    : [const Color(0xFF2457D6), const Color(0xFF1D4ED8)]),
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Center(
        child: Icon(
          isHotel
              ? Icons.hotel_rounded
              : (isFood ? Icons.restaurant_rounded : Icons.storefront_rounded),
          size: 72,
          color: Colors.white70,
        ),
      ),
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
    return Container(color: Colors.white, child: tabBar);
  }

  @override
  bool shouldRebuild(_TabBarDelegate oldDelegate) => false;
}
