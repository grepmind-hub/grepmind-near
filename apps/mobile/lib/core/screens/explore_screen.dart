// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:grepmind_mobile/core/network/api_client.dart';
import 'package:grepmind_mobile/core/providers/app_provider.dart';
import 'package:grepmind_mobile/core/theme/app_theme.dart';
import 'package:grepmind_mobile/core/widgets/banner_card.dart';
import 'package:grepmind_mobile/core/widgets/business_card.dart';
import 'package:grepmind_mobile/core/widgets/category_chip.dart';
import 'package:grepmind_mobile/core/widgets/premium_card.dart';
import 'package:grepmind_mobile/core/widgets/skeleton_loader.dart';
import 'package:grepmind_mobile/core/screens/business_detail_screen.dart';
import 'package:grepmind_mobile/core/screens/categories_screen.dart';
import 'package:grepmind_mobile/core/screens/search_results_screen.dart';
import 'package:grepmind_mobile/core/screens/service_pro_screen.dart';

/// Explore screen: search, categories, featured offer, nearby businesses.
class ExploreScreen extends ConsumerStatefulWidget {
  const ExploreScreen({super.key});

  @override
  ConsumerState<ExploreScreen> createState() => _ExploreScreenState();
}

class _ExploreScreenState extends ConsumerState<ExploreScreen> {
  final _searchController = TextEditingController();
  String _selectedCategory = 'all';
  bool _isSearching = false;
  final bool _isOpenNow = false;
  final bool _isAvailableNow = false;
  final String _sortBy = 'relevance';
  final int _radius = 5000; // meters

  final List<Map<String, dynamic>> _categories = const [
    {'label': 'All', 'icon': Icons.apps_rounded, 'slug': 'all', 'bg': Color(0xFFEEF2FF), 'fg': Color(0xFF4F46E5)},
    {'label': 'Shops', 'icon': Icons.storefront_rounded, 'slug': 'general', 'bg': Color(0xFFFEE2E2), 'fg': Color(0xFFEF4444)},
    {'label': 'Services', 'icon': Icons.handyman_rounded, 'slug': 'electrician', 'bg': Color(0xFFDBEAFE), 'fg': Color(0xFF2563EB)},
    {'label': 'Electronics', 'icon': Icons.devices_rounded, 'slug': 'electronics', 'bg': Color(0xFFCCFBF1), 'fg': Color(0xFF0F766E)},
    {'label': 'Fashion', 'icon': Icons.checkroom_rounded, 'slug': 'fashion', 'bg': Color(0xFFFFEDD5), 'fg': Color(0xFFEA580C)},
    {'label': 'Groceries', 'icon': Icons.local_grocery_store_rounded, 'slug': 'grocery', 'bg': Color(0xFFDCFCE7), 'fg': Color(0xFF16A34A)},
    {'label': 'Medical', 'icon': Icons.local_pharmacy_rounded, 'slug': 'medical', 'bg': Color(0xFFF3E8FF), 'fg': Color(0xFF9333EA)},
    {'label': 'Hardware', 'icon': Icons.build_rounded, 'slug': 'hardware', 'bg': Color(0xFFFEF3C7), 'fg': Color(0xFFD97706)},
    {'label': 'Home', 'icon': Icons.kitchen_rounded, 'slug': 'home_kitchen', 'bg': Color(0xFFE0F2FE), 'fg': Color(0xFF0284C7)},
    {'label': 'Beauty', 'icon': Icons.spa_rounded, 'slug': 'health_wellness', 'bg': Color(0xFFFCE7F3), 'fg': Color(0xFFDB2777)},
    {'label': 'Auto Care', 'icon': Icons.directions_car_rounded, 'slug': 'automotive', 'bg': Color(0xFFF1F5F9), 'fg': Color(0xFF475569)},
    {'label': 'More →', 'icon': Icons.grid_view_rounded, 'slug': 'more', 'bg': Color(0xFFEDE9FE), 'fg': Color(0xFF7C3AED)},
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _onFiltersChanged();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    setState(() => _isSearching = value.isNotEmpty);
  }

