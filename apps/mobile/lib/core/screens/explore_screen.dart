import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:grepmind_mobile/core/network/api_client.dart';
import 'package:grepmind_mobile/core/providers/app_provider.dart';
import 'package:grepmind_mobile/core/providers/home_feed_provider.dart';
import 'package:grepmind_mobile/core/providers/platform_cart_provider.dart';
import 'package:grepmind_mobile/core/screens/platform_catalog_screen.dart';
import 'package:grepmind_mobile/core/theme/app_theme.dart';
import 'package:grepmind_mobile/core/models/business.dart';
import 'package:grepmind_mobile/core/widgets/category_chip.dart';
import 'package:grepmind_mobile/core/widgets/marketplace_cards.dart';
import 'package:grepmind_mobile/core/widgets/premium_card.dart';
import 'package:grepmind_mobile/core/widgets/skeleton_loader.dart';
import 'package:grepmind_mobile/core/widgets/sticky_cart_summary_bar.dart';
import 'package:grepmind_mobile/core/screens/business_detail_screen.dart';
import 'package:grepmind_mobile/core/screens/categories_screen.dart';
import 'package:grepmind_mobile/core/screens/search_results_screen.dart';
import 'package:grepmind_mobile/core/screens/service_pro_screen.dart';
import 'package:grepmind_mobile/core/screens/nearby_map_screen.dart';

/// Explore screen: search, categories, featured offer, nearby businesses.
class ExploreScreen extends ConsumerStatefulWidget {
  const ExploreScreen({super.key});

  @override
  ConsumerState<ExploreScreen> createState() => _ExploreScreenState();
}

class _ExploreScreenState extends ConsumerState<ExploreScreen> {
  final _searchController = TextEditingController();
  String _selectedCategory = 'all';
  String _activeQuickFilter = 'all'; // 'all', 'fast_delivery', 'grocery', 'food', 'services', 'open_now', 'top_rated'
  bool _isSearching = false;
  bool _isOpenNow = false;
  final bool _isAvailableNow = false;
  final String _sortBy = 'relevance';
  final int _radius = 5000; // meters

