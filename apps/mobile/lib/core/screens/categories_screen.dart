import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:grepmind_mobile/core/models/business.dart';
import 'package:grepmind_mobile/core/providers/app_provider.dart';
import 'package:grepmind_mobile/core/theme/app_theme.dart';
import 'package:grepmind_mobile/core/screens/search_results_screen.dart';

/// Screen 8: Categories Directory
/// Displays the full directory of categories with search and category filtering,
/// matching the Grepmind Near UI/UX Showcase Screen 8.
class CategoriesScreen extends ConsumerStatefulWidget {
  const CategoriesScreen({super.key});

  @override
  ConsumerState<CategoriesScreen> createState() => _CategoriesScreenState();
}

class _CategoriesScreenState extends ConsumerState<CategoriesScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  String _selectedSection = 'All';

  final List<String> _sections = const [
    'All',
    'Shops & Retail',
    'Home Services',
    'Health & Beauty',
    'Lifestyle & Tech',
  ];

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  static IconData getCategoryIcon(String? slug) {
    switch (slug) {
      case 'grocery':
        return Icons.local_grocery_store_rounded;
      case 'hardware':
        return Icons.build_rounded;
      case 'medical':
        return Icons.local_pharmacy_rounded;
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
        return Icons.directions_car_rounded;
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

  static Color getCategoryColor(String? slug) {
    switch (slug) {
      case 'grocery':
        return const Color(0xFF16A34A);
      case 'hardware':
        return const Color(0xFFD97706);
      case 'medical':
        return const Color(0xFF9333EA);
      case 'restaurant':
        return const Color(0xFFEA580C);
      case 'hotel':
        return const Color(0xFF0F766E);
      case 'salon':
        return const Color(0xFFDB2777);
      case 'plumber':
        return const Color(0xFF0284C7);
      case 'electrician':
        return const Color(0xFF2563EB);
      case 'carpenter':
        return const Color(0xFFB45309);
      case 'tailor':
        return const Color(0xFF7C3AED);
      case 'general':
        return const Color(0xFF0F766E);
      case 'fashion':
        return const Color(0xFFE11D48);
      case 'electronics':
        return const Color(0xFF4F46E5);
      case 'home_kitchen':
        return const Color(0xFF0D9488);
      case 'health_wellness':
        return const Color(0xFF059669);
      case 'sports_fitness':
        return const Color(0xFFD97706);
      case 'automotive':
        return const Color(0xFF475569);
      case 'books_stationery':
        return const Color(0xFF6366F1);
      case 'cleaning':
        return const Color(0xFF0284C7);
      default:
        return const Color(0xFF2457D6);
    }
  }

  bool _matchesSection(Category cat, String section) {
    if (section == 'All') return true;
    final slug = cat.slug;
    if (section == 'Shops & Retail') {
      return ['grocery', 'general', 'fashion', 'books_stationery', 'restaurant'].contains(slug);
    }
    if (section == 'Home Services') {
      return ['electrician', 'plumber', 'carpenter', 'hardware', 'cleaning', 'home_kitchen'].contains(slug);
    }
    if (section == 'Health & Beauty') {
      return ['medical', 'salon', 'health_wellness'].contains(slug);
    }
    if (section == 'Lifestyle & Tech') {
      return ['electronics', 'sports_fitness', 'automotive', 'tailor'].contains(slug);
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final catState = ref.watch(categoriesProvider);
    final allCategories = catState.items;

    // Filter categories by query and section
    final filteredCategories = allCategories.where((cat) {
      final matchesQuery = _searchQuery.isEmpty ||
          cat.name.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          (cat.description?.toLowerCase().contains(_searchQuery.toLowerCase()) ?? false);
      final matchesSec = _matchesSection(cat, _selectedSection);
      return matchesQuery && matchesSec;
    }).toList();

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
        title: const Text(
          'Categories Directory',
          style: TextStyle(
            color: AppTheme.mainText,
            fontWeight: FontWeight.w800,
            fontSize: 18,
            letterSpacing: -0.3,
          ),
        ),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 16),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: AppTheme.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              '${allCategories.length} items',
              style: const TextStyle(
                color: AppTheme.primary,
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
            ),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(color: const Color(0xFFE4E7EC), height: 1),
        ),
      ),
      body: Column(
        children: [
          // Search categories bar
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: TextField(
                controller: _searchController,
                onChanged: (v) => setState(() => _searchQuery = v),
                decoration: InputDecoration(
                  hintText: 'Search categories or services...',
                  hintStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 14),
                  prefixIcon: const Icon(Icons.search_rounded, color: Color(0xFF94A3B8), size: 22),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear_rounded, color: Color(0xFF94A3B8), size: 18),
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _searchQuery = '');
                          },
                        )
                      : null,
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 13),
                ),
              ),
            ),
          ),

          // Horizontal section pill filter
          Container(
            color: Colors.white,
            padding: const EdgeInsets.only(bottom: 12),
            child: SizedBox(
              height: 38,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: _sections.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (_, index) {
                  final sec = _sections[index];
                  final isSelected = _selectedSection == sec;
                  return InkWell(
                    onTap: () => setState(() => _selectedSection = sec),
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: isSelected ? AppTheme.primary : const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: isSelected ? AppTheme.primary : const Color(0xFFE2E8F0),
                        ),
                      ),
                      child: Text(
                        sec,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                          color: isSelected ? Colors.white : AppTheme.mainText,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),

          const Divider(height: 1, thickness: 1, color: Color(0xFFE4E7EC)),

          // Categories directory list
          Expanded(
            child: catState.isLoading && allCategories.isEmpty
                ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
                : filteredCategories.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              width: 64,
                              height: 64,
                              decoration: const BoxDecoration(
                                color: Color(0xFFF1F5F9),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.category_outlined, color: Color(0xFF94A3B8), size: 32),
                            ),
                            const SizedBox(height: 14),
                            const Text(
                              'No categories found',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: AppTheme.mainText,
                              ),
                            ),
                            const SizedBox(height: 4),
                            const Text(
                              'Try adjusting your search query',
                              style: TextStyle(color: AppTheme.secondaryText, fontSize: 13),
                            ),
                          ],
                        ),
                      )
                    : SafeArea(
                        top: false,
                        child: ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16, 14, 16, 32),
                          itemCount: filteredCategories.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 12),
                          itemBuilder: (context, index) {
                          final category = filteredCategories[index];
                          final icon = getCategoryIcon(category.slug);
                          final color = getCategoryColor(category.slug);

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
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: const Color(0xFFE4E7EC)),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.02),
                                    blurRadius: 6,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 52,
                                    height: 52,
                                    decoration: BoxDecoration(
                                      color: color.withValues(alpha: 0.12),
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                    child: Icon(icon, color: color, size: 26),
                                  ),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          category.name,
                                          style: const TextStyle(
                                            fontSize: 15,
                                            fontWeight: FontWeight.w700,
                                            color: AppTheme.mainText,
                                            letterSpacing: -0.2,
                                          ),
                                        ),
                                        if (category.description != null && category.description!.isNotEmpty) ...[
                                          const SizedBox(height: 3),
                                          Text(
                                            category.description!,
                                            style: const TextStyle(
                                              fontSize: 12,
                                              color: AppTheme.secondaryText,
                                              height: 1.25,
                                            ),
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Container(
                                    width: 32,
                                    height: 32,
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFF8FAFC),
                                      shape: BoxShape.circle,
                                      border: Border.all(color: const Color(0xFFE2E8F0)),
                                    ),
                                    child: const Icon(
                                      Icons.chevron_right_rounded,
                                      color: Color(0xFF64748B),
                                      size: 20,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
          ),
        ],
      ),
    );
  }
}
