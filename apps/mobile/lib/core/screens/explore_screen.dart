// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:grepmind_mobile/core/network/api_client.dart';
import 'package:grepmind_mobile/core/providers/app_provider.dart';
import 'package:grepmind_mobile/core/providers/home_feed_provider.dart';
import 'package:grepmind_mobile/core/theme/app_theme.dart';
import 'package:grepmind_mobile/core/widgets/business_card.dart';
import 'package:grepmind_mobile/core/widgets/category_chip.dart';
import 'package:grepmind_mobile/core/widgets/premium_card.dart';
import 'package:grepmind_mobile/core/widgets/skeleton_loader.dart';
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
  bool _isSearching = false;
  bool _isOpenNow = false;
  final bool _isAvailableNow = false;
  final String _sortBy = 'relevance';
  final int _radius = 5000; // meters

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadInitialLocation();
    });
  }

  Future<void> _loadInitialLocation() async {
    if (ref.read(appLocationProvider).cityName.isEmpty) {
      try {
        final response = await apiClient.get('/locations');
        final locations = response.data['data'] as List;
        if (!mounted) return;
        if (locations.isNotEmpty) {
          final location = locations.first as Map<String, dynamic>;
          ref
              .read(appLocationProvider.notifier)
              .setLocation(
                AppLocation(
                  cityName: location['city'] as String,
                  latitude: (location['latitude'] as num).toDouble(),
                  longitude: (location['longitude'] as num).toDouble(),
                  activeBusinessCount: location['count'] as int,
                ),
              );
        }
      } catch (_) {
        /* Location picker provides an explicit retry. */
      }
    }
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

  void _showLocationModal() async {
    List<Map<String, dynamic>> locations;
    try {
      final response = await apiClient.get('/locations');
      locations = (response.data['data'] as List).cast<Map<String, dynamic>>();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Unable to load cities. Please try again.'),
          ),
        );
      }
      return;
    }
    if (!mounted) return;

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
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: AppTheme.mainText,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Choose Cuttack or Jajpur',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppTheme.secondaryText,
                          ),
                        ),
                      ],
                    ),
                    IconButton(
                      icon: const Icon(
                        Icons.close_rounded,
                        color: AppTheme.secondaryText,
                      ),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Text(
                  'AVAILABLE CITIES',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                if (locations.isEmpty)
                  const Text('No cities currently have active listings.'),
                ...locations.map(
                  (location) => _buildLocationTile(
                    ctx: ctx,
                    cityName: location['city'] as String,
                    locality: '',
                    badge: '${location['count']} active listings',
                    lat: (location['latitude'] as num).toDouble(),
                    lng: (location['longitude'] as num).toDouble(),
                    isSupported: true,
                    count: location['count'] as int,
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
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
          Text(
            cityName,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: isSupported
                  ? const Color(0xFFDCFCE7)
                  : const Color(0xFFFEF3C7),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              badge,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: isSupported
                    ? const Color(0xFF15803D)
                    : const Color(0xFFB45309),
              ),
            ),
          ),
        ],
      ),
      subtitle: Text(
        locality,
        style: const TextStyle(fontSize: 12, color: AppTheme.secondaryText),
      ),
      trailing: const Icon(
        Icons.chevron_right_rounded,
        color: AppTheme.secondaryText,
        size: 18,
      ),
      onTap: () {
        ref
            .read(appLocationProvider.notifier)
            .setLocation(
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
    final categoryState = ref.watch(categoriesProvider);
    final categoryItems = categoryState.items.take(10).toList(growable: false);
    final state = ref.watch(businessesProvider);
    final appLocation = ref.watch(appLocationProvider);
    final recentBusinesses = ref.watch(
      recentlyAddedBusinessesProvider(appLocation.cityName),
    );

    return Scaffold(
      backgroundColor: AppTheme.background,
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
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Explore',
                                  style: Theme.of(context)
                                      .textTheme
                                      .headlineSmall
                                      ?.copyWith(fontWeight: FontWeight.w800),
                                ),
                                InkWell(
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
                                          color: AppTheme.secondary,
                                          size: 17,
                                        ),
                                        const SizedBox(width: 4),
                                        Flexible(
                                          child: Text(
                                            appLocation.displayName.isEmpty
                                                ? 'Choose Cuttack or Jajpur'
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
                          IconButton.filledTonal(
                            tooltip: 'Nearby map',
                            onPressed: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const NearbyMapScreen(),
                              ),
                            ),
                            icon: const Icon(Icons.map_outlined),
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
                                      color: AppTheme.primary,
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
                                ? const Color(0xFFEEF2FF)
                                : (isMore
                                      ? const Color(0xFFEDE9FE)
                                      : CategoriesScreen.getCategoryColor(
                                          category!.slug,
                                        ).withOpacity(0.13)),
                            iconColor: isAll
                                ? const Color(0xFF4F46E5)
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
                                  color: AppTheme.primary,
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
                                  color: Colors.white,
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
                                                      color: AppTheme.primary,
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
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(
                    kScreenPadding,
                    0,
                    kScreenPadding,
                    32,
                  ),
                  sliver: SliverList.separated(
                    itemCount: state.items.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (_, i) {
                      final b = state.items[i];
                      return BusinessCard(
                        business: b,
                        onTap: () {
                          final serviceCategories = [
                            'electrician',
                            'plumber',
                            'carpenter',
                            'tailor',
                          ];
                          if (serviceCategories.contains(b.categorySlug) ||
                              b.acceptsRequests) {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => ServiceProScreen(business: b),
                              ),
                            );
                          } else {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) =>
                                    BusinessDetailScreen(businessId: b.id),
                              ),
                            );
                          }
                        },
                      );
                    },
                  ),
                ),
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
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEF3C7),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: const Color(0xFFFDE68A)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.radar_rounded,
                          size: 16,
                          color: Color(0xFFD97706),
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
                      icon: const Icon(
                        Icons.notifications_active_outlined,
                        size: 18,
                        color: Colors.white,
                      ),
                      label: const Text(
                        'Notify Me When Available',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
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
              'Enter your mobile number to receive instant SMS & WhatsApp notification when Grepmind Near launches in ${appLocation.cityName}.',
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
                    color: Colors.white,
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
