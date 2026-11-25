import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:grepmind_mobile/core/data/category_listings_data.dart';
import 'package:grepmind_mobile/core/models/business.dart';
import 'package:grepmind_mobile/core/providers/app_provider.dart';
import 'package:grepmind_mobile/core/theme/abashyaka_colors.dart';
import 'package:grepmind_mobile/core/theme/app_theme.dart';
import 'package:grepmind_mobile/core/widgets/screen_illustration_card.dart';
import 'package:grepmind_mobile/core/widgets/business_card.dart';
import 'package:grepmind_mobile/core/screens/business_detail_screen.dart';
import 'package:grepmind_mobile/core/screens/service_pro_screen.dart';
import 'package:grepmind_mobile/core/screens/nearby_map_screen.dart';

/// Screen 9: Search & Filter Results
/// Designed according to Abashyaka Premium UI Standard:
/// - Metallic Teal (#007D80) & Signature Teal (#00545B)
/// - Pearl White (#F5FAFA) & Pure White (#FFFFFF)
/// - Premium Obsidian (#101820) primary typography
/// - Graphite Charcoal (#374151) secondary typography
/// - Strictly Admin-Approved Service Places (Chhatia, Kuanpal, Jagatpur, Tangi, Chandikhol)
/// - Real distance in km, zero raw pincodes
class SearchResultsScreen extends ConsumerStatefulWidget {
  final String? initialQuery;
  final String? initialCategory;
  final String? categoryName;

  const SearchResultsScreen({
    super.key,
    this.initialQuery,
    this.initialCategory,
    this.categoryName,
  });

  @override
  ConsumerState<SearchResultsScreen> createState() =>
      _SearchResultsScreenState();
}

class _SearchResultsScreenState extends ConsumerState<SearchResultsScreen> {
  late final TextEditingController _searchController;
  String? _selectedCategory;
  String? _selectedCategoryName;
  int _radiusM = 5000;
  bool _isOpenNow = false;
  bool _isVerifiedOnly = false;
  String _sortBy = 'distance';

