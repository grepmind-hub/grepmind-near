import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:grepmind_mobile/core/models/business.dart';
import 'package:grepmind_mobile/core/providers/app_provider.dart';
import 'package:grepmind_mobile/core/theme/app_theme.dart';
import 'package:grepmind_mobile/core/widgets/business_card.dart';
import 'package:grepmind_mobile/core/screens/business_detail_screen.dart';
import 'package:grepmind_mobile/core/screens/service_pro_screen.dart';
import 'package:grepmind_mobile/core/screens/nearby_map_screen.dart';

/// Screen 9: Search & Filter Results
/// Matching Grepmind Near UI/UX Showcase Screen 9 & Search and results.png.
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
  ConsumerState<SearchResultsScreen> createState() => _SearchResultsScreenState();
}

class _SearchResultsScreenState extends ConsumerState<SearchResultsScreen> {
  late final TextEditingController _searchController;
  String? _selectedCategory;
  String? _selectedCategoryName;
  int _radiusM = 5000;
  bool _isOpenNow = false;
  bool _isVerifiedOnly = false;
  String _sortBy = 'distance';

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController(text: widget.initialQuery ?? '');
    _selectedCategory = widget.initialCategory;
    _selectedCategoryName = widget.categoryName;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _executeSearch();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _executeSearch() {
    final q = _searchController.text.trim();
    if (q.isNotEmpty) {
      ref.read(businessesProvider.notifier).search(
        query: q,
        lat: 20.2961,
        lng: 85.8245,
        radiusM: _radiusM,
        categorySlug: _selectedCategory,
        openNow: _isOpenNow ? true : null,
        sort: _sortBy,
      );
    } else {
      ref.read(businessesProvider.notifier).nearby(
        lat: 20.2961,
        lng: 85.8245,
        radiusM: _radiusM,
      );
    }
  }

  void _showRadiusSheet() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                child: Text(
                  'Search Radius',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppTheme.mainText),
                ),
              ),
              const Divider(height: 1),
              ...[1000, 2000, 5000, 10000, 20000].map((r) {
                final km = r ~/ 1000;
                final isSel = _radiusM == r;
                return ListTile(
                  leading: Icon(
                    isSel ? Icons.radio_button_checked : Icons.radio_button_off,
                    color: isSel ? AppTheme.primary : const Color(0xFF94A3B8),
                  ),
                  title: Text(
                    'Within $km km',
                    style: TextStyle(
                      fontWeight: isSel ? FontWeight.w700 : FontWeight.w500,
                      color: isSel ? AppTheme.primary : AppTheme.mainText,
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
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                child: Text(
                  'Sort By',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppTheme.mainText),
                ),
              ),
              const Divider(height: 1),
              _buildSortOption('distance', 'Nearest (Distance)'),
              _buildSortOption('relevance', 'Best Match (Relevance)'),
              _buildSortOption('rating', 'Highest Rated'),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSortOption(String key, String title) {
    final isSel = _sortBy == key;
    return ListTile(
      leading: Icon(
        isSel ? Icons.radio_button_checked : Icons.radio_button_off,
        color: isSel ? AppTheme.primary : const Color(0xFF94A3B8),
      ),
      title: Text(
        title,
        style: TextStyle(
          fontWeight: isSel ? FontWeight.w700 : FontWeight.w500,
          color: isSel ? AppTheme.primary : AppTheme.mainText,
        ),
      ),
      onTap: () {
        Navigator.pop(context);
        setState(() => _sortBy = key);
        _executeSearch();
      },
    );
  }

  void _onBusinessTapped(Business biz) {
    // If it's a trade service pro, navigate to Screen 13 (Service Pro Profile)
    final serviceCategories = ['electrician', 'plumber', 'carpenter', 'tailor'];
    if (serviceCategories.contains(biz.categorySlug) || biz.acceptsRequests) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ServiceProScreen(business: biz),
        ),
      );
    } else {
      // Otherwise navigate to Screen 11 (Business Detail Profile)
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
    final favNotifier = ref.read(favoritesProvider.notifier);

    // Apply local filters if category or verified is active
    var items = state.items;
    if (_selectedCategory != null && _selectedCategory!.isNotEmpty && _selectedCategory != 'all') {
      items = items.where((b) => b.categorySlug == _selectedCategory).toList();
    }
    if (_isVerifiedOnly) {
      items = items.where((b) => b.verificationStatus == 'verified').toList();
    }
    if (_isOpenNow) {
      items = items.where((b) => b.isOpenNow).toList();
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: AppTheme.mainText),
          onPressed: () => Navigator.pop(context),
        ),
        titleSpacing: 0,
        title: Container(
          margin: const EdgeInsets.only(right: 8),
          height: 44,
          decoration: BoxDecoration(
            color: const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: TextField(
            controller: _searchController,
            onSubmitted: (_) => _executeSearch(),
            decoration: InputDecoration(
              hintText: 'Search shops, services, products...',
              hintStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 14),
              prefixIcon: const Icon(Icons.search_rounded, color: Color(0xFF94A3B8), size: 20),
              suffixIcon: _searchController.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear_rounded, color: Color(0xFF94A3B8), size: 18),
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
          IconButton(
            icon: const Icon(Icons.map_outlined, color: AppTheme.primary),
            tooltip: 'Map view',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const NearbyMapScreen()),
              );
            },
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
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
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
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: AppTheme.primaryContainer,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: AppTheme.primary),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                _selectedCategoryName ?? _selectedCategory!,
                                style: const TextStyle(
                                  color: AppTheme.primary,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 12,
                                ),
                              ),
                              const SizedBox(width: 4),
                              const Icon(Icons.close_rounded, size: 14, color: AppTheme.primary),
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
              const Divider(height: 1, thickness: 1, color: Color(0xFFE4E7EC)),
            ],
          ),
        ),
      ),
      body: Column(
        children: [
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
                    color: AppTheme.secondaryText,
                  ),
                ),
                if (_selectedCategory != null || _isVerifiedOnly || _isOpenNow || _radiusM != 5000)
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
                        color: AppTheme.primary,
                      ),
                    ),
                  ),
              ],
            ),
          ),

          // Results List
          Expanded(
            child: state.isLoading && items.isEmpty
                ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
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
                                  color: const Color(0xFFEFF6FF),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: const Icon(
                                  Icons.search_off_rounded,
                                  color: AppTheme.primary,
                                  size: 36,
                                ),
                              ),
                              const SizedBox(height: 16),
                              const Text(
                                'No businesses found',
                                style: TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w800,
                                  color: AppTheme.mainText,
                                ),
                              ),
                              const SizedBox(height: 6),
                              const Text(
                                'Try expanding your radius, clearing category filters, or searching a different term.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: AppTheme.secondaryText,
                                  height: 1.4,
                                ),
                              ),
                              const SizedBox(height: 18),
                              ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppTheme.primary,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                onPressed: () {
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
                                child: const Text(
                                  'Reset Filters & Show All',
                                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: () async => _executeSearch(),
                        color: AppTheme.primary,
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
                                onFavoriteToggled: () => favNotifier.toggle(biz.id),
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
          color: isActive ? AppTheme.primary.withValues(alpha: 0.1) : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isActive ? AppTheme.primary : const Color(0xFFE2E8F0),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 14,
              color: isActive ? AppTheme.primary : const Color(0xFF64748B),
            ),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isActive ? FontWeight.w700 : FontWeight.w600,
                color: isActive ? AppTheme.primary : AppTheme.mainText,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
