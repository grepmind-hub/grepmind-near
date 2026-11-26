import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:grepmind_mobile/core/data/category_listings_data.dart';
import 'package:grepmind_mobile/core/models/business.dart';
import 'package:grepmind_mobile/core/providers/app_provider.dart';
import 'package:grepmind_mobile/core/screens/business_detail_screen.dart';
import 'package:grepmind_mobile/core/theme/abashyaka_colors.dart';
import 'package:grepmind_mobile/core/theme/app_theme.dart';
import 'package:grepmind_mobile/core/widgets/skeleton_loader.dart';

/// Screen 16: Saved / Bookmarked Businesses.
///
/// Fully aligned with the 2026 Abashyaka Premium UI Design Standard:
/// - Metallic Teal Fluid Wave header art (assets/backgrounds/premium/home_background.webp)
/// - Premium Obsidian (#101820) headings and Graphite Charcoal (#374151) subtitles
/// - Admin-approved service places (Chhatia, Kuanpal, Jagatpur, Tangi, Chandikhol)
/// - Authentic category nature badges across all 18 categories
/// - Context-aware action buttons (Book Ride, Book Appointment, Book Service, View Store, etc.)
/// - Interactive favorite toggles with SnackBar undo and clear confirmation
/// - Suggested local gems in empty state for instant exploration and bookmarking
class SavedScreen extends ConsumerStatefulWidget {
  const SavedScreen({super.key});

  @override
  ConsumerState<SavedScreen> createState() => _SavedScreenState();
}

class _SavedScreenState extends ConsumerState<SavedScreen> {
  String _selectedFilter = 'all';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(favoritesProvider.notifier).load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(favoritesProvider);
    final filteredItems = _filterItems(state.items);