  void _search() {
    final q = _searchController.text.trim();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SearchResultsScreen(
          initialQuery: q.isEmpty ? null : q,
          initialCategory: _selectedCategory == 'all' ? null : _selectedCategory,
        ),
      ),
    );
    FocusScope.of(context).unfocus();
  }

  void _onFiltersChanged() {
    final loc = ref.read(appLocationProvider);
    final q = _searchController.text.trim();
    if (q.isEmpty) {
      ref.read(businessesProvider.notifier).search(
        query: '',
        lat: loc.latitude,
        lng: loc.longitude,
        radiusM: _radius,
        categorySlug: _selectedCategory == 'all' ? null : _selectedCategory,
        openNow: _isOpenNow,
        availableNow: _isAvailableNow,
        sort: _sortBy,
      );
    } else {
      _search();
    }
  }

  void _showLocationModal() {
    final customCityCtrl = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 20,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Select Location',
                          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppTheme.mainText),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Choose an active hub or request your town',
                          style: TextStyle(fontSize: 12, color: AppTheme.secondaryText),
                        ),
                      ],
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, color: AppTheme.secondaryText),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                // GPS Current Location
                InkWell(
                  onTap: () {
                    ref.read(appLocationProvider.notifier).setLocation(
                      const AppLocation(
                        cityName: 'Bhubaneswar',
                        localityName: 'Odisha (GPS)',
                        latitude: 20.2961,
                        longitude: 85.8245,
                        isSupported: true,
                        activeBusinessCount: 7,
                      ),
                    );
                    Navigator.pop(ctx);
                    _onFiltersChanged();
                  },
                  borderRadius: BorderRadius.circular(14),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryContainer.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppTheme.primary.withValues(alpha: 0.2)),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: AppTheme.primary,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.my_location_rounded, color: Colors.white, size: 20),
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Use Current GPS Location',
                                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: AppTheme.mainText),
                              ),
                              SizedBox(height: 2),
                              Text(
                                'Bhubaneswar Hub (20.2961° N, 85.8245° E)',
                                style: TextStyle(fontSize: 12, color: AppTheme.secondaryText),
                              ),
                            ],
                          ),
                        ),
                        const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: AppTheme.primary),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 20),
                const Text(
                  'ACTIVE SERVICE HUBS',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: AppTheme.secondaryText, letterSpacing: 0.8),
                ),
                const SizedBox(height: 8),

                _buildLocationTile(
                  ctx: ctx,
                  cityName: 'Bhubaneswar',
                  locality: 'Unit 3 & Janpath',
                  badge: '7 Verified Listings',
                  lat: 20.2961,
                  lng: 85.8245,
                  isSupported: true,
                  count: 7,
                ),
                _buildLocationTile(
                  ctx: ctx,
                  cityName: 'Cuttack',
                  locality: 'Badambadi & Chandi Chhak',
                  badge: '2 Verified Listings',
                  lat: 20.4625,
                  lng: 85.8830,
                  isSupported: true,
                  count: 2,
                ),
                _buildLocationTile(
                  ctx: ctx,
                  cityName: 'Jajpur',
                  locality: 'Jajpur Road & Station',
                  badge: '1 Verified Pro',
                  lat: 20.8447,
                  lng: 86.3315,
                  isSupported: true,
                  count: 1,
                ),

                const SizedBox(height: 16),
                const Text(
                  'UPCOMING CITIES (EXPANDING SOON)',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Color(0xFFD97706), letterSpacing: 0.8),
                ),
                const SizedBox(height: 8),

                _buildLocationTile(
                  ctx: ctx,
                  cityName: 'Puri',
                  locality: 'Grand Road & Sea Beach',
                  badge: 'Expanding Soon',
                  lat: 19.8135,
                  lng: 85.8312,
                  isSupported: false,
                  count: 0,
                ),
                _buildLocationTile(
                  ctx: ctx,
                  cityName: 'Rourkela',
                  locality: 'Panposh & Sector 5',
                  badge: 'Expanding Soon',
                  lat: 22.2604,
                  lng: 84.8536,
                  isSupported: false,
                  count: 0,
                ),
                _buildLocationTile(
                  ctx: ctx,
                  cityName: 'Berhampur',
                  locality: 'Silk City Main Market',
                  badge: 'Expanding Soon',
                  lat: 19.3149,
                  lng: 84.7941,
                  isSupported: false,
                  count: 0,
                ),

                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.search_rounded, color: AppTheme.secondaryText, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: customCityCtrl,
                          decoration: const InputDecoration(
                            hintText: 'Enter any locality or town in Odisha...',
                            hintStyle: TextStyle(fontSize: 13, color: AppTheme.hintText),
                            border: InputBorder.none,
                          ),
                          onSubmitted: (val) {
                            if (val.trim().isNotEmpty) {
                              _handleCustomLocationSelect(ctx, val.trim());
                            }
                          },
                        ),
                      ),
                      TextButton(
                        onPressed: () {
                          if (customCityCtrl.text.trim().isNotEmpty) {
                            _handleCustomLocationSelect(ctx, customCityCtrl.text.trim());
                          }
                        },
                        child: const Text('Check', style: TextStyle(fontWeight: FontWeight.w700)),
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

  void _handleCustomLocationSelect(BuildContext ctx, String locationQuery) {
    Navigator.pop(ctx);
    ref.read(appLocationProvider.notifier).setLocation(
      AppLocation(
        cityName: locationQuery,
        localityName: 'Odisha',
        latitude: 20.0,
        longitude: 85.0,
        isSupported: false,
        activeBusinessCount: 0,
      ),
    );

    try {
      apiClient.post(
        '/analytics/unserved-location',
        data: {
          'query': locationQuery,
          'city': locationQuery,
          'locality': 'Odisha',
        },
      );
    } catch (_) {}

    _onFiltersChanged();
  }

  Widget _buildLocationTile({
    required BuildContext ctx,
    required String cityName,
    required String locality,
    required String badge,
    required double lat,
    required double lng,
    required bool isSupported,
    required int count,
  }) {
    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      leading: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: isSupported
              ? AppTheme.primaryContainer.withValues(alpha: 0.7)
              : const Color(0xFFFEF3C7),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(
          isSupported ? Icons.storefront_rounded : Icons.radar_rounded,
          color: isSupported ? AppTheme.primary : const Color(0xFFD97706),
          size: 18,
        ),
      ),
      title: Row(
        children: [
          Text(cityName, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: isSupported ? const Color(0xFFDCFCE7) : const Color(0xFFFEF3C7),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              badge,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: isSupported ? const Color(0xFF15803D) : const Color(0xFFB45309),
              ),
            ),
          ),
        ],
      ),
      subtitle: Text(locality, style: const TextStyle(fontSize: 12, color: AppTheme.secondaryText)),
      trailing: const Icon(Icons.chevron_right_rounded, color: AppTheme.secondaryText, size: 18),
      onTap: () {
        ref.read(appLocationProvider.notifier).setLocation(
          AppLocation(
            cityName: cityName,
            localityName: locality,
            latitude: lat,
            longitude: lng,
            isSupported: isSupported,
            activeBusinessCount: count,
          ),
        );

        if (!isSupported) {
          try {
            apiClient.post(
              '/analytics/unserved-location',
              data: {
                'city': cityName,
                'locality': locality,
                'latitude': lat,
                'longitude': lng,
              },
            );
          } catch (_) {}
        }

        Navigator.pop(ctx);
        _onFiltersChanged();
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(businessesProvider);
    final appLocation = ref.watch(appLocationProvider);

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Screen 7 Header: Location selector + notification bell
            Padding(
              padding: const EdgeInsets.fromLTRB(kScreenPadding, 12, kScreenPadding, 8),
              child: Row(
                children: [
                  Expanded(
                    child: InkWell(
                      onTap: _showLocationModal,
                      borderRadius: BorderRadius.circular(12),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.location_on_rounded, color: AppTheme.primary, size: 22),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                appLocation.displayName,
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  color: AppTheme.mainText,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 4),
                            const Icon(Icons.keyboard_arrow_down_rounded, color: AppTheme.secondaryText, size: 20),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const Spacer(),
                  // Notification bell with badge
                  Stack(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFE4E7EC)),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.03),
                              blurRadius: 6,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: IconButton(
                          padding: EdgeInsets.zero,
                          icon: const Icon(Icons.notifications_none_rounded, color: AppTheme.mainText, size: 22),
                          onPressed: () {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('No new notifications')),
                            );
                          },
                        ),
                      ),
                      Positioned(
                        right: 8,
                        top: 8,
                        child: Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            color: AppTheme.error,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Screen 7 Search Bar with QR scanner icon
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: kScreenPadding),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFE4E7EC)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.03),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: TextField(
                  controller: _searchController,
                  onChanged: _onSearchChanged,
                  onSubmitted: (_) => _search(),
                  decoration: InputDecoration(
                    hintText: 'Search shops, services, products...',
                    hintStyle: const TextStyle(color: Color(0xFF9AA5B1), fontSize: 14),
                    prefixIcon: const Icon(Icons.search_rounded, color: Color(0xFF9AA5B1), size: 22),
                    suffixIcon: _isSearching
                        ? IconButton(
                            icon: const Icon(Icons.clear_rounded, color: Color(0xFF9AA5B1), size: 18),
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _isSearching = false);
                              _onFiltersChanged();
                            },
                          )
                        : IconButton(
                            icon: const Icon(Icons.qr_code_scanner_rounded, color: AppTheme.primary, size: 20),
                            onPressed: () {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('QR Code scanner coming soon')),
                              );
                            },
                          ),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Screen 7 Circular Category Buttons Row Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: kScreenPadding),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Categories',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.mainText,
                      letterSpacing: -0.3,
                    ),
                  ),
                  InkWell(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const CategoriesScreen()),
                      );
                    },
                    borderRadius: BorderRadius.circular(8),
                    child: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                      child: Text(
                        'View All',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.primary,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),

            // Screen 7 Circular Category Buttons Row
            SizedBox(
              height: 92,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: kScreenPadding),
                itemCount: _categories.length,
                separatorBuilder: (_, _) => const SizedBox(width: 4),
                itemBuilder: (_, i) {
                  final cat = _categories[i];
                  final isSel = _selectedCategory == cat['slug'];
                  return CategoryCircleItem(
                    label: cat['label'] as String,
                    icon: cat['icon'] as IconData,
                    backgroundColor: cat['bg'] as Color?,
                    iconColor: cat['fg'] as Color?,
                    isSelected: isSel,
                    onTap: () {
                      if (cat['slug'] == 'more') {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const CategoriesScreen()),
                        );
                      } else {
                        setState(() => _selectedCategory = cat['slug'] as String);
                        _onFiltersChanged();
                      }
                    },
                  );
                },
              ),
            ),
            const SizedBox(height: 12),

            // Screen 7 Hero Promotional Banner
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: kScreenPadding),
              child: BannerCard(
                badgeText: 'New Arrivals',
                title: 'Monsoon Home Care Sale',
                subtitle: 'Up to 20% off on plumbing & electrical services this week',
                onTap: () {},
              ),
            ),
            const SizedBox(height: 18),

            // Section Header: "Nearby Shops" with "View All" matching Screen 7
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: kScreenPadding),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _isSearching
                        ? 'Search results'
                        : 'Nearby Shops & Services',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.mainText,
                      letterSpacing: -0.3,
                    ),
                  ),
                  InkWell(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const SearchResultsScreen()),
                      );
                    },
                    borderRadius: BorderRadius.circular(8),
                    child: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                      child: Text(
                        'View All',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.primary,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),

            // Business list.
            Expanded(
              child: state.isLoading && state.items.isEmpty
                  ? _buildSkeletonList()
                  : state.error != null && state.items.isEmpty
                      ? _buildEmpty(state.error!)
                      : state.items.isEmpty
                          ? _buildUnservedOrEmptyState(appLocation)
                          : RefreshIndicator(
                              onRefresh: () async {
                                _onFiltersChanged();
                              },
                              child: SafeArea(
                                top: false,
                                child: ListView.separated(
                                  padding: const EdgeInsets.fromLTRB(kScreenPadding, 0, kScreenPadding, 32),
                                  itemCount: state.items.length,
                                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                                  itemBuilder: (_, i) {
                                    final b = state.items[i];
                                    return BusinessCard(
                                      business: b,
                                      onTap: () {
                                        final serviceCategories = ['electrician', 'plumber', 'carpenter', 'tailor'];
                                        if (serviceCategories.contains(b.categorySlug) || b.acceptsRequests) {
                                          Navigator.of(context).push(
                                            MaterialPageRoute(builder: (_) => ServiceProScreen(business: b)),
                                          );
                                        } else {
                                          Navigator.of(context).push(
                                            MaterialPageRoute(builder: (_) => BusinessDetailScreen(businessId: b.id)),
                                          );
                                        }
                                      },
                                    );
                                  },
                                ),
                              ),
                            ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSkeletonList() {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: kScreenPadding),
      itemCount: 6,
      itemBuilder: (_, i) => const PremiumCard(
        padding: EdgeInsets.all(14),
        margin: EdgeInsets.only(bottom: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SkeletonLoader(width: 72, height: 72, radius: 10),
            SizedBox(height: 12),
            SkeletonLine(),
            SizedBox(height: 10),
            SkeletonLoader(width: 120, height: 14, radius: 7),
            SizedBox(height: 6),
            SkeletonLoader(width: 80, height: 14, radius: 7),
          ],
        ),
      ),
    );
  }

  Widget _buildEmpty(String error) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.search_off, size: 56, color: AppTheme.hintText),
          const SizedBox(height: 16),
          Text(
            'No results found',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
              color: AppTheme.mainText,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            error,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppTheme.secondaryText),
          ),
        ],
      ),
    );
  }

  Widget _buildUnservedOrEmptyState(AppLocation appLocation) {
    final cityName = appLocation.cityName;

    if (appLocation.isSupported) {
      return RefreshIndicator(
        onRefresh: () async => _onFiltersChanged(),
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withValues(alpha: 0.08),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.storefront_outlined, size: 36, color: AppTheme.primary),
                ),
                const SizedBox(height: 18),
                Text(
                  _selectedCategory != 'all'
                      ? 'No businesses in ${_selectedCategory.toUpperCase()} yet'
                      : 'No listings found in $cityName',
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.mainText,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  _selectedCategory != 'all'
                      ? 'Try switching to "All" or exploring other categories nearby.'
                      : 'Try broadening your search or switching to another locality.',
                  style: const TextStyle(fontSize: 13, color: AppTheme.secondaryText, height: 1.4),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                if (_selectedCategory != 'all')
                  OutlinedButton.icon(
                    icon: const Icon(Icons.refresh_rounded, size: 18),
                    label: const Text('Show All Categories'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.primary,
                      side: const BorderSide(color: AppTheme.primary),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    ),
                    onPressed: () {
                      setState(() => _selectedCategory = 'all');
                      _onFiltersChanged();
                    },
                  ),
              ],
            ),
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () async => _onFiltersChanged(),
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFFE2E8F0)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Radar / Expanding Soon Badge
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEF3C7),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: const Color(0xFFFDE68A)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.radar_rounded, size: 16, color: Color(0xFFD97706)),
                        const SizedBox(width: 6),
                        Text(
                          'EXPANDING TO ${cityName.toUpperCase()} SOON',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFFB45309),
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),

                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: AppTheme.primary.withValues(alpha: 0.08),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.location_off_rounded, size: 32, color: AppTheme.primary),
                  ),
                  const SizedBox(height: 16),

                  Text(
                    'Service Not Available in $cityName Yet',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.mainText,
                      letterSpacing: -0.3,
                    ),
                  ),
                  const SizedBox(height: 8),

                  Text(
                    'We are currently onboarding verified local shops and certified service professionals in $cityName. Grepmind Near will provide services in this location soon!',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppTheme.secondaryText,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 20),

                  // "Notify Me When Available" Button
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.notifications_active_outlined, size: 18, color: Colors.white),
                      label: const Text(
                        'Notify Me When Available',
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Colors.white),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primary,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        elevation: 0,
                      ),
                      onPressed: () => _promptNotifyMe(appLocation),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Explore Active Cities Section
            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Explore Active Service Cities',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.mainText,
                ),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                _buildActiveCityChip(
                  name: 'Bhubaneswar',
                  count: '7 Stores & Pros',
                  lat: 20.2961,
                  lng: 85.8245,
                  active: cityName == 'Bhubaneswar',
                ),
                const SizedBox(width: 8),
                _buildActiveCityChip(
                  name: 'Cuttack',
                  count: '2 Active',
                  lat: 20.4625,
                  lng: 85.8830,
                  active: cityName == 'Cuttack',
                ),
                const SizedBox(width: 8),
                _buildActiveCityChip(
                  name: 'Jajpur',
                  count: '1 Active',
                  lat: 20.8447,
                  lng: 86.3315,
                  active: cityName == 'Jajpur',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _promptNotifyMe(AppLocation appLocation) {
    final phoneCtrl = TextEditingController(text: '+919');

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 20,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Launch Alert for ${appLocation.cityName}',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppTheme.mainText),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => Navigator.pop(ctx),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Enter your mobile number to receive instant SMS & WhatsApp notification when Grepmind Near launches in ${appLocation.cityName}.',
              style: const TextStyle(fontSize: 13, color: AppTheme.secondaryText, height: 1.4),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: phoneCtrl,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'Mobile Number',
                prefixIcon: Icon(Icons.phone_iphone_rounded, color: AppTheme.primary),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: () async {
                  final phone = phoneCtrl.text.trim();
                  if (phone.length < 10) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Please enter a valid phone number')),
                    );
                    return;
                  }
                  Navigator.pop(ctx);
                  try {
                    await apiClient.post(
                      '/analytics/unserved-location',
                      data: {
                        'city': appLocation.cityName,
                        'locality': appLocation.localityName,
                        'latitude': appLocation.latitude,
                        'longitude': appLocation.longitude,
                        'notification_phone': phone,
                      },
                    );
                  } catch (_) {}

                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Saved! We will notify $phone when services launch in ${appLocation.cityName}.'),
                        backgroundColor: AppTheme.success,
                      ),
                    );
                  }
                },
                child: const Text('Confirm Notification Alert', style: TextStyle(fontWeight: FontWeight.w700, color: Colors.white)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActiveCityChip({
    required String name,
    required String count,
    required double lat,
    required double lng,
    required bool active,
  }) {
    return Expanded(
      child: InkWell(
        onTap: () {
          ref.read(appLocationProvider.notifier).setLocation(
            AppLocation(
              cityName: name,
              localityName: 'Odisha',
              latitude: lat,
              longitude: lng,
              isSupported: true,
              activeBusinessCount: name == 'Bhubaneswar' ? 7 : (name == 'Cuttack' ? 2 : 1),
            ),
          );
          _onFiltersChanged();
        },
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
          decoration: BoxDecoration(
            color: active ? AppTheme.primary : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: active ? AppTheme.primary : const Color(0xFFE2E8F0),
            ),
          ),
          child: Column(
            children: [
              Text(
                name,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: active ? Colors.white : AppTheme.mainText,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Text(
                count,
                style: TextStyle(
                  fontSize: 10,
                  color: active ? Colors.white.withValues(alpha: 0.8) : AppTheme.secondaryText,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}