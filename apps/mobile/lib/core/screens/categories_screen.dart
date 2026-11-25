import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:grepmind_mobile/core/data/category_listings_data.dart';
import 'package:grepmind_mobile/core/models/business.dart';
import 'package:grepmind_mobile/core/providers/app_provider.dart';
import 'package:grepmind_mobile/core/screens/business_detail_screen.dart';
import 'package:grepmind_mobile/core/screens/search_results_screen.dart';
import 'package:grepmind_mobile/core/screens/service_pro_screen.dart';
import 'package:grepmind_mobile/core/theme/abashyaka_colors.dart';
import 'package:grepmind_mobile/core/theme/abashyaka_gradients.dart';
import 'package:grepmind_mobile/core/theme/abashyaka_typography.dart';
import 'package:grepmind_mobile/core/widgets/category_3d_icon.dart';
import 'package:url_launcher/url_launcher.dart';

/// Screen 8: Categories Directory
/// Displays the complete 19-category taxonomy with dedicated listing data,
/// nearest pincode and location-wise filtering with distance in km,
/// and the approved Pearl White & Metallic Teal Premium Design System.
class CategoriesScreen extends ConsumerStatefulWidget {
  static IconData getCategoryIcon(String? slug) =>
      _CategoriesScreenState.getCategoryIcon(slug);
  static Color getCategoryColor(String? slug) =>
      _CategoriesScreenState.getCategoryColor(slug);
  static Color getCategoryBackgroundColor(String? slug) =>
      _CategoriesScreenState.getCategoryBackgroundColor(slug);

  const CategoriesScreen({super.key});

  @override
  ConsumerState<CategoriesScreen> createState() => _CategoriesScreenState();
}