    return Scaffold(
      backgroundColor: AbashyakaColors.pearlWhite,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: AbashyakaColors.pureWhite,
        surfaceTintColor: Colors.transparent,
        flexibleSpace: Stack(
          fit: StackFit.expand,
          children: [
            Image.asset(
              'assets/backgrounds/premium/home_background.webp',
              fit: BoxFit.cover,
              alignment: Alignment.topCenter,
            ),
            Container(
              color: AbashyakaColors.pureWhite.withValues(alpha: 0.88),
            ),
          ],
        ),
        leading: Navigator.canPop(context)
            ? IconButton(
                icon: const Icon(
                  Icons.arrow_back_rounded,
                  color: AbashyakaColors.premiumObsidian,
                ),
                tooltip: 'Back',
                onPressed: () => Navigator.of(context).pop(),
              )
            : null,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Saved Places',
              style: AbashyakaTypography.pageTitle(
                color: AbashyakaColors.premiumObsidian,
                fontSize: 18,
              ).copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 2),
            Text(
              state.items.isEmpty
                  ? 'Chhatia, Kuanpal & nearby'
                  : '${state.items.length} ${state.items.length == 1 ? 'place' : 'places'} bookmarked',
              style: AbashyakaTypography.supportingText(
                color: AbashyakaColors.graphiteCharcoal,
                fontSize: 12,
              ),
            ),
          ],
        ),
        actions: [
          if (state.items.isNotEmpty)
            IconButton(
              icon: const Icon(
                Icons.delete_outline_rounded,
                color: AbashyakaColors.graphiteCharcoal,
              ),
              onPressed: _showClearDialog,
              tooltip: 'Clear all',
            ),
        ],
      ),
      body: state.isLoading
          ? ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: 4,
              separatorBuilder: (_, _) => const SizedBox(height: 12),
              itemBuilder: (_, _) => const SkeletonLoader(
                height: 108,
                radius: AbashyakaRadius.md,
              ),
            )
          : RefreshIndicator(
              color: AbashyakaColors.metallicTeal,
              backgroundColor: AbashyakaColors.pureWhite,
              onRefresh: () => ref.read(favoritesProvider.notifier).load(),
              child: state.error != null
                  ? _buildError(state.error!)
                  : state.items.isEmpty
                  ? _buildEmpty()
                  : _buildList(filteredItems, state.items.length),
            ),
    );
  }

  List<Business> _filterItems(List<Business> items) {
    if (_selectedFilter == 'all') return items;
    return items.where((biz) {
      final slug = biz.categorySlug.toLowerCase();
      switch (_selectedFilter) {
        case 'shops':
          return slug == 'shops' ||
              slug == 'grocery' ||
              slug == 'medicines' ||
              slug == 'fashion' ||
              slug == 'electronics' ||
              slug == 'home_furniture';
        case 'services':
          return slug == 'services' ||
              slug == 'automobile' ||
              slug == 'construction' ||
              slug == 'home_painting_decor' ||
              biz.isServiceProvider;
        case 'transport':
          return slug == 'cab_auto' || slug == 'transport';
        case 'dining':
          return slug == 'food' || slug == 'hotels_stays';
        case 'care':
          return slug == 'doctors' ||
              slug == 'beauty_salon' ||
              slug == 'fitness_wellness';
        default:
          return true;
      }
    }).toList();
  }

  Widget _buildList(List<Business> items, int totalSavedCount) {
    return Column(
      children: [
        // Filter tabs carousel
        _buildFilterBar(totalSavedCount),
        // Results list
        Expanded(
          child: items.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.filter_list_off_rounded,
                          size: 40,
                          color: AbashyakaColors.disabledText,
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'No saved places in this category',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: AbashyakaColors.premiumObsidian,
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextButton(
                          onPressed: () => setState(() => _selectedFilter = 'all'),
                          child: const Text('Show all saved places'),
                        ),
                      ],
                    ),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                  itemCount: items.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final biz = items[index];
                    return _SavedBusinessCard(
                      business: biz,
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => BusinessDetailScreen(businessId: biz.id),
                        ),
                      ),
                      onFavoriteToggle: () => _removeSavedBusiness(biz),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildFilterBar(int totalCount) {
    final filters = [
      {'id': 'all', 'label': 'All ($totalCount)'},
      {'id': 'shops', 'label': 'Shops & Retail'},
      {'id': 'services', 'label': 'Services & Pros'},
      {'id': 'transport', 'label': 'Cab & Auto'},
      {'id': 'dining', 'label': 'Food & Stays'},
      {'id': 'care', 'label': 'Care & Health'},
    ];

    return Container(
      height: 48,
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        itemCount: filters.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final filter = filters[index];
          final isSelected = _selectedFilter == filter['id'];
          return InkWell(
            onTap: () => setState(() => _selectedFilter = filter['id']!),
            borderRadius: BorderRadius.circular(20),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: isSelected
                    ? AbashyakaColors.signatureTeal
                    : AbashyakaColors.pureWhite,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isSelected
                      ? AbashyakaColors.signatureTeal
                      : AbashyakaColors.softGrey,
                ),
                boxShadow: isSelected
                    ? [
                        BoxShadow(
                          color: AbashyakaColors.signatureTeal.withValues(alpha: 0.2),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ]
                    : null,
              ),
              child: Text(
                filter['label']!,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                  color: isSelected
                      ? AbashyakaColors.pureWhite
                      : AbashyakaColors.graphiteCharcoal,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildEmpty() {
    // Curated recommendations for instant exploration
    final suggestedPlaces = CategoryListingsData.allListings.take(4).toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 32),
      child: Column(
        children: [
          // Empty illustration container
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: AbashyakaColors.pureWhite,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AbashyakaColors.softGrey),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF00545B).withValues(alpha: 0.04),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: AbashyakaColors.iceAquaWhite,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: AbashyakaColors.signatureTeal.withValues(alpha: 0.2),
                      width: 2,
                    ),
                  ),
                  child: const Icon(
                    Icons.favorite_rounded,
                    size: 36,
                    color: AbashyakaColors.signatureTeal,
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'No saved places yet',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: AbashyakaColors.premiumObsidian,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Tap the heart icon on any shop, doctor, driver stand, or artisan in Chhatia, Kuanpal & nearby to bookmark them here for instant 1-tap access.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.4,
                    color: AbashyakaColors.graphiteCharcoal,
                  ),
                ),
                const SizedBox(height: 20),
                FilledButton.icon(
                  key: const ValueKey('explore_nearby_button'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AbashyakaColors.signatureTeal,
                    foregroundColor: AbashyakaColors.pureWhite,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 22,
                      vertical: 12,
                    ),
                    elevation: 0,
                  ),
                  onPressed: () {
                    if (Navigator.canPop(context)) {
                      Navigator.pop(context);
                    }
                  },
                  icon: const Icon(Icons.near_me_rounded, size: 18),
                  label: const Text(
                    'Explore nearby places',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),

          // Suggested Places Header
          Row(
            children: const [
              Icon(
                Icons.stars_rounded,
                size: 20,
                color: AbashyakaColors.signatureTeal,
              ),
              SizedBox(width: 8),
              Text(
                'Popular in Chhatia & Nearby',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: AbashyakaColors.premiumObsidian,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Suggested cards
          ...suggestedPlaces.map(
            (biz) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _SuggestedBusinessCard(
                business: biz,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => BusinessDetailScreen(businessId: biz.id),
                  ),
                ),
                onBookmark: () async {
                  await ref.read(favoritesProvider.notifier).toggle(biz.id);
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Added ${biz.name} to saved places!'),
                        duration: const Duration(seconds: 2),
                        backgroundColor: AbashyakaColors.signatureTeal,
                      ),
                    );
                  }
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildError(String error) {
    final isAuthError =
        error.contains('401') || error.toLowerCase().contains('unauthorized');

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Container(
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
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF2F2),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isAuthError
                      ? Icons.lock_outline_rounded
                      : Icons.error_outline_rounded,
                  size: 32,
                  color: AbashyakaColors.error,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                isAuthError
                    ? 'Sign in to access bookmarks'
                    : 'Unable to load saved places',
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: AbashyakaColors.premiumObsidian,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                isAuthError
                    ? 'Sign in to sync your saved businesses and services across all your devices.'
                    : 'Please check your connection and tap retry to refresh your saved places.',
                style: const TextStyle(
                  color: AbashyakaColors.graphiteCharcoal,
                  fontSize: 13,
                  height: 1.4,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: AbashyakaColors.signatureTeal,
                  foregroundColor: AbashyakaColors.pureWhite,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 22,
                    vertical: 12,
                  ),
                ),
                onPressed: () => ref.read(favoritesProvider.notifier).load(),
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text(
                  'Refresh',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _removeSavedBusiness(Business biz) async {
    final removed = await ref.read(favoritesProvider.notifier).toggle(biz.id);
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Removed "${biz.name}" from saved places'),
        action: SnackBarAction(
          label: 'Undo',
          textColor: const Color(0xFFFDE047),
          onPressed: () {
            ref.read(favoritesProvider.notifier).toggle(biz.id);
          },
        ),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  void _showClearDialog() {
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'Clear all saved places?',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: AbashyakaColors.premiumObsidian,
          ),
        ),
        content: const Text(
          'This will remove all bookmarked businesses and services from your list.',
          style: TextStyle(
            fontSize: 13.5,
            color: AbashyakaColors.graphiteCharcoal,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text(
              'Cancel',
              style: TextStyle(color: AbashyakaColors.graphiteCharcoal),
            ),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AbashyakaColors.error,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onPressed: () async {
              Navigator.pop(dialogCtx);
              await ref.read(favoritesProvider.notifier).clearAll();
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('All saved places have been cleared.'),
                  duration: Duration(seconds: 2),
                ),
              );
            },
            child: const Text('Clear all'),
          ),
        ],
      ),
    );
  }
}

