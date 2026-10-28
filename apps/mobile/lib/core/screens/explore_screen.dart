// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
    final q = _searchController.text.trim();
    if (q.isEmpty) {
      ref.read(businessesProvider.notifier).search(
        query: '',
        lat: 20.2961,
        lng: 85.8245,
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
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Select Location',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppTheme.mainText),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: AppTheme.secondaryText),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ListTile(
                leading: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(color: AppTheme.primaryContainer, borderRadius: BorderRadius.circular(10)),
                  child: const Icon(Icons.my_location, color: AppTheme.primary),
                ),
                title: const Text('Use Current GPS Location', style: TextStyle(fontWeight: FontWeight.w700)),
                subtitle: const Text('Bhubaneswar, Odisha (20.2961, 85.8245)'),
                onTap: () {
                  Navigator.pop(ctx);
                  _onFiltersChanged();
                },
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.location_city, color: AppTheme.secondaryText),
                title: const Text('Cuttack, Odisha'),
                onTap: () => Navigator.pop(ctx),
              ),
              ListTile(
                leading: const Icon(Icons.location_city, color: AppTheme.secondaryText),
                title: const Text('Puri, Odisha'),
                onTap: () => Navigator.pop(ctx),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(businessesProvider);

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
                  InkWell(
                    onTap: _showLocationModal,
                    borderRadius: BorderRadius.circular(12),
                    child: const Padding(
                      padding: EdgeInsets.symmetric(vertical: 4, horizontal: 2),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.location_on_rounded, color: AppTheme.primary, size: 22),
                          SizedBox(width: 6),
                          Text(
                            'Bhubaneswar, Odisha',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.mainText,
                            ),
                          ),
                          SizedBox(width: 4),
                          Icon(Icons.keyboard_arrow_down_rounded, color: AppTheme.secondaryText, size: 20),
                        ],
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
            const SizedBox(height: 14),

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
                          ? RefreshIndicator(
                              onRefresh: () async => _onFiltersChanged(),
                              child: SingleChildScrollView(
                                physics: const AlwaysScrollableScrollPhysics(),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
                                  alignment: Alignment.center,
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.storefront_outlined, size: 56, color: AppTheme.hintText),
                                      const SizedBox(height: 16),
                                      Text(
                                        'No shops found nearby',
                                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                              fontWeight: FontWeight.w700,
                                              color: AppTheme.mainText,
                                            ),
                                      ),
                                      const SizedBox(height: 6),
                                      const Text(
                                        'Try adjusting your search radius or selecting a different category.',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(color: AppTheme.secondaryText, fontSize: 13),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            )
                          : RefreshIndicator(
                              onRefresh: () async {
                                _onFiltersChanged();
                              },
                              child: ListView.separated(
                                padding: const EdgeInsets.fromLTRB(kScreenPadding, 0, kScreenPadding, 24),
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
}