  List<Business> _getFilteredBusinesses(List<Business> items) {
    if (_activeQuickFilter == 'all') {
      return items;
    }
    return items.where((b) {
      switch (_activeQuickFilter) {
        case 'fast_delivery':
          return b.deliveryEnabled == true;
        case 'grocery':
          final slug = b.categorySlug.toLowerCase();
          return slug.contains('grocer') ||
              slug.contains('kirana') ||
              slug.contains('supermarket');
        case 'food':
          final slug = b.categorySlug.toLowerCase();
          return slug.contains('rest') ||
              slug.contains('food') ||
              slug.contains('cafe') ||
              slug.contains('bake') ||
              slug.contains('dine');
        case 'services':
          return b.shouldOpenServiceProfile;
        case 'open_now':
          return b.isOpenNow;
        case 'top_rated':
          return (b.rating ?? 0.0) >= 4.0;
        default:
          return true;
      }
    }).toList();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadInitialLocation();
    });
  }

  Future<void> _loadInitialLocation() async {
    await ref.read(appLocationProvider.notifier).loadDefaultLocation();
    if (mounted) _onFiltersChanged();
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
          initialCategory: _selectedCategory == 'all'
              ? null
              : _selectedCategory,
        ),
      ),
    );
    FocusScope.of(context).unfocus();
  }

  void _onFiltersChanged() {
    final loc = ref.read(appLocationProvider);
    final q = _searchController.text.trim();
    if (q.isEmpty) {
      ref
          .read(businessesProvider.notifier)
          .search(
            query: '',
            lat: loc.cityName.isEmpty ? null : loc.latitude,
            lng: loc.cityName.isEmpty ? null : loc.longitude,
            radiusM: _radius,
            categorySlug: _selectedCategory == 'all' ? null : _selectedCategory,
            city: loc.cityName,
            openNow: _isOpenNow,
            availableNow: _isAvailableNow,
            sort: _sortBy,
          );
    } else {
      _search();
    }
  }

  Future<void> _useCurrentLocationGPS() async {
    const chhatia = AppLocation(
      cityName: 'Jajpur',
      localityName: 'Chhatia',
      localityId: '02200000-0000-4000-8000-000000000201',
      latitude: 20.6105,
      longitude: 86.0270,
      activeBusinessCount: 15,
    );
    const kuanpal = AppLocation(
      cityName: 'Katak',
      localityName: 'Kuanpal',
      localityId: '02200000-0000-4000-8000-000000000101',
      latitude: 20.5250,
      longitude: 86.0820,
      activeBusinessCount: 12,
    );

    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        ref.read(appLocationProvider.notifier).setLocation(chhatia);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text(
                'Location permission denied. Switched to default hub: Chhatia, Jajpur.',
              ),
              backgroundColor: AbashyakaColors.secondaryText,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          );
        }
        _onFiltersChanged();
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        timeLimit: const Duration(seconds: 5),
      );

      final distToChhatia = Geolocator.distanceBetween(
        position.latitude,
        position.longitude,
        chhatia.latitude,
        chhatia.longitude,
      );
      final distToKuanpal = Geolocator.distanceBetween(
        position.latitude,
        position.longitude,
        kuanpal.latitude,
        kuanpal.longitude,
      );

      final closest = distToChhatia <= distToKuanpal ? chhatia : kuanpal;
      final shortestDist = distToChhatia <= distToKuanpal
          ? distToChhatia
          : distToKuanpal;
      final shortestKm = (shortestDist / 1000).toStringAsFixed(1);

      ref.read(appLocationProvider.notifier).setLocation(closest);
      _onFiltersChanged();

      if (mounted) {
        final message = shortestDist <= 30000
            ? 'GPS matched to ${closest.localityName}, ${closest.cityName} ($shortestKm km away).'
            : 'Outside active delivery coverage ($shortestKm km). Switched to nearest hub: ${closest.localityName}, ${closest.cityName}.';

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(
                  Icons.my_location_rounded,
                  color: AbashyakaColors.pureWhite,
                  size: 20,
                ),
                const SizedBox(width: 10),
                Expanded(child: Text(message)),
              ],
            ),
            backgroundColor: AbashyakaColors.success,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (_) {
      ref.read(appLocationProvider.notifier).setLocation(chhatia);
      _onFiltersChanged();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              'GPS unavailable. Switched to default hub: Chhatia, Jajpur.',
            ),
            backgroundColor: AbashyakaColors.secondaryText,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
      }
    }
  }

  void _showLocationModal() {
    const chhatia = AppLocation(
      cityName: 'Jajpur',
      localityName: 'Chhatia',
      localityId: '02200000-0000-4000-8000-000000000201',
      latitude: 20.6105,
      longitude: 86.0270,
      activeBusinessCount: 15,
    );
    const kuanpal = AppLocation(
      cityName: 'Katak',
      localityName: 'Kuanpal',
      localityId: '02200000-0000-4000-8000-000000000101',
      latitude: 20.5250,
      longitude: 86.0820,
      activeBusinessCount: 12,
    );

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
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
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: const Color(0xFFD1D5DB),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Select Delivery Hub',
                          style: TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF153D30),
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Authorized launch areas for Abashyaka',
                          style: TextStyle(
                            fontSize: 12,
                            color: Color(0xFF6B7280),
                          ),
                        ),
                      ],
                    ),
                    IconButton(
                      icon: const Icon(
                        Icons.close_rounded,
                        color: Color(0xFF6B7280),
                      ),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                InkWell(
                  onTap: () async {
                    Navigator.pop(ctx);
                    await _useCurrentLocationGPS();
                  },
                  borderRadius: BorderRadius.circular(14),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: AbashyakaColors.successSurface,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: AbashyakaColors.success.withValues(alpha: 0.3),
                      ),
                    ),
                    child: const Row(
                      children: [
                        Icon(
                          Icons.my_location_rounded,
                          color: AbashyakaColors.success,
                          size: 22,
                        ),
                        SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Use My Current Location',
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14,
                                  color: AbashyakaColors.success,
                                ),
                              ),
                              Text(
                                'Matches to closest launch hub via GPS',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Color(0xFF52675D),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Icon(
                          Icons.arrow_forward_ios_rounded,
                          size: 14,
                          color: AbashyakaColors.success,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'AVAILABLE LAUNCH HUBS',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.6,
                    color: Color(0xFF6B7280),
                  ),
                ),
                const SizedBox(height: 10),
                _buildHubTile(
                  ctx: ctx,
                  location: chhatia,
                  title: 'Chhatia Hub',
                  subtitle: 'Jajpur District',
                  badge: '15 Active Stores',
                  isRecommended: true,
                ),
                const SizedBox(height: 8),
                _buildHubTile(
                  ctx: ctx,
                  location: kuanpal,
                  title: 'Kuanpal Hub',
                  subtitle: 'Katak District',
                  badge: '12 Active Stores',
                  isRecommended: false,
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHubTile({
    required BuildContext ctx,
    required AppLocation location,
    required String title,
    required String subtitle,
    required String badge,
    required bool isRecommended,
  }) {
    final isSelected =
        ref.watch(appLocationProvider).localityName == location.localityName;
    return InkWell(
      onTap: () {
        Navigator.pop(ctx);
        ref.read(appLocationProvider.notifier).setLocation(location);
        _onFiltersChanged();
      },
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isSelected ? AbashyakaColors.successSurface : AbashyakaColors.pureWhite,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected
                ? AbashyakaColors.success
                : const Color(0xFFE5E7EB),
            width: isSelected ? 1.5 : 1.0,
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: isSelected
                    ? AbashyakaColors.success
                    : const Color(0xFFF3F4F6),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.store_rounded,
                size: 20,
                color: isSelected ? AbashyakaColors.pureWhite : const Color(0xFF6B7280),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                          color: isSelected
                              ? AbashyakaColors.success
                              : const Color(0xFF1F2937),
                        ),
                      ),
                      if (isRecommended) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFF8A00)
                                .withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text(
                            'RECOMMENDED',
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                              color: AbashyakaColors.warning,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF6B7280),
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: AbashyakaColors.successSurface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFBBF7D0)),
              ),
              child: Text(
                badge,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: AbashyakaColors.success,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final categoryState = ref.watch(categoriesProvider);
    final categoryItems = categoryState.items.take(10).toList(growable: false);
    final state = ref.watch(businessesProvider);
    final appLocation = ref.watch(appLocationProvider);
    final recentBusinesses = ref.watch(
      recentlyAddedBusinessesProvider(appLocation.cityName),
    );
    final userId = ref.watch(currentUserProvider)?.id ?? '';
    final groceryScope = PlatformCartScope(
      userId: userId,
      vertical: 'grocery',
      localityId: appLocation.localityId,
      locality: appLocation.localityName,
      district: appLocation.cityName,
    );
    final foodScope = PlatformCartScope(
      userId: userId,
      vertical: 'food',
      localityId: appLocation.localityId,
      locality: appLocation.localityName,
      district: appLocation.cityName,
    );
    final groceryCart = ref.watch(platformCartProvider(groceryScope));
    final foodCart = ref.watch(platformCartProvider(foodScope));

    return Scaffold(
      backgroundColor: AppTheme.background,
      bottomNavigationBar: groceryCart.itemCount > 0
          ? StickyCartSummaryBar(scope: groceryScope)
          : foodCart.itemCount > 0
          ? StickyCartSummaryBar(scope: foodScope)
          : null,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async => _onFiltersChanged(),
          child: CustomScrollView(
            key: const Key('explore_screen_scroll_view'),
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Explore is a task-focused search surface; Home owns promotional discovery.
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        kScreenPadding,
                        10,
                        kScreenPadding,
                        8,
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 38,
                            height: 38,
                            margin: const EdgeInsets.only(right: 12),
                            decoration: BoxDecoration(
                              color: AbashyakaColors.successSurface,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            padding: const EdgeInsets.all(4),
                            child: Image.asset(
                              'assets/abashyaka/emblem_official.png',
                              fit: BoxFit.contain,
                              errorBuilder: (context, error, stackTrace) =>
                                  Image.asset(
                                    'assets/abashyaka/splash_emblem.png',
                                    fit: BoxFit.contain,
                                  ),
                            ),
                          ),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    const Text(
                                      'Explore',
                                      style: TextStyle(
                                        fontSize: 22,
                                        fontWeight: FontWeight.w800,
                                        color: Color(0xFF153D30),
                                        letterSpacing: -0.3,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 7,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: AbashyakaColors.successSurface,
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(
                                          color: AbashyakaColors.success
                                              .withValues(alpha: 0.3),
                                        ),
                                      ),
                                      child: const Text(
                                        'ଆବଶ୍ୟକ',
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w700,
                                          color: AbashyakaColors.success,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                InkWell(
                                  key: const Key('explore_location_selector'),
                                  onTap: _showLocationModal,
                                  borderRadius: BorderRadius.circular(8),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 2,
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(
                                          Icons.location_on_rounded,
                                          color: AppTheme.emerald,
                                          size: 17,
                                        ),
                                        const SizedBox(width: 4),
                                        Flexible(
                                          child: Text(
                                            appLocation.displayName.isEmpty
                                                ? 'Chhatia, Jajpur'
                                                : appLocation.displayName,
                                            style: Theme.of(context)
                                                .textTheme
                                                .labelLarge
                                                ?.copyWith(
                                                  color: AppTheme.secondaryText,
                                                ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        const Icon(
                                          Icons.keyboard_arrow_down_rounded,
                                          color: AppTheme.secondaryText,
                                          size: 18,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: AbashyakaColors.successSurface,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: const Color(0xFFA7F3D0),
                              ),
                            ),
                            child: IconButton(
                              tooltip: 'Nearby map',
                              padding: EdgeInsets.zero,
                              onPressed: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const NearbyMapScreen(),
                                ),
                              ),
                              icon: const Icon(
                                Icons.map_outlined,
                                color: AppTheme.emerald,
                                size: 20,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Screen 7 Search Bar with QR scanner icon
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: kScreenPadding,
                      ),
                      child: Container(
                        decoration: BoxDecoration(
                          color: AbashyakaColors.pureWhite,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: AbashyakaColors.aquaSilverBorder),
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
                            hintStyle: const TextStyle(
                              color: Color(0xFF9AA5B1),
                              fontSize: 14,
                            ),
                            prefixIcon: const Icon(
                              Icons.search_rounded,
                              color: Color(0xFF9AA5B1),
                              size: 22,
                            ),
                            suffixIcon: _isSearching
                                ? IconButton(
                                    icon: const Icon(
                                      Icons.clear_rounded,
                                      color: Color(0xFF9AA5B1),
                                      size: 18,
                                    ),
                                    onPressed: () {
                                      _searchController.clear();
                                      setState(() => _isSearching = false);
                                      _onFiltersChanged();
                                    },
                                  )
                                : IconButton(
                                    tooltip: 'Search',
                                    icon: const Icon(
                                      Icons.arrow_forward_rounded,
                                      color: AppTheme.emerald,
                                      size: 20,
                                    ),
                                    onPressed: _search,
                                  ),
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(
                              vertical: 14,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: kScreenPadding,
                      ),
                      child: Row(
                        children: [
                          FilterChip(
                            label: const Text('Open now'),
                            avatar: const Icon(
                              Icons.schedule_rounded,
                              size: 17,
                            ),
                            selected: _isOpenNow,
                            onSelected: (selected) {
                              setState(() => _isOpenNow = selected);
                              _onFiltersChanged();
                            },
                            showCheckmark: false,
                            materialTapTargetSize: MaterialTapTargetSize.padded,
                          ),
                          const SizedBox(width: 8),
                          OutlinedButton.icon(
                            onPressed: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const NearbyMapScreen(),
                              ),
                            ),
                            icon: const Icon(Icons.map_outlined, size: 18),
                            label: const Text('Map'),
                            style: OutlinedButton.styleFrom(
                              minimumSize: const Size(88, 48),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(24),
                              ),
                            ),
                          ),
                          const Spacer(),
                          Text(
                            '${state.items.length} results',
                            style: Theme.of(context).textTheme.labelMedium,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),

                    // Screen 7 Circular Category Buttons Row Header
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: kScreenPadding,
                      ),
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
                                MaterialPageRoute(
                                  builder: (_) => const CategoriesScreen(),
                                ),
                              );
                            },
                            borderRadius: BorderRadius.circular(8),
                            child: const Padding(
                              padding: EdgeInsets.symmetric(
                                horizontal: 4,
                                vertical: 2,
                              ),
                              child: Text(
                                'View All',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF087F0D),
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
                      height: 114,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(
                          horizontal: kScreenPadding,
                        ),
                        itemCount: categoryState.isLoading
                            ? 6
                            : categoryItems.length + 2,
                        separatorBuilder: (_, _) => const SizedBox(width: 4),
                        itemBuilder: (_, i) {
                          if (categoryState.isLoading) {
                            return const SizedBox(
                              width: 68,
                              child: SkeletonLoader(height: 68, radius: 34),
                            );
                          }
                          final isAll = i == 0;
                          final isMore = i == categoryItems.length + 1;
                          final category = isAll || isMore
                              ? null
                              : categoryItems[i - 1];
                          final slug = isAll
                              ? 'all'
                              : (isMore ? 'more' : category!.slug);
                          final isSel = _selectedCategory == slug;
                          return CategoryCircleItem(
                            key: Key('explore_category_$slug'),
                            label: isAll
                                ? 'All'
                                : (isMore ? 'More' : category!.name),
                            icon: isAll
                                ? Icons.apps_rounded
                                : (isMore
                                      ? Icons.grid_view_rounded
                                      : CategoriesScreen.getCategoryIcon(
                                          category!.slug,
                                        )),
                            backgroundColor: isAll
                                ? const Color(0xFFE4F7E3)
                                : (isMore
                                      ? const Color(0xFFEDE9FE)
                                      : CategoriesScreen.getCategoryBackgroundColor(
                                          category!.slug,
                                        )),
                            iconColor: isAll
                                ? const Color(0xFF087F0D)
                                : (isMore
                                      ? const Color(0xFF7C3AED)
                                      : CategoriesScreen.getCategoryColor(
                                          category!.slug,
                                        )),
                            isSelected: isSel,
                            onTap: () {
                              if (isMore) {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => const CategoriesScreen(),
                                  ),
                                );
                              } else {
                                setState(() => _selectedCategory = slug);
                                _onFiltersChanged();
                              }
                            },
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Search results are the main Explore content, distinct from Home's feed.
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: kScreenPadding,
                      ),
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
                                MaterialPageRoute(
                                  builder: (_) => const SearchResultsScreen(),
                                ),
                              );
                            },
                            borderRadius: BorderRadius.circular(8),
                            child: const Padding(
                              padding: EdgeInsets.symmetric(
                                horizontal: 4,
                                vertical: 2,
                              ),
                              child: Text(
                                'View All',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF087F0D),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),

                    if (recentBusinesses.isLoading ||
                        (recentBusinesses.valueOrNull?.isNotEmpty ??
                            false)) ...[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(
                          kScreenPadding,
                          0,
                          kScreenPadding,
                          8,
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Recently added',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium
                                        ?.copyWith(fontWeight: FontWeight.w800),
                                  ),
                                  Text(
                                    'Newly approved businesses in ${appLocation.cityName}',
                                    style: Theme.of(context).textTheme.bodySmall
                                        ?.copyWith(
                                          color: AppTheme.secondaryText,
                                        ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(
                        height: 114,
                        child: recentBusinesses.when(
                          loading: () => const Center(
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          error: (_, _) => const SizedBox.shrink(),
                          data: (items) => ListView.separated(
                            padding: const EdgeInsets.symmetric(
                              horizontal: kScreenPadding,
                            ),
                            scrollDirection: Axis.horizontal,
                            itemCount: items.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(width: 10),
                            itemBuilder: (context, index) {
                              final business = items[index];
                              return SizedBox(
                                width: 270,
                                child: Material(
                                  color: AbashyakaColors.pureWhite,
                                  borderRadius: BorderRadius.circular(16),
                                  clipBehavior: Clip.antiAlias,
                                  child: InkWell(
                                    onTap: () => Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => BusinessDetailScreen(
                                          businessId: business.id,
                                        ),
                                      ),
                                    ),
                                    child: Padding(
                                      padding: const EdgeInsets.all(9),
                                      child: Row(
                                        children: [
                                          ClipRRect(
                                            borderRadius: BorderRadius.circular(
                                              12,
                                            ),
                                            child: SizedBox(
                                              width: 86,
                                              height: 86,
                                              child:
                                                  business
                                                          .coverPhotoUrl
                                                          ?.isNotEmpty ==
                                                      true
                                                  ? Image.network(
                                                      business.coverPhotoUrl!,
                                                      fit: BoxFit.cover,
                                                      errorBuilder: (_, _, _) =>
                                                          const _RecentBusinessPlaceholder(),
                                                    )
                                                  : const _RecentBusinessPlaceholder(),
                                            ),
                                          ),
                                          const SizedBox(width: 10),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              mainAxisAlignment:
                                                  MainAxisAlignment.center,
                                              children: [
                                                Container(
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        horizontal: 8,
                                                        vertical: 3,
                                                      ),
                                                  decoration: BoxDecoration(
                                                    color: AppTheme
                                                        .primaryContainer,
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          20,
                                                        ),
                                                  ),
                                                  child: const Text(
                                                    'NEW LISTING',
                                                    style: TextStyle(
                                                      color: AppTheme.emerald,
                                                      fontSize: 9,
                                                      fontWeight:
                                                          FontWeight.w800,
                                                    ),
                                                  ),
                                                ),
                                                const SizedBox(height: 5),
                                                Text(
                                                  business.name,
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: Theme.of(context)
                                                      .textTheme
                                                      .titleSmall
                                                      ?.copyWith(
                                                        fontWeight:
                                                            FontWeight.w800,
                                                      ),
                                                ),
                                                Text(
                                                  '${business.categoryName ?? business.categorySlug} · ${business.locality ?? business.city ?? ''}',
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: Theme.of(context)
                                                      .textTheme
                                                      .bodySmall
                                                      ?.copyWith(
                                                        color: AppTheme
                                                            .secondaryText,
                                                      ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          const Icon(
                                            Icons.chevron_right_rounded,
                                            color: AppTheme.secondaryText,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],

                    // 1. Featured Neighborhood Spotlight
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: kScreenPadding,
                      ),
                      child: FeaturedNeighborhoodCard(
                        title: 'Fresh Winter Harvest & Specials',
                        subtitle:
                            'Hand-picked daily from local farming cooperatives in ${appLocation.cityName}',
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => PlatformCatalogScreen(
                                vertical: 'grocery',
                                city: appLocation.cityName,
                                locality: appLocation.localityName,
                                localityId: appLocation.localityId,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 12),

                    // 2. Quick Grocery Essentials Header
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: kScreenPadding,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Fresh Groceries (15–30 mins)',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: AppTheme.brandText,
                              letterSpacing: -0.3,
                            ),
                          ),
                          InkWell(
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => PlatformCatalogScreen(
                                    vertical: 'grocery',
                                    city: appLocation.cityName,
                                    locality: appLocation.localityName,
                                    localityId: appLocation.localityId,
                                  ),
                                ),
                              );
                            },
                            borderRadius: BorderRadius.circular(8),
                            child: const Padding(
                              padding: EdgeInsets.symmetric(
                                horizontal: 4,
                                vertical: 2,
                              ),
                              child: Text(
                                'View All',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: AppTheme.emerald,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),

                    // 2. Quick Grocery Cards Horizontal Carousel
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(
                        horizontal: kScreenPadding,
                      ),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 165,
                            height: 250,
                            child: CompactGroceryCard(
                              name: 'Fresh Red Tomatoes',
                              unit: '1 kg',
                              priceMinor: 4200,
                              mrpMinor: 5000,
                              badgeText: '16% OFF',
                              quantityInCart:
                                  groceryCart
                                      .lines['4e300000-0000-4000-8000-000000000211']
                                      ?.quantity ??
                                  0,
                              onAdd: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => PlatformCatalogScreen(
                                      vertical: 'grocery',
                                      city: appLocation.cityName,
                                      locality: appLocation.localityName,
                                      localityId: appLocation.localityId,
                                    ),
                                  ),
                                );
                              },
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => PlatformCatalogScreen(
                                      vertical: 'grocery',
                                      city: appLocation.cityName,
                                      locality: appLocation.localityName,
                                      localityId: appLocation.localityId,
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                          const SizedBox(width: 12),
                          SizedBox(
                            width: 165,
                            height: 250,
                            child: CompactGroceryCard(
                              name: 'Kalinga Cold-Pressed Mustard Oil',
                              unit: '1 L',
                              priceMinor: 18000,
                              mrpMinor: 21000,
                              badgeText: 'POPULAR',
                              onAdd: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => PlatformCatalogScreen(
                                      vertical: 'grocery',
                                      city: appLocation.cityName,
                                      locality: appLocation.localityName,
                                      localityId: appLocation.localityId,
                                    ),
                                  ),
                                );
                              },
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => PlatformCatalogScreen(
                                      vertical: 'grocery',
                                      city: appLocation.cityName,
                                      locality: appLocation.localityName,
                                      localityId: appLocation.localityId,
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                          const SizedBox(width: 12),
                          SizedBox(
                            width: 165,
                            height: 250,
                            child: CompactGroceryCard(
                              name: 'Odisha Fresh Toned Milk',
                              unit: '500 ml',
                              priceMinor: 2800,
                              onAdd: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => PlatformCatalogScreen(
                                      vertical: 'grocery',
                                      city: appLocation.cityName,
                                      locality: appLocation.localityName,
                                      localityId: appLocation.localityId,
                                    ),
                                  ),
                                );
                              },
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => PlatformCatalogScreen(
                                      vertical: 'grocery',
                                      city: appLocation.cityName,
                                      locality: appLocation.localityName,
                                      localityId: appLocation.localityId,
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
              ),

              // Business list follows the same vertical scroll as the header
              // and recent listings, keeping a usable viewport on short screens.
              if (state.isLoading && state.items.isEmpty)
                _buildSkeletonSliver()
              else if (state.error != null && state.items.isEmpty)
                SliverToBoxAdapter(
                  child: SizedBox(
                    height: 280,
                    child: _buildEmpty(
                      'Unable to load nearby businesses. Please check your connection and try again.',
                    ),
                  ),
                )
              else if (state.items.isEmpty)
                SliverToBoxAdapter(
                  child: _buildUnservedOrEmptyState(appLocation),
                )
              else ...[
                SliverPersistentHeader(
                  pinned: true,
                  delegate: _StickyQuickFilterDelegate(
                    activeFilter: _activeQuickFilter,
                    onSelect: (filterKey) {
                      setState(() {
                        _activeQuickFilter = filterKey;
                      });
                    },
                    totalCount: _getFilteredBusinesses(state.items).length,
                  ),
                ),
                if (_getFilteredBusinesses(state.items).isEmpty)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: kScreenPadding,
                        vertical: 36,
                      ),
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: const BoxDecoration(
                                color: AbashyakaColors.successSurface,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.filter_alt_off_rounded,
                                size: 36,
                                color: AppTheme.emerald,
                              ),
                            ),
                            const SizedBox(height: 12),
                            const Text(
                              'No matching businesses found',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: AppTheme.brandText,
                              ),
                            ),
                            const SizedBox(height: 6),
                            const Text(
                              'Try selecting another filter or show all nearby stores.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 13,
                                color: AppTheme.secondaryText,
                              ),
                            ),
                            const SizedBox(height: 16),
                            ElevatedButton.icon(
                              onPressed: () =>
                                  setState(() => _activeQuickFilter = 'all'),
                              icon: const Icon(
                                Icons.clear_all_rounded,
                                size: 18,
                              ),
                              label: const Text('Show all nearby'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppTheme.emerald,
                                foregroundColor: AbashyakaColors.pureWhite,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(
                      kScreenPadding,
                      8,
                      kScreenPadding,
                      32,
                    ),
                    sliver: SliverList.separated(
                      itemCount: _getFilteredBusinesses(state.items).length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (_, i) {
                        final b = _getFilteredBusinesses(state.items)[i];
                        if (b.shouldOpenServiceProfile) {
                          return ServiceProCard(
                            name: b.name,
                            specialization:
                                b.categoryName ?? 'Service Specialist',
                            photoUrl: b.coverPhotoUrl,
                            rating: b.rating,
                            jobsCompleted: b.reviewCount,
                            coverageLocality: b.locality ?? b.city,
                            isVerified: b.verificationStatus == 'verified',
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => ServiceProScreen(business: b),
                              ),
                            ),
                            onBook: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => ServiceProScreen(business: b),
                              ),
                            ),
                          );
                        }
                        return LocalBusinessDiscoveryCard(
                          name: b.name,
                          category:
                              b.categoryName ??
                              (b.categorySlug.isNotEmpty
                                  ? '${b.categorySlug[0].toUpperCase()}${b.categorySlug.substring(1)}'
                                  : 'Store'),
                          categorySlug: b.categorySlug,
                          coverPhotoUrl: b.coverPhotoUrl,
                          rating: b.rating,
                          reviewCount: b.reviewCount,
                          distanceKm: b.distanceM != null
                              ? b.distanceM! / 1000.0
                              : null,
                          locality: b.locality ?? b.addressText,
                          operatingStatus: b.isOpenNow ? 'Open now' : 'Closed',
                          isVerified: b.verificationStatus == 'verified',
                          phoneNumber: b.phoneE164,
                          latitude: b.latitude,
                          longitude: b.longitude,
                          primaryActionLabel: b.shopActionLabel,
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) =>
                                  BusinessDetailScreen(businessId: b.id),
                            ),
                          ),
                          onPrimaryAction: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) =>
                                  BusinessDetailScreen(businessId: b.id),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSkeletonSliver() {
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: kScreenPadding),
      sliver: SliverList.builder(
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
            style: Theme.of(context).textTheme.bodyMedium
                ?.copyWith(color: AppTheme.secondaryText),
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
                  child: const Icon(
                    Icons.storefront_outlined,
                    size: 36,
                    color: AppTheme.primary,
                  ),
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
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppTheme.secondaryText,
                    height: 1.4,
                  ),
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
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 12,
                      ),
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
                color: AbashyakaColors.pureWhite,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AbashyakaColors.softGrey),
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
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: AbashyakaColors.warningSurface,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: const Color(0xFFFDE68A)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.radar_rounded,
                          size: 16,
                          color: AbashyakaColors.warning,
                        ),
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
                    child: const Icon(
                      Icons.location_off_rounded,
                      size: 32,
                      color: AppTheme.primary,
                    ),
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
                    'We are currently onboarding verified local shops and certified service professionals in $cityName. Abashyaka will provide services in this location soon!',
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
                      icon: const Icon(
                        Icons.notifications_active_outlined,
                        size: 18,
                        color: AbashyakaColors.pureWhite,
                      ),
                      label: const Text(
                        'Notify Me When Available',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: AbashyakaColors.pureWhite,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primary,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
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
            OutlinedButton.icon(
              onPressed: _showLocationModal,
              icon: const Icon(Icons.location_city_outlined),
              label: const Text('Browse available cities'),
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
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.mainText,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => Navigator.pop(ctx),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Enter your mobile number to receive instant SMS & WhatsApp notification when Abashyaka launches in ${appLocation.cityName}.',
              style: const TextStyle(
                fontSize: 13,
                color: AppTheme.secondaryText,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: phoneCtrl,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'Mobile Number',
                prefixIcon: Icon(
                  Icons.phone_iphone_rounded,
                  color: AppTheme.primary,
                ),
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
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: () async {
                  final phone = phoneCtrl.text.trim();
                  if (phone.length < 10) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Please enter a valid phone number'),
                      ),
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
                        content: Text(
                          'Saved! We will notify $phone when services launch in ${appLocation.cityName}.',
                        ),
                        backgroundColor: AppTheme.success,
                      ),
                    );
                  }
                },
                child: const Text(
                  'Confirm Notification Alert',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: AbashyakaColors.pureWhite,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RecentBusinessPlaceholder extends StatelessWidget {
  const _RecentBusinessPlaceholder();
  @override
  Widget build(BuildContext context) => const ColoredBox(
    color: AppTheme.surfaceVariant,
    child: Center(
      child: Icon(Icons.storefront_outlined, color: AppTheme.secondary),
    ),
  );
}

class _StickyQuickFilterDelegate extends SliverPersistentHeaderDelegate {
  final String activeFilter;
  final ValueChanged<String> onSelect;
  final int totalCount;

  _StickyQuickFilterDelegate({
    required this.activeFilter,
    required this.onSelect,
    required this.totalCount,
  });

  @override
  double get minExtent => 48.0;

  @override
  double get maxExtent => 48.0;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    const filters = [
      ('all', 'All', Icons.apps_rounded),
      ('fast_delivery', '⚡ Fast Delivery', null),
      ('food', '🍲 Food & Meals', null),
      ('grocery', '🛒 Fresh Grocery', null),
      ('services', '🛠️ Services', null),
      ('open_now', '🕒 Open Now', null),
      ('top_rated', '⭐ 4.0+', null),
    ];

    return Container(
      color: AppTheme.brandCanvas,
      alignment: Alignment.centerLeft,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(
          horizontal: kScreenPadding,
          vertical: 6,
        ),
        itemCount: filters.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final item = filters[index];
          final key = item.$1;
          final label = item.$2;
          final icon = item.$3;
          final isSelected = activeFilter == key;

          return Material(
            color: Colors.transparent,
            child: InkWell(
              key: Key('filter_pill_$key'),
              onTap: () => onSelect(key),
              borderRadius: BorderRadius.circular(20),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: isSelected ? AppTheme.emerald : AbashyakaColors.pureWhite,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isSelected
                        ? AppTheme.emerald
                        : const Color(0xFFE1EBE5),
                  ),
                  boxShadow: isSelected
                      ? [
                          BoxShadow(
                            color: AppTheme.emerald.withValues(alpha: 0.25),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ]
                      : [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.03),
                            blurRadius: 4,
                            offset: const Offset(0, 1),
                          ),
                        ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (icon != null) ...[
                      Icon(
                        icon,
                        size: 15,
                        color: isSelected ? AbashyakaColors.pureWhite : AppTheme.emerald,
                      ),
                      const SizedBox(width: 6),
                    ],
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: isSelected
                            ? FontWeight.w700
                            : FontWeight.w600,
                        color: isSelected ? AbashyakaColors.pureWhite : AppTheme.brandText,
                        letterSpacing: -0.2,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  bool shouldRebuild(covariant _StickyQuickFilterDelegate oldDelegate) {
    return oldDelegate.activeFilter != activeFilter ||
        oldDelegate.totalCount != totalCount;
  }
}