/// A high-gloss card representing a saved business with category nature pill,
/// rating, locality, action button, and favorite toggle.
class _SavedBusinessCard extends StatelessWidget {
  final Business business;
  final VoidCallback onTap;
  final VoidCallback onFavoriteToggle;

  const _SavedBusinessCard({
    required this.business,
    required this.onTap,
    required this.onFavoriteToggle,
  });

  @override
  Widget build(BuildContext context) {
    final natureColor = _getNatureColor(business.categorySlug);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AbashyakaColors.pureWhite,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AbashyakaColors.softGrey),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF00545B).withValues(alpha: 0.04),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Category Avatar with nature color
                Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    color: natureColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    _getCategoryIcon(business.categorySlug),
                    color: natureColor,
                    size: 26,
                  ),
                ),
                const SizedBox(width: 12),
                // Title & Badges
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        business.name,
                        style: const TextStyle(
                          fontSize: 15.5,
                          fontWeight: FontWeight.w700,
                          color: AbashyakaColors.premiumObsidian,
                          letterSpacing: -0.2,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 5),
                      Row(
                        children: [
                          // Nature Badge
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 2.5,
                            ),
                            decoration: BoxDecoration(
                              color: natureColor.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(5),
                            ),
                            child: Text(
                              business.categoryNatureLabel.toUpperCase(),
                              style: TextStyle(
                                fontSize: 9.5,
                                fontWeight: FontWeight.w800,
                                color: natureColor,
                                letterSpacing: 0.4,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          // Locality
                          const Icon(
                            Icons.location_on_rounded,
                            size: 13,
                            color: AbashyakaColors.mutedText,
                          ),
                          const SizedBox(width: 2),
                          Flexible(
                            child: Text(
                              business.locality ?? 'Chhatia',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: AbashyakaColors.graphiteCharcoal,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (business.isVerified) ...[
                            const SizedBox(width: 4),
                            const Icon(
                              Icons.verified_rounded,
                              size: 14,
                              color: Color(0xFF0D9488),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                // Red heart toggle button
                IconButton(
                  key: ValueKey('saved_heart_${business.id}'),
                  icon: const Icon(
                    Icons.favorite_rounded,
                    color: Color(0xFFE11D48),
                    size: 24,
                  ),
                  onPressed: onFavoriteToggle,
                  tooltip: 'Remove from saved',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Divider(height: 1, color: AbashyakaColors.unavailableSurface),
            const SizedBox(height: 10),
            // Bottom Row: Rating / Distance + Action CTA Button
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Rating & Distance
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: AbashyakaColors.warningSurface,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.star_rounded,
                            size: 13,
                            color: AbashyakaColors.warning,
                          ),
                          const SizedBox(width: 3),
                          Text(
                            (business.rating ?? 0) > 0
                                ? (business.rating ?? 4.8).toStringAsFixed(1)
                                : '4.8',
                            style: const TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w800,
                              color: AbashyakaColors.warning,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (business.distanceM != null) ...[
                      const SizedBox(width: 8),
                      Text(
                        business.distanceText,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AbashyakaColors.mutedText,
                        ),
                      ),
                    ],
                  ],
                ),
                // Context-Aware CTA Button
                InkWell(
                  onTap: onTap,
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 6.5,
                    ),
                    decoration: BoxDecoration(
                      color: AbashyakaColors.signatureTeal,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _getActionIcon(business.categorySlug),
                          size: 14,
                          color: AbashyakaColors.pureWhite,
                        ),
                        const SizedBox(width: 5),
                        Text(
                          business.primaryActionLabel,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: AbashyakaColors.pureWhite,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Color _getNatureColor(String category) {
    final slug = category.toLowerCase().trim().replaceAll('-', '_');
    switch (slug) {
      case 'cab_auto':
      case 'transport':
        return AbashyakaColors.warning; // Amber
      case 'doctors':
      case 'healthcare':
      case 'medicines':
        return const Color(0xFFE11D48); // Rose
      case 'education':
        return const Color(0xFF2563EB); // Royal Blue
      case 'food':
        return const Color(0xFFEA580C); // Warm Orange
      case 'beauty_salon':
        return const Color(0xFFDB2777); // Pink
      case 'fitness_wellness':
        return AbashyakaColors.success; // Emerald
      case 'hotels_stays':
        return const Color(0xFF7C3AED); // Purple
      default:
        return AbashyakaColors.signatureTeal;
    }
  }

  IconData _getCategoryIcon(String category) {
    final slug = category.toLowerCase().trim().replaceAll('-', '_');
    switch (slug) {
      case 'cab_auto':
      case 'transport':
        return Icons.local_taxi_rounded;
      case 'doctors':
      case 'healthcare':
        return Icons.medical_services_rounded;
      case 'medicines':
        return Icons.local_pharmacy_rounded;
      case 'food':
        return Icons.restaurant_rounded;
      case 'grocery':
        return Icons.local_grocery_store_rounded;
      case 'education':
        return Icons.school_rounded;
      case 'services':
        return Icons.handyman_rounded;
      case 'beauty_salon':
        return Icons.spa_rounded;
      case 'fitness_wellness':
        return Icons.fitness_center_rounded;
      case 'hotels_stays':
        return Icons.hotel_rounded;
      case 'automobile':
        return Icons.directions_car_rounded;
      case 'events_catering':
        return Icons.celebration_rounded;
      case 'fashion':
        return Icons.checkroom_rounded;
      case 'electronics':
        return Icons.devices_other_rounded;
      case 'home_furniture':
        return Icons.chair_rounded;
      default:
        return Icons.storefront_rounded;
    }
  }

  IconData _getActionIcon(String category) {
    final slug = category.toLowerCase().trim().replaceAll('-', '_');
    switch (slug) {
      case 'cab_auto':
      case 'transport':
        return Icons.local_taxi_rounded;
      case 'doctors':
        return Icons.calendar_month_rounded;
      case 'education':
        return Icons.chat_bubble_outline_rounded;
      case 'services':
      case 'automobile':
      case 'construction':
      case 'home_painting_decor':
        return Icons.handyman_rounded;
      case 'food':
        return Icons.restaurant_rounded;
      case 'hotels_stays':
        return Icons.hotel_rounded;
      case 'beauty_salon':
      case 'fitness_wellness':
        return Icons.event_available_rounded;
      default:
        return Icons.storefront_rounded;
    }
  }
}

/// Suggested business card shown in the empty state so users can explore and bookmark.
class _SuggestedBusinessCard extends StatelessWidget {
  final Business business;
  final VoidCallback onTap;
  final VoidCallback onBookmark;

  const _SuggestedBusinessCard({
    required this.business,
    required this.onTap,
    required this.onBookmark,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: AbashyakaColors.pureWhite,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AbashyakaColors.softGrey),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: AbashyakaColors.iceAquaWhite,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.storefront_rounded,
                color: AbashyakaColors.signatureTeal,
                size: 22,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    business.name,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AbashyakaColors.premiumObsidian,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${business.categoryNatureLabel} • ${business.locality ?? 'Chhatia'}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AbashyakaColors.graphiteCharcoal,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: AbashyakaColors.signatureTeal,
                side: const BorderSide(color: AbashyakaColors.signatureTeal),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
              ),
              onPressed: onBookmark,
              icon: const Icon(Icons.favorite_border_rounded, size: 15),
              label: const Text(
                'Save',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
