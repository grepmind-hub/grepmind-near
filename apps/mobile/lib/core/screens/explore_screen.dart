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

  final List<Map<String, dynamic>> _categories = const [
    {'label': 'All', 'icon': Icons.grid_view, 'slug': 'all'},
    {'label': 'Grocery', 'icon': Icons.store, 'slug': 'grocery'},
    {'label': 'Hardware', 'icon': Icons.build, 'slug': 'hardware'},
    {'label': 'Medical', 'icon': Icons.local_pharmacy, 'slug': 'medical'},
    {'label': 'Restaurant', 'icon': Icons.restaurant, 'slug': 'restaurant'},
    {'label': 'Plumber', 'icon': Icons.plumbing, 'slug': 'plumber'},
    {'label': 'Electrician', 'icon': Icons.electrical_services, 'slug': 'electrician'},
    {'label': 'Carpenter', 'icon': Icons.carpenter, 'slug': 'carpenter'},
  ];

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
    if (q.isEmpty) return;
    ref.read(businessesProvider.notifier).search(query: q, lat: 20.46, lng: 85.88);
    FocusScope.of(context).unfocus();
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
            // Location selector + notification.
            Padding(
              padding: const EdgeInsets.fromLTRB(kScreenPadding, 12, kScreenPadding, 8),
              child: Row(
                children: [
                  const Icon(Icons.location_on_outlined, color: AppTheme.primary, size: 20),
                  const SizedBox(width: 6),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () {},
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        side: const BorderSide(color: AppTheme.border),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      child: const Text(
                        'Bhubaneswar, Odisha',
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    decoration: BoxDecoration(
                      color: AppTheme.primaryContainer,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const IconButton(
                      icon: Icon(Icons.notifications_none, color: AppTheme.primary, size: 22),
                      onPressed: null,
                    ),
                  ),
                ],
              ),
            ),

            // Search field.
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: kScreenPadding),
              child: PremiumCard(
                padding: EdgeInsets.zero,
                radius: 12,
                borderColor: AppTheme.border,
                color: AppTheme.surface,
                child: TextField(
                  controller: _searchController,
                  onChanged: _onSearchChanged,
                  onSubmitted: (_) => _search(),
                  decoration: InputDecoration(
                    hintText: 'Search shops, services, products',
                    hintStyle: const TextStyle(color: AppTheme.hintText, fontSize: 14),
                    prefixIcon: const Icon(Icons.search, color: AppTheme.hintText, size: 20),
                    suffixIcon: _isSearching
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                        : IconButton(
                            icon: const Icon(Icons.clear, color: AppTheme.hintText),
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _isSearching = false);
                            },
                          ),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Horizontal category list.
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: kScreenPadding),
              child: SizedBox(
                height: 94,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: _categories.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 10),
                  itemBuilder: (_, i) {
                    final cat = _categories[i];
                    final selected = _selectedCategory == cat['slug'];
                    return CategoryChip(
                      label: cat['label'] as String,
                      icon: cat['icon'] as IconData?,
                      isSelected: selected,
                      onTap: () {
                        setState(() => _selectedCategory = cat['slug'] as String);
                        ref.read(businessesProvider.notifier).search(
                              query: '',
                              lat: 20.46,
                              lng: 85.88,
                              categorySlug: cat['slug'] == 'all' ? null : cat['slug'] as String,
                            );
                      },
                    );
                  },
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Featured offer banner.
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: kScreenPadding),
              child: BannerCard(
                title: 'Monsoon Home Care Sale',
                subtitle: 'Up to 20% off on plumbing & electrical services this week',
                imageUrl: null,
                height: 120,
                onTap: () {},
              ),
            ),
            const SizedBox(height: 20),

            // Section header: Nearby shops & services.
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: kScreenPadding),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Nearby shops & services',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: AppTheme.mainText,
                        ),
                  ),
                  TextButton(
                    onPressed: () {},
                    child: const Text('View all', style: TextStyle(color: AppTheme.primary, fontWeight: FontWeight.w600)),
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
                      : RefreshIndicator(
                          onRefresh: () async {
                            ref.read(businessesProvider.notifier).search(query: '', lat: 20.46, lng: 85.88);
                          },
                          child: ListView.separated(
                            padding: const EdgeInsets.symmetric(horizontal: kScreenPadding),
                            itemCount: state.items.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 10),
                            itemBuilder: (_, i) {
                              final b = state.items[i];
                              return BusinessCard(
                                business: b,
                                onTap: () => Navigator.of(context).push(
                                  MaterialPageRoute(builder: (_) => BusinessDetailScreen(businessId: b.id)),
                                ),
                                isFavorited: false,
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