  // Quick categories for 1-tap filtering
  static const List<Map<String, String>> _quickCategories = [
    {'slug': 'food', 'name': 'Food'},
    {'slug': 'grocery', 'name': 'Grocery'},
    {'slug': 'medicines', 'name': 'Medicines'},
    {'slug': 'doctors', 'name': 'Doctors'},
    {'slug': 'cab_auto', 'name': 'Cab & Auto'},
    {'slug': 'services', 'name': 'Services'},
    {'slug': 'shops', 'name': 'Shops'},
    {'slug': 'fashion', 'name': 'Fashion'},
    {'slug': 'hotels_stays', 'name': 'Hotels & Stays'},
    {'slug': 'fitness_wellness', 'name': 'Fitness'},
  ];

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController(text: widget.initialQuery ?? '');
    _selectedCategory = widget.initialCategory;
    _selectedCategoryName = widget.categoryName;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _executeSearch();
      ref.read(favoritesProvider.notifier).load();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _executeSearch() {
    final q = _searchController.text.trim();
    final location = ref.read(appLocationProvider);
    ref
        .read(businessesProvider.notifier)
        .search(
          query: q,
          lat: location.latitude,
          lng: location.longitude,
          city: location.cityName,
          radiusM: _radiusM,
          categorySlug: _selectedCategory,
          openNow: _isOpenNow ? true : null,
          sort: _sortBy,
        );
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
    if (isSaved == null || isSaved == wasSaved) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not update saved places. Please retry.'),
        ),
      );
    }
  }

  void _showRadiusSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                child: Row(
                  children: [
                    const Icon(
                      Icons.radar_rounded,
                      color: AbashyakaColors.signatureTeal,
                      size: 22,
                    ),
                    const SizedBox(width: 10),
                    const Text(
                      'Search Radius',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: AbashyakaColors.premiumObsidian,
                        letterSpacing: -0.3,
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1, color: Color(0xFFE2E8F0)),
              const SizedBox(height: 8),
              ...[1000, 2000, 5000, 10000, 20000].map((r) {
                final km = r ~/ 1000;
                final isSel = _radiusM == r;
                return ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 24),
                  leading: Icon(
                    isSel ? Icons.radio_button_checked : Icons.radio_button_off,
                    color: isSel
                        ? AbashyakaColors.signatureTeal
                        : const Color(0xFF94A3B8),
                  ),
                  title: Text(
                    'Within $km km',
                    style: TextStyle(
                      fontWeight: isSel ? FontWeight.w700 : FontWeight.w500,
                      color: isSel
                          ? AbashyakaColors.signatureTeal
                          : AbashyakaColors.graphiteCharcoal,
                    ),
                  ),
                  onTap: () {
                    Navigator.pop(ctx);
                    setState(() => _radiusM = r);
                    _executeSearch();
                  },
                );
              }),
            ],
          ),
        ),
      ),
    );
  }

  void _showSortSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                child: Row(
                  children: [
                    const Icon(
                      Icons.swap_vert_rounded,
                      color: AbashyakaColors.signatureTeal,
                      size: 22,
                    ),
                    const SizedBox(width: 10),
                    const Text(
                      'Sort Results By',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: AbashyakaColors.premiumObsidian,
                        letterSpacing: -0.3,
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1, color: Color(0xFFE2E8F0)),
              const SizedBox(height: 8),
              _buildSortOption('distance', 'Nearest First (Distance)', Icons.near_me_outlined),
              _buildSortOption('relevance', 'Best Match (Relevance)', Icons.auto_awesome_outlined),
              _buildSortOption('rating', 'Highest Rated (Reviews)', Icons.star_outline_rounded),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSortOption(String key, String title, IconData icon) {
    final isSel = _sortBy == key;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 24),
      leading: Icon(
        isSel ? Icons.radio_button_checked : Icons.radio_button_off,
        color: isSel
            ? AbashyakaColors.signatureTeal
            : const Color(0xFF94A3B8),
      ),
      title: Row(
        children: [
          Icon(
            icon,
            size: 18,
            color: isSel
                ? AbashyakaColors.signatureTeal
                : const Color(0xFF64748B),
          ),
          const SizedBox(width: 8),
          Text(
            title,
            style: TextStyle(
              fontWeight: isSel ? FontWeight.w700 : FontWeight.w500,
              color: isSel
                  ? AbashyakaColors.signatureTeal
                  : AbashyakaColors.graphiteCharcoal,
            ),
          ),
        ],
      ),
      onTap: () {
        Navigator.pop(context);
        setState(() => _sortBy = key);
        _executeSearch();
      },
    );
  }

  void _onBusinessTapped(Business biz) {
    if (biz.shouldOpenServiceProfile) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => ServiceProScreen(business: biz)),
      );
    } else {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => BusinessDetailScreen(businessId: biz.id),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(businessesProvider);
    final savedBusinessIds = ref
        .watch(favoritesProvider)
        .items
        .map((business) => business.id)
        .toSet();

    // Apply local filters if category, verified, or open-now is active
    var items = state.items;
    if (_selectedCategory != null &&
        _selectedCategory!.isNotEmpty &&
        _selectedCategory != 'all') {
      items = items
          .where((b) => CategoryListingsData.matchesCategory(
              b.categorySlug, _selectedCategory))
          .toList();
    }
    if (_isVerifiedOnly) {
      items = items.where((b) => b.verificationStatus == 'verified').toList();
    }
    if (_isOpenNow) {
      items = items.where((b) => b.isOpenNow).toList();
    }

    return Scaffold(
      backgroundColor: AbashyakaColors.pearlWhite,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: AbashyakaColors.premiumObsidian),
          onPressed: () => Navigator.pop(context),
        ),
        titleSpacing: 0,
        title: Container(
          margin: const EdgeInsets.only(right: 8),
          height: 44,
          decoration: BoxDecoration(
            color: const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: TextField(
            controller: _searchController,
            style: const TextStyle(
              fontSize: 14,
              color: AbashyakaColors.premiumObsidian,
              fontWeight: FontWeight.w500,
            ),
            onSubmitted: (_) => _executeSearch(),
            decoration: InputDecoration(
              hintText: 'Search food, shops, services, doctors...',
              hintStyle: const TextStyle(
                color: Color(0xFF94A3B8),
                fontSize: 14,
              ),
              prefixIcon: const Icon(
                Icons.search_rounded,
                color: AbashyakaColors.signatureTeal,
                size: 20,
              ),
              suffixIcon: _searchController.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(
                        Icons.clear_rounded,
                        color: Color(0xFF94A3B8),
                        size: 18,
                      ),
                      onPressed: () {
                        _searchController.clear();
                        _executeSearch();
                      },
                    )
                  : null,
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
        ),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 12),
            decoration: BoxDecoration(
              color: const Color(0xFFE6F7F7),
              borderRadius: BorderRadius.circular(12),
            ),
            child: IconButton(
              icon: const Icon(Icons.map_outlined, color: AbashyakaColors.signatureTeal),
              tooltip: 'Map view',
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const NearbyMapScreen()),
                );
              },
            ),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Column(
            children: [
              // Horizontal Filter Chips Row
              SizedBox(
                height: 48,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 6,
                  ),
                  children: [
                    // Category Active Chip
                    if (_selectedCategory != null) ...[
                      InkWell(
                        onTap: () {
                          setState(() {
                            _selectedCategory = null;
                            _selectedCategoryName = null;
                          });
                          _executeSearch();
                        },
                        borderRadius: BorderRadius.circular(20),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFE6F7F7),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: AbashyakaColors.metallicTeal,
                              width: 1.5,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                _selectedCategoryName ?? _selectedCategory!,
                                style: const TextStyle(
                                  color: AbashyakaColors.signatureTeal,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 12,
                                ),
                              ),
                              const SizedBox(width: 4),
                              const Icon(
                                Icons.close_rounded,
                                size: 14,
                                color: AbashyakaColors.signatureTeal,
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],

                    // Radius chip
                    _buildPillChip(
                      label: '${_radiusM ~/ 1000} km',
                      icon: Icons.radar_rounded,
                      isActive: _radiusM != 5000,
                      onTap: _showRadiusSheet,
                    ),
                    const SizedBox(width: 8),

                    // Sort chip
                    _buildPillChip(
                      label: _sortBy == 'distance'
                          ? 'Nearest'
                          : _sortBy == 'rating'
                          ? 'Top Rated'
                          : 'Best Match',
                      icon: Icons.swap_vert_rounded,
                      isActive: _sortBy != 'distance',
                      onTap: _showSortSheet,
                    ),
                    const SizedBox(width: 8),

                    // Verified chip
                    _buildPillChip(
                      label: 'Verified',
                      icon: Icons.verified_user_outlined,
                      isActive: _isVerifiedOnly,
                      onTap: () {
                        setState(() => _isVerifiedOnly = !_isVerifiedOnly);
                      },
                    ),
                    const SizedBox(width: 8),

                    // Open now chip
                    _buildPillChip(
                      label: 'Open Now',
                      icon: Icons.access_time_rounded,
                      isActive: _isOpenNow,
                      onTap: () {
                        setState(() => _isOpenNow = !_isOpenNow);
                        _executeSearch();
                      },
                    ),
                  ],
                ),
              ),
              const Divider(height: 1, thickness: 1, color: Color(0xFFE2E8F0)),
            ],
          ),
        ),
      ),
      body: Column(
        children: [
          // Quick Category Pills Bar (shown when no specific category is active)
          if (_selectedCategory == null) ...[
            Container(
              height: 42,
              color: Colors.white,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                itemCount: _quickCategories.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final cat = _quickCategories[index];
                  return InkWell(
                    onTap: () {
                      setState(() {
                        _selectedCategory = cat['slug'];
                        _selectedCategoryName = cat['name'];
                      });
                      _executeSearch();
                    },
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: Text(
                        cat['name']!,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AbashyakaColors.graphiteCharcoal,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            const Divider(height: 1, thickness: 1, color: Color(0xFFE2E8F0)),
          ],

          // Results Header bar
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  state.isLoading
                      ? 'Searching...'
                      : 'Showing ${items.length} nearby places',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AbashyakaColors.graphiteCharcoal,
                  ),
                ),
                if (_selectedCategory != null ||
                    _isVerifiedOnly ||
                    _isOpenNow ||
                    _radiusM != 5000)
                  InkWell(
                    onTap: () {
                      setState(() {
                        _selectedCategory = null;
                        _selectedCategoryName = null;
                        _isVerifiedOnly = false;
                        _isOpenNow = false;
                        _radiusM = 5000;
                        _sortBy = 'distance';
                      });
                      _executeSearch();
                    },
                    child: const Text(
                      'Clear Filters',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFFD97706),
                      ),
                    ),
                  ),
              ],
            ),
          ),

          const Padding(
            padding: EdgeInsets.fromLTRB(16, 2, 16, 10),
            child: ScreenIllustrationCard(
              illustration: ScreenIllustration.search,
              title: 'Search your neighborhood',
              subtitle: 'Compare nearby options at a glance',
              icon: Icons.travel_explore_rounded,
              compact: true,
            ),
          ),

          // Results List
          Expanded(
            child: state.isLoading && items.isEmpty
                ? const Center(
                    child: CircularProgressIndicator(
                      color: AbashyakaColors.signatureTeal,
                    ),
                  )
                : items.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 32),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            width: 72,
                            height: 72,
                            decoration: BoxDecoration(
                              color: const Color(0xFFE6F7F7),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: const Icon(
                              Icons.search_off_rounded,
                              color: AbashyakaColors.signatureTeal,
                              size: 36,
                            ),
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            'No businesses found',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: AbashyakaColors.premiumObsidian,
                              letterSpacing: -0.3,
                            ),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Try expanding your radius, searching nearby hubs like Chhatia, Kuanpal, Jagatpur, Tangi, or Chandikhol, or clearing filters.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 13,
                              color: AbashyakaColors.graphiteCharcoal,
                              height: 1.4,
                            ),
                          ),
                          const SizedBox(height: 20),
                          InkWell(
                            onTap: () {
                              setState(() {
                                _searchController.clear();
                                _selectedCategory = null;
                                _selectedCategoryName = null;
                                _isVerifiedOnly = false;
                                _isOpenNow = false;
                                _radiusM = 10000;
                              });
                              _executeSearch();
                            },
                            borderRadius: BorderRadius.circular(14),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 24,
                                vertical: 12,
                              ),
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  colors: [
                                    AbashyakaColors.signatureTeal,
                                    AbashyakaColors.metallicTeal,
                                  ],
                                ),
                                borderRadius: BorderRadius.circular(14),
                                boxShadow: [
                                  BoxShadow(
                                    color: AbashyakaColors.signatureTeal
                                        .withValues(alpha: 0.25),
                                    blurRadius: 8,
                                    offset: const Offset(0, 3),
                                  ),
                                ],
                              ),
                              child: const Text(
                                'Reset Filters & Show All',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                : RefreshIndicator(
                    onRefresh: () async => _executeSearch(),
                    color: AbashyakaColors.signatureTeal,
                    child: SafeArea(
                      top: false,
                      child: ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                        itemCount: items.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 12),
                        itemBuilder: (context, index) {
                          final biz = items[index];
                          return BusinessCard(
                            business: biz,
                            onTap: () => _onBusinessTapped(biz),
                            isFavorited: savedBusinessIds.contains(biz.id),
                            onFavoriteToggled: () => _toggleFavorite(biz.id),
                          );
                        },
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildPillChip({
    required String label,
    required IconData icon,
    required bool isActive,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isActive ? const Color(0xFFE6F7F7) : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isActive
                ? AbashyakaColors.metallicTeal
                : const Color(0xFFE2E8F0),
            width: isActive ? 1.5 : 1.0,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.02),
              blurRadius: 4,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 14,
              color: isActive
                  ? AbashyakaColors.metallicTeal
                  : const Color(0xFF64748B),
            ),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isActive ? FontWeight.w700 : FontWeight.w600,
                color: isActive
                    ? AbashyakaColors.signatureTeal
                    : AbashyakaColors.graphiteCharcoal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