class _CategoriesScreenState extends ConsumerState<CategoriesScreen>
    with SingleTickerProviderStateMixin {
  final TextEditingController _searchController = TextEditingController();
  late final TabController _tabController;

  String _searchQuery = '';
  String _selectedSection = 'All';
  String _selectedLocality = 'All';
  String _selectedPincode = 'All';
  int _selectedRadiusM = 10000; // 10 km default
  String _sortBy = 'distance'; // 'distance' or 'rating'

  final List<String> _sections = const [
    'All',
    'Shops & Retail',
    'Home Services',
    'Health & Beauty',
    'Lifestyle & Tech',
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  static IconData getCategoryIcon(String? slug) {
    switch (slug) {
      case 'grocery':
        return Icons.shopping_basket_rounded;
      case 'hardware':
        return Icons.handyman_rounded;
      case 'medical':
        return Icons.medication_rounded;
      case 'restaurant':
        return Icons.restaurant_rounded;
      case 'salon':
        return Icons.face_rounded;
      case 'plumber':
        return Icons.plumbing_rounded;
      case 'electrician':
        return Icons.electrical_services_rounded;
      case 'carpenter':
        return Icons.carpenter_rounded;
      case 'tailor':
        return Icons.design_services_rounded;
      case 'general':
        return Icons.storefront_rounded;
      case 'fashion':
        return Icons.checkroom_rounded;
      case 'electronics':
        return Icons.devices_rounded;
      case 'home_kitchen':
        return Icons.kitchen_rounded;
      case 'health_wellness':
        return Icons.spa_rounded;
      case 'sports_fitness':
        return Icons.fitness_center_rounded;
      case 'automotive':
        return Icons.local_taxi_rounded;
      case 'books_stationery':
        return Icons.menu_book_rounded;
      case 'cleaning':
        return Icons.cleaning_services_rounded;
      case 'hotel':
        return Icons.hotel_rounded;
      default:
        return Icons.category_rounded;
    }
  }

  static Color getCategoryBackgroundColor(String? slug) {
    switch (slug) {
      case 'grocery':
        return const Color(0xFFE6F4EA);
      case 'restaurant':
        return const Color(0xFFFEF3C7);
      case 'medical':
        return const Color(0xFFE0F2FE);
      case 'hardware':
        return const Color(0xFFFFEDD5);
      case 'hotel':
        return const Color(0xFFDCFCE7);
      case 'salon':
        return const Color(0xFFFCE7F3);
      case 'plumber':
        return const Color(0xFFE0F2FE);
      case 'electrician':
        return const Color(0xFFFEF9C3);
      case 'carpenter':
        return const Color(0xFFFFEDD5);
      case 'tailor':
        return const Color(0xFFF3E8FF);
      case 'general':
        return const Color(0xFFFFE4E6);
      case 'fashion':
        return const Color(0xFFFFE4E6);
      case 'electronics':
        return const Color(0xFFEEF2FF);
      case 'home_kitchen':
        return const Color(0xFFCCFBF1);
      case 'health_wellness':
        return const Color(0xFFD1FAE5);
      case 'sports_fitness':
        return const Color(0xFFFEF3C7);
      case 'automotive':
        return const Color(0xFFE2E8F0);
      case 'books_stationery':
        return const Color(0xFFE0E7FF);
      case 'cleaning':
        return const Color(0xFFE0F2FE);
      default:
        return AbashyakaColors.iceAquaWhite;
    }
  }

  static Color getCategoryColor(String? slug) {
    switch (slug) {
      case 'grocery':
        return const Color(0xFF16A34A);
      case 'hardware':
        return const Color(0xFFD97706);
      case 'medical':
        return const Color(0xFF0284C7);
      case 'restaurant':
        return const Color(0xFFEA580C);
      case 'hotel':
        return AbashyakaColors.signatureTeal;
      case 'salon':
        return const Color(0xFFDB2777);
      case 'plumber':
        return const Color(0xFF0284C7);
      case 'electrician':
        return const Color(0xFFD97706);
      case 'carpenter':
        return const Color(0xFFB45309);
      case 'tailor':
        return const Color(0xFF7C3AED);
      case 'general':
        return const Color(0xFFDC2626);
      case 'fashion':
        return const Color(0xFFE11D48);
      case 'electronics':
        return const Color(0xFF4F46E5);
      case 'home_kitchen':
        return AbashyakaColors.metallicTeal;
      case 'health_wellness':
        return const Color(0xFF059669);
      case 'sports_fitness':
        return const Color(0xFFD97706);
      case 'automotive':
        return AbashyakaColors.signatureTeal;
      case 'books_stationery':
        return const Color(0xFF6366F1);
      case 'cleaning':
        return const Color(0xFF0284C7);
      default:
        return AbashyakaColors.metallicTeal;
    }
  }

  bool _matchesSection(Category cat, String section) {
    if (section == 'All') return true;
    final slug = cat.slug;
    if (section == 'Shops & Retail') {
      return [
        'grocery',
        'general',
        'fashion',
        'books_stationery',
        'restaurant',
      ].contains(slug);
    }
    if (section == 'Home Services') {
      return [
        'electrician',
        'plumber',
        'carpenter',
        'hardware',
        'cleaning',
        'home_kitchen',
      ].contains(slug);
    }
    if (section == 'Health & Beauty') {
      return ['medical', 'salon', 'health_wellness'].contains(slug);
    }
    if (section == 'Lifestyle & Tech') {
      return [
        'electronics',
        'sports_fitness',
        'automotive',
        'tailor',
        'hotel',
      ].contains(slug);
    }
    return true;
  }

  void _showLocationPincodeModal() {
    final localities = [
      'All',
      ...CategoryListingsData.getAvailableLocalities(),
    ];
    final pincodes = ['All', ...CategoryListingsData.getAvailablePincodes()];

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => Container(
          decoration: const BoxDecoration(
            color: AbashyakaColors.pureWhite,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 44,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AbashyakaColors.aquaSilverBorder,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Filter by Location & Pincode',
                    style: AbashyakaTypography.sectionTitle(fontSize: 18),
                  ),
                  TextButton(
                    onPressed: () {
                      setState(() {
                        _selectedLocality = 'All';
                        _selectedPincode = 'All';
                        _selectedRadiusM = 10000;
                      });
                      Navigator.pop(ctx);
                    },
                    child: Text(
                      'Reset',
                      style: AbashyakaTypography.supportingText(
                        color: AbashyakaColors.signatureTeal,
                        fontSize: 13,
                      ).copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Select nearest Odisha locality or pincode to discover close merchants and services.',
                style: AbashyakaTypography.bodyMedium(fontSize: 12.5),
              ),
              const SizedBox(height: 16),
              // Locality Chips
              Text(
                'Nearest Localities',
                style: AbashyakaTypography.cardTitle(fontSize: 14),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: localities.map((loc) {
                  final isSel = _selectedLocality == loc;
                  return ChoiceChip(
                    label: Text(loc),
                    selected: isSel,
                    selectedColor: AbashyakaColors.metallicTeal,
                    backgroundColor: AbashyakaColors.pearlWhite,
                    labelStyle: TextStyle(
                      color: isSel ? Colors.white : AbashyakaColors.inkBlack,
                      fontWeight: isSel ? FontWeight.w700 : FontWeight.w500,
                      fontSize: 12.5,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                      side: BorderSide(
                        color: isSel
                            ? AbashyakaColors.metallicTeal
                            : AbashyakaColors.aquaSilverBorder,
                      ),
                    ),
                    onSelected: (val) {
                      setModalState(() => _selectedLocality = loc);
                      setState(() => _selectedLocality = loc);
                    },
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),
              // Pincode Chips
              Text(
                'Postal Code (Pincode)',
                style: AbashyakaTypography.cardTitle(fontSize: 14),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: pincodes.map((pin) {
                  final isSel = _selectedPincode == pin;
                  return ChoiceChip(
                    label: Text(pin == 'All' ? 'All Pincodes' : pin),
                    selected: isSel,
                    selectedColor: AbashyakaColors.signatureTeal,
                    backgroundColor: AbashyakaColors.pearlWhite,
                    labelStyle: TextStyle(
                      color: isSel ? Colors.white : AbashyakaColors.inkBlack,
                      fontWeight: isSel ? FontWeight.w700 : FontWeight.w500,
                      fontSize: 12.5,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                      side: BorderSide(
                        color: isSel
                            ? AbashyakaColors.signatureTeal
                            : AbashyakaColors.aquaSilverBorder,
                      ),
                    ),
                    onSelected: (val) {
                      setModalState(() => _selectedPincode = pin);
                      setState(() => _selectedPincode = pin);
                    },
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),
              // Radius Filter
              Text(
                'Distance Radius',
                style: AbashyakaTypography.cardTitle(fontSize: 14),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  for (final r in [2000, 5000, 10000, 20000])
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 3),
                        child: InkWell(
                          onTap: () {
                            setModalState(() => _selectedRadiusM = r);
                            setState(() => _selectedRadiusM = r);
                          },
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            decoration: BoxDecoration(
                              color: _selectedRadiusM == r
                                  ? AbashyakaColors.metallicTeal
                                  : AbashyakaColors.pearlWhite,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: _selectedRadiusM == r
                                    ? AbashyakaColors.metallicTeal
                                    : AbashyakaColors.aquaSilverBorder,
                              ),
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              '${r ~/ 1000} km',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: _selectedRadiusM == r
                                    ? FontWeight.w700
                                    : FontWeight.w600,
                                color: _selectedRadiusM == r
                                    ? Colors.white
                                    : AbashyakaColors.inkBlack,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 22),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: AbashyakaGradients.metallicButton,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(ctx),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      shadowColor: Colors.transparent,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: Text(
                      'Apply Location Filter',
                      style: AbashyakaTypography.buttonText(),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final catState = ref.watch(categoriesProvider);
    final allCategories = catState.items;

    // Filter categories by query and section
    final filteredCategories = allCategories.where((cat) {
      final matchesQuery =
          _searchQuery.isEmpty ||
          cat.name.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          (cat.description?.toLowerCase().contains(
                _searchQuery.toLowerCase(),
              ) ??
              false);
      final matchesSec = _matchesSection(cat, _selectedSection);
      return matchesQuery && matchesSec;
    }).toList();

    // Listings matching all active filters
    final matchingListings = CategoryListingsData.getListingsForCategory(
      null,
      query: _searchQuery,
      locality: _selectedLocality,
      pincode: _selectedPincode,
      maxRadiusM: _selectedRadiusM,
      sortBy: _sortBy,
    );

    return Scaffold(
      backgroundColor: AbashyakaColors.pearlWhite,
      appBar: AppBar(
        backgroundColor: AbashyakaColors.pureWhite,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_rounded,
            color: AbashyakaColors.inkBlack,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Categories Directory',
          style: AbashyakaTypography.pageTitle(fontSize: 18),
        ),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 16),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: AbashyakaColors.tealTint,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: AbashyakaColors.metallicTeal.withValues(alpha: 0.25),
              ),
            ),
            child: Text(
              '${allCategories.length} Categories',
              style: const TextStyle(
                color: AbashyakaColors.metallicTeal,
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
            ),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: Container(
            color: AbashyakaColors.pureWhite,
            child: TabBar(
              controller: _tabController,
              indicatorColor: AbashyakaColors.metallicTeal,
              indicatorWeight: 3,
              labelColor: AbashyakaColors.signatureTeal,
              unselectedLabelColor: AbashyakaColors.secondaryText,
              labelStyle: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 14,
              ),
              tabs: [
                Tab(text: 'Categories (${allCategories.length})'),
                Tab(text: 'Explore Listings (${matchingListings.length})'),
              ],
            ),
          ),
        ),
      ),
      body: Column(
        children: [
          // ---------------------------------------------------------
          // Pincode & Locality Filter Ribbon (Always Visible)
          // ---------------------------------------------------------
          Container(
            color: AbashyakaColors.pureWhite,
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
            child: Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: _showLocationPincodeModal,
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 7,
                      ),
                      decoration: BoxDecoration(
                        color: AbashyakaColors.iceAquaWhite,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: AbashyakaColors.aquaSilverBorder,
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.location_on_rounded,
                            size: 16,
                            color: AbashyakaColors.signatureTeal,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              _selectedLocality == 'All' &&
                                      _selectedPincode == 'All'
                                  ? 'All Odisha Localities & Pincodes'
                                  : '${_selectedLocality != 'All' ? _selectedLocality : 'All'} (${_selectedPincode != 'All' ? _selectedPincode : 'Any'})',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: AbashyakaColors.signatureTeal,
                              ),
                            ),
                          ),
                          const Icon(
                            Icons.keyboard_arrow_down_rounded,
                            size: 18,
                            color: AbashyakaColors.signatureTeal,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                InkWell(
                  onTap: _showLocationPincodeModal,
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: AbashyakaColors.tealTint,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: AbashyakaColors.metallicTeal.withValues(
                          alpha: 0.3,
                        ),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.near_me_rounded,
                          size: 14,
                          color: AbashyakaColors.metallicTeal,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${_selectedRadiusM ~/ 1000} km',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: AbashyakaColors.metallicTeal,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ---------------------------------------------------------
          // Search & Section Filter Bar
          // ---------------------------------------------------------
          Container(
            color: AbashyakaColors.pureWhite,
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: Column(
              children: [
                Container(
                  decoration: BoxDecoration(
                    color: AbashyakaColors.pearlWhite,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AbashyakaColors.aquaSilverBorder),
                  ),
                  child: TextField(
                    controller: _searchController,
                    onChanged: (v) => setState(() => _searchQuery = v),
                    style: AbashyakaTypography.bodyLarge(fontSize: 14),
                    decoration: InputDecoration(
                      hintText: 'Search 19 categories, shops or services...',
                      hintStyle: AbashyakaTypography.bodyMedium(
                        color: AbashyakaColors.secondaryText,
                        fontSize: 13.5,
                      ),
                      prefixIcon: const Icon(
                        Icons.search_rounded,
                        color: AbashyakaColors.metallicTeal,
                        size: 22,
                      ),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(
                                Icons.clear_rounded,
                                color: AbashyakaColors.secondaryText,
                                size: 18,
                              ),
                              onPressed: () {
                                _searchController.clear();
                                setState(() => _searchQuery = '');
                              },
                            )
                          : null,
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                // Horizontal section pill filter
                SizedBox(
                  height: 38,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: _sections.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 8),
                    itemBuilder: (_, index) {
                      final sec = _sections[index];
                      final isSelected = _selectedSection == sec;
                      return InkWell(
                        onTap: () => setState(() => _selectedSection = sec),
                        borderRadius: BorderRadius.circular(20),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            gradient: isSelected
                                ? AbashyakaGradients.metallicButton
                                : null,
                            color: isSelected
                                ? null
                                : AbashyakaColors.pureWhite,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: isSelected
                                  ? AbashyakaColors.metallicTeal
                                  : AbashyakaColors.aquaSilverBorder,
                            ),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            sec,
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: isSelected
                                  ? FontWeight.w700
                                  : FontWeight.w600,
                              color: isSelected
                                  ? Colors.white
                                  : AbashyakaColors.inkBlack,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),

          const Divider(
            height: 1,
            thickness: 1,
            color: AbashyakaColors.aquaSilverBorder,
          ),

          // ---------------------------------------------------------
          // Tab Content: Tab 1 (Categories) & Tab 2 (Direct Listings)
          // ---------------------------------------------------------
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                // TAB 1: 19 Category Taxonomy Directory
                _buildCategoriesTab(filteredCategories),

                // TAB 2: Direct Filtered Listings Across Odisha
                _buildListingsTab(matchingListings),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoriesTab(List<Category> categories) {
    if (categories.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: const BoxDecoration(
                color: AbashyakaColors.iceAquaWhite,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.search_off_rounded,
                color: AbashyakaColors.secondaryText,
                size: 32,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              'No categories match "$_searchQuery"',
              style: AbashyakaTypography.cardTitle(fontSize: 16),
            ),
            const SizedBox(height: 4),
            Text(
              'Try clearing search or choosing another section',
              style: AbashyakaTypography.bodyMedium(fontSize: 13),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      key: const Key('categories_page_scroll'),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      itemCount: categories.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final category = categories[index];
        final color = getCategoryColor(category.slug);

        // Pre-compute listing count and nearest distance in km for this category
        final catListings = CategoryListingsData.getListingsForCategory(
          category.slug,
          locality: _selectedLocality,
          pincode: _selectedPincode,
          maxRadiusM: _selectedRadiusM,
        );
        final count = catListings.length;
        final nearest = catListings.isNotEmpty ? catListings.first : null;
        final nearestText = nearest?.distanceText ?? '0.5 km';
        final nearestPin = nearest?.postalCode ?? '751007';

        return InkWell(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => SearchResultsScreen(
                  initialCategory: category.slug,
                  categoryName: category.name,
                ),
              ),
            );
          },
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.all(13),
            decoration: BoxDecoration(
              color: AbashyakaColors.pureWhite,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AbashyakaColors.aquaSilverBorder),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.02),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // 3D icon or styled container
                Container(
                  width: 54,
                  height: 54,
                  decoration: BoxDecoration(
                    color: getCategoryBackgroundColor(category.slug),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: color.withValues(alpha: 0.15),
                      width: 1,
                    ),
                  ),
                  child: Center(
                    child: Category3DIcon(categoryId: category.slug, size: 38),
                  ),
                ),
                const SizedBox(width: 14),
                // Category Title & Subtitle
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        category.name,
                        style: AbashyakaTypography.cardTitle(fontSize: 15),
                      ),
                      if (category.description != null &&
                          category.description!.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          category.description!,
                          style: AbashyakaTypography.bodyMedium(fontSize: 12),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                      const SizedBox(height: 6),
                      // Verified listings badge with km & pincode
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: AbashyakaColors.iceAquaWhite,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.store_rounded,
                                  size: 11,
                                  color: AbashyakaColors.metallicTeal,
                                ),
                                const SizedBox(width: 3),
                                Text(
                                  '$count available',
                                  style: const TextStyle(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w700,
                                    color: AbashyakaColors.signatureTeal,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: AbashyakaColors.pearlWhite,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: AbashyakaColors.aquaSilverBorder,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.near_me_rounded,
                                  size: 10,
                                  color: AbashyakaColors.secondaryText,
                                ),
                                const SizedBox(width: 2),
                                Text(
                                  '$nearestText • $nearestPin',
                                  style: const TextStyle(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w600,
                                    color: AbashyakaColors.secondaryText,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: AbashyakaColors.pearlWhite,
                    shape: BoxShape.circle,
                    border: Border.all(color: AbashyakaColors.aquaSilverBorder),
                  ),
                  child: const Icon(
                    Icons.chevron_right_rounded,
                    color: AbashyakaColors.metallicTeal,
                    size: 20,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildListingsTab(List<Business> listings) {
    if (listings.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: const BoxDecoration(
                color: AbashyakaColors.iceAquaWhite,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.location_off_rounded,
                color: AbashyakaColors.secondaryText,
                size: 32,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              'No listings in $_selectedLocality within ${_selectedRadiusM ~/ 1000} km',
              style: AbashyakaTypography.cardTitle(fontSize: 15),
            ),
            const SizedBox(height: 6),
            Text(
              'Try expanding the radius or resetting the location filter',
              style: AbashyakaTypography.bodyMedium(fontSize: 12.5),
            ),
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: () {
                setState(() {
                  _selectedLocality = 'All';
                  _selectedPincode = 'All';
                  _selectedRadiusM = 20000;
                });
              },
              style: OutlinedButton.styleFrom(
                foregroundColor: AbashyakaColors.signatureTeal,
                side: const BorderSide(color: AbashyakaColors.metallicTeal),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text('Show All Odisha Places'),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      itemCount: listings.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final b = listings[index];
        final isService = Business.serviceTradeCategories.contains(
          b.categorySlug,
        );

        return InkWell(
          onTap: () {
            if (isService) {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ServiceProScreen(business: b),
                ),
              );
            } else {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => BusinessDetailScreen(businessId: b.id),
                ),
              );
            }
          },
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AbashyakaColors.pureWhite,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AbashyakaColors.aquaSilverBorder),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.02),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Category icon / avatar
                Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    color: getCategoryBackgroundColor(b.categorySlug),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Center(
                    child: Category3DIcon(categoryId: b.categorySlug, size: 34),
                  ),
                ),
                const SizedBox(width: 12),
                // Details
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              b.name,
                              style: AbashyakaTypography.cardTitle(
                                fontSize: 15,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: AbashyakaColors.iceAquaWhite,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.star_rounded,
                                  size: 13,
                                  color: AbashyakaColors.metallicGold,
                                ),
                                const SizedBox(width: 2),
                                Text(
                                  (b.rating ?? 4.8).toStringAsFixed(1),
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: AbashyakaColors.ratingText,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      // Category & Locality + Pincode
                      Row(
                        children: [
                          Text(
                            b.categoryName ?? b.categorySlug,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: AbashyakaColors.signatureTeal,
                            ),
                          ),
                          const Text(
                            ' • ',
                            style: TextStyle(
                              color: AbashyakaColors.secondaryText,
                            ),
                          ),
                          Expanded(
                            child: Text(
                              '${b.locality ?? 'Odisha'} (${b.postalCode ?? ''})',
                              style: AbashyakaTypography.supportingText(
                                fontSize: 12,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 5),
                      // Distance in km & Call Action
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: AbashyakaColors.pearlWhite,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: AbashyakaColors.aquaSilverBorder,
                              ),
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.near_me_rounded,
                                  size: 11,
                                  color: AbashyakaColors.metallicTeal,
                                ),
                                const SizedBox(width: 3),
                                Text(
                                  b.distanceText,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: AbashyakaColors.metallicTeal,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (b.phoneE164 != null)
                            InkWell(
                              onTap: () async {
                                final uri = Uri.parse('tel:${b.phoneE164}');
                                if (await canLaunchUrl(uri)) {
                                  await launchUrl(uri);
                                }
                              },
                              borderRadius: BorderRadius.circular(8),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                child: Row(
                                  children: [
                                    const Icon(
                                      Icons.phone_rounded,
                                      size: 13,
                                      color: AbashyakaColors.signatureTeal,
                                    ),
                                    const SizedBox(width: 3),
                                    Text(
                                      'Call',
                                      style: TextStyle(
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.w700,
                                        color: AbashyakaColors.signatureTeal,
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
              ],
            ),
          ),
        );
      },
    );
  }
}
