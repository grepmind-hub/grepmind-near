import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:grepmind_mobile/core/screens/merchant_categories_screen.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:grepmind_mobile/core/models/business.dart';
import 'package:grepmind_mobile/core/providers/app_provider.dart';
import 'package:grepmind_mobile/core/network/api_client.dart';
import 'package:grepmind_mobile/core/theme/app_theme.dart';
import 'package:grepmind_mobile/core/widgets/premium_card.dart';
import 'package:grepmind_mobile/core/utils/category_sample_image.dart';

/// Screen 21: Merchant Catalog Management
/// Allows merchants and service professionals to manage their product inventory
/// and service offerings with stock status, pricing, search, and modals.
class MerchantCatalogScreen extends ConsumerStatefulWidget {
  const MerchantCatalogScreen({super.key});

  @override
  ConsumerState<MerchantCatalogScreen> createState() =>
      _MerchantCatalogScreenState();
}

class _MerchantCatalogScreenState extends ConsumerState<MerchantCatalogScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (mounted) setState(() {});
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(merchantCatalogProvider.notifier).loadCatalog();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final catalogState = ref.watch(merchantCatalogProvider);

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text(
          'Catalog Management',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
        backgroundColor: Colors.white,
        foregroundColor: AppTheme.mainText,
        elevation: 0,
        actions: [
          IconButton(
            tooltip: 'Manage categories',
            icon: const Icon(Icons.category_outlined),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const MerchantCategoriesScreen(),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh Catalog',
            onPressed: () =>
                ref.read(merchantCatalogProvider.notifier).loadCatalog(),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(108),
          child: Column(
            children: [
              // Search input
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 6,
                ),
                child: TextField(
                  key: const Key('search_catalog_input'),
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Search products or services...',
                    hintStyle: const TextStyle(
                      fontSize: 14,
                      color: AppTheme.hintText,
                    ),
                    prefixIcon: const Icon(
                      Icons.search,
                      size: 20,
                      color: AppTheme.secondaryText,
                    ),
                    suffixIcon: _searchController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 18),
                            onPressed: () {
                              _searchController.clear();
                              ref
                                  .read(merchantCatalogProvider.notifier)
                                  .setSearchQuery('');
                              setState(() {});
                            },
                          )
                        : null,
                    filled: true,
                    fillColor: const Color(0xFFF1F5F9),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  onChanged: (val) {
                    ref
                        .read(merchantCatalogProvider.notifier)
                        .setSearchQuery(val);
                    setState(() {});
                  },
                ),
              ),

              // Segmented TabBar
              TabBar(
                controller: _tabController,
                labelColor: AppTheme.primary,
                unselectedLabelColor: AppTheme.secondaryText,
                indicatorColor: AppTheme.primary,
                indicatorWeight: 3,
                labelStyle: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
                unselectedLabelStyle: const TextStyle(
                  fontWeight: FontWeight.w500,
                  fontSize: 14,
                ),
                tabs: [
                  Tab(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.inventory_2_outlined, size: 18),
                        const SizedBox(width: 8),
                        const Text('Products'),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: _tabController.index == 0
                                ? AppTheme.primary.withOpacity(0.12)
                                : Colors.grey.shade200,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            '${catalogState.products.length}',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: _tabController.index == 0
                                  ? AppTheme.primary
                                  : AppTheme.secondaryText,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Tab(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.home_repair_service_outlined,
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        const Text('Services'),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: _tabController.index == 1
                                ? AppTheme.primary.withOpacity(0.12)
                                : Colors.grey.shade200,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            '${catalogState.services.length}',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: _tabController.index == 1
                                  ? AppTheme.primary
                                  : AppTheme.secondaryText,
                            ),
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
      ),
      body: catalogState.isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _buildProductsTab(catalogState),
                _buildServicesTab(catalogState),
              ],
            ),
      floatingActionButton: FloatingActionButton.extended(
        key: Key(
          _tabController.index == 0 ? 'add_product_fab' : 'add_service_fab',
        ),
        backgroundColor: _tabController.index == 0
            ? AppTheme.primary
            : const Color(0xFF0F766E),
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add, size: 20),
        label: Text(
          _tabController.index == 0 ? 'Add Product' : 'Add Service',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        onPressed: () {
          if (_tabController.index == 0) {
            _showProductModal(context, null);
          } else {
            _showServiceModal(context, null);
          }
        },
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // PRODUCTS TAB
  // ---------------------------------------------------------------------------

  Widget _buildProductsTab(MerchantCatalogState state) {
    final prods = state.filteredProducts;

    return Column(
      children: [
        // Filter Chips row
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              _filterChip('All', 'all', state.selectedProductFilter, (v) {
                ref.read(merchantCatalogProvider.notifier).setProductFilter(v);
              }),
              const SizedBox(width: 8),
              _filterChip('In Stock', 'in_stock', state.selectedProductFilter, (
                v,
              ) {
                ref.read(merchantCatalogProvider.notifier).setProductFilter(v);
              }),
              const SizedBox(width: 8),
              _filterChip('Limited', 'limited', state.selectedProductFilter, (
                v,
              ) {
                ref.read(merchantCatalogProvider.notifier).setProductFilter(v);
              }),
              const SizedBox(width: 8),
              _filterChip(
                'Out of Stock',
                'out_of_stock',
                state.selectedProductFilter,
                (v) {
                  ref
                      .read(merchantCatalogProvider.notifier)
                      .setProductFilter(v);
                },
              ),
              const SizedBox(width: 8),
              _filterChip('Live', 'published', state.selectedProductFilter, (
                v,
              ) {
                ref.read(merchantCatalogProvider.notifier).setProductFilter(v);
              }),
              const SizedBox(width: 8),
              _filterChip('Draft', 'draft', state.selectedProductFilter, (v) {
                ref.read(merchantCatalogProvider.notifier).setProductFilter(v);
              }),
            ],
          ),
        ),

        // Product list
        Expanded(
          child: prods.isEmpty
              ? _buildEmptyState(
                  title: state.searchQuery.isNotEmpty
                      ? 'No products found'
                      : 'No Products in Catalog',
                  subtitle: state.searchQuery.isNotEmpty
                      ? 'Try adjusting your search query or filter chips.'
                      : 'Add retail items, prices, and stock counts to showcase on your storefront.',
                  buttonLabel: '+ Add First Product',
                  onAction: () => _showProductModal(context, null),
                )
              : RefreshIndicator(
                  onRefresh: () =>
                      ref.read(merchantCatalogProvider.notifier).loadCatalog(),
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 90),
                    itemCount: prods.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final p = prods[index];
                      return _buildProductCard(p);
                    },
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildProductCard(Product p) {
    return PremiumCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Product thumbnail / placeholder
              Container(
                width: 70,
                height: 70,
                decoration: BoxDecoration(
                  color: AppTheme.primary.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: p.imageUrl != null && p.imageUrl!.isNotEmpty
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.network(
                          p.imageUrl!,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => const Icon(
                            Icons.inventory_2_outlined,
                            color: AppTheme.primary,
                            size: 30,
                          ),
                        ),
                      )
                    : const Icon(
                        Icons.inventory_2_outlined,
                        color: AppTheme.primary,
                        size: 30,
                      ),
              ),
              const SizedBox(width: 14),

              // Title and details
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            p.name,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.mainText,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        _buildPublishedBadge(p.isPublished),
                      ],
                    ),
                    if (p.description != null && p.description!.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        p.description!,
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppTheme.secondaryText,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    const SizedBox(height: 8),

                    // Price & Stock
                    Row(
                      children: [
                        Text(
                          p.priceText,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: AppTheme.primary,
                          ),
                        ),
                        const Spacer(),
                        _buildStockStatusBadge(p.stockStatus),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(height: 1, color: Color(0xFFE2E8F0)),
          const SizedBox(height: 8),

          // Actions row
          Row(
            children: [
              // Quick stock status picker
              PopupMenuButton<String>(
                tooltip: 'Change Stock Status',
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.swap_vert,
                        size: 16,
                        color: AppTheme.secondaryText,
                      ),
                      SizedBox(width: 4),
                      Text(
                        'Stock Status',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.mainText,
                        ),
                      ),
                    ],
                  ),
                ),
                onSelected: (val) {
                  ref.read(merchantCatalogProvider.notifier).updateProduct(
                    p.id,
                    {'stock_status': val},
                  );
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'in_stock', child: Text('In Stock')),
                  PopupMenuItem(value: 'limited', child: Text('Limited / Low')),
                  PopupMenuItem(
                    value: 'out_of_stock',
                    child: Text('Out of Stock'),
                  ),
                ],
              ),
              const SizedBox(width: 8),

              // Publish / Unpublish quick toggle
              IconButton(
                key: Key('toggle_published_${p.id}'),
                icon: Icon(
                  p.isPublished
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                  size: 20,
                  color: p.isPublished
                      ? AppTheme.primary
                      : AppTheme.secondaryText,
                ),
                tooltip: p.isPublished
                    ? 'Unpublish (make draft)'
                    : 'Publish live',
                onPressed: () {
                  ref.read(merchantCatalogProvider.notifier).updateProduct(
                    p.id,
                    {'is_published': !p.isPublished},
                  );
                },
              ),
              const Spacer(),

              // Edit button
              TextButton.icon(
                key: Key('edit_product_btn_${p.id}'),
                style: TextButton.styleFrom(
                  foregroundColor: AppTheme.primary,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
                onPressed: () => _showProductModal(context, p),
                icon: const Icon(Icons.edit_outlined, size: 16),
                label: const Text(
                  'Edit',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
              ),

              // Delete button
              IconButton(
                key: Key('delete_product_btn_${p.id}'),
                icon: const Icon(
                  Icons.delete_outline,
                  size: 18,
                  color: AppTheme.error,
                ),
                tooltip: 'Delete Product',
                onPressed: () => _confirmDeleteProduct(context, p),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // SERVICES TAB
  // ---------------------------------------------------------------------------

  Widget _buildServicesTab(MerchantCatalogState state) {
    final srvs = state.filteredServices;

    return Column(
      children: [
        // Filter Chips row
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              _filterChip('All', 'all', state.selectedServiceFilter, (v) {
                ref.read(merchantCatalogProvider.notifier).setServiceFilter(v);
              }),
              const SizedBox(width: 8),
              _filterChip('Active', 'active', state.selectedServiceFilter, (v) {
                ref.read(merchantCatalogProvider.notifier).setServiceFilter(v);
              }),
              const SizedBox(width: 8),
              _filterChip('Inactive', 'inactive', state.selectedServiceFilter, (
                v,
              ) {
                ref.read(merchantCatalogProvider.notifier).setServiceFilter(v);
              }),
            ],
          ),
        ),

        // Services list
        Expanded(
          child: srvs.isEmpty
              ? _buildEmptyState(
                  title: state.searchQuery.isNotEmpty
                      ? 'No services found'
                      : 'No Services Added',
                  subtitle: state.searchQuery.isNotEmpty
                      ? 'Try adjusting your search query.'
                      : 'Offer on-site services, consultations, or trade appointments with transparent pricing.',
                  buttonLabel: '+ Add First Service',
                  onAction: () => _showServiceModal(context, null),
                )
              : RefreshIndicator(
                  onRefresh: () =>
                      ref.read(merchantCatalogProvider.notifier).loadCatalog(),
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 90),
                    itemCount: srvs.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final s = srvs[index];
                      return _buildServiceCard(s);
                    },
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildServiceCard(Service s) {
    String priceDisplay = 'Rate on inspection';
    if (s.indicativePriceMin != null && s.indicativePriceMax != null) {
      priceDisplay =
          '₹${s.indicativePriceMin!.toInt()} - ₹${s.indicativePriceMax!.toInt()}';
    } else if (s.indicativePriceMin != null) {
      priceDisplay = 'From ₹${s.indicativePriceMin!.toInt()}';
    }

    return PremiumCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: const Color(0xFF0F766E).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.handyman_outlined,
                  color: Color(0xFF0F766E),
                  size: 26,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            s.name,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.mainText,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: s.isActive
                                ? const Color(0xFFD1FAE5)
                                : const Color(0xFFF1F5F9),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            s.isActive ? 'Active' : 'Inactive',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: s.isActive
                                  ? const Color(0xFF065F46)
                                  : AppTheme.secondaryText,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (s.description != null && s.description!.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        s.description!,
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppTheme.secondaryText,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    const SizedBox(height: 8),
                    Text(
                      priceDisplay,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF0F766E),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(height: 1, color: Color(0xFFE2E8F0)),
          const SizedBox(height: 8),

          Row(
            children: [
              // Switch status directly
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Switch.adaptive(
                    key: Key('toggle_service_active_${s.id}'),
                    value: s.isActive,
                    activeColor: const Color(0xFF0F766E),
                    onChanged: (val) {
                      ref.read(merchantCatalogProvider.notifier).updateService(
                        s.id,
                        {'is_active': val},
                      );
                    },
                  ),
                  Text(
                    s.isActive ? 'Available' : 'Paused',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppTheme.secondaryText,
                    ),
                  ),
                ],
              ),
              const Spacer(),

              // Edit button
              TextButton.icon(
                key: Key('edit_service_btn_${s.id}'),
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFF0F766E),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
                onPressed: () => _showServiceModal(context, s),
                icon: const Icon(Icons.edit_outlined, size: 16),
                label: const Text(
                  'Edit',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
              ),

              // Delete button
              IconButton(
                key: Key('delete_service_btn_${s.id}'),
                icon: const Icon(
                  Icons.delete_outline,
                  size: 18,
                  color: AppTheme.error,
                ),
                tooltip: 'Delete Service',
                onPressed: () => _confirmDeleteService(context, s),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // HELPERS & MODALS
  // ---------------------------------------------------------------------------

  Widget _filterChip(
    String label,
    String value,
    String currentSelected,
    Function(String) onSelect,
  ) {
    final isSelected = currentSelected == value;
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: () => onSelect(value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.primary : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? AppTheme.primary : const Color(0xFFCBD5E1),
            width: 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
            color: isSelected ? Colors.white : AppTheme.mainText,
          ),
        ),
      ),
    );
  }

  Widget _buildStockStatusBadge(String stock) {
    Color bg;
    Color fg;
    String label;
    IconData icon;

    switch (stock) {
      case 'in_stock':
        bg = const Color(0xFFD1FAE5);
        fg = const Color(0xFF065F46);
        label = 'In Stock';
        icon = Icons.check_circle_outline;
        break;
      case 'limited':
        bg = const Color(0xFFFEF3C7);
        fg = const Color(0xFF92400E);
        label = 'Limited';
        icon = Icons.timelapse;
        break;
      case 'out_of_stock':
        bg = const Color(0xFFFEE2E2);
        fg = const Color(0xFF991B1B);
        label = 'Out of Stock';
        icon = Icons.cancel_outlined;
        break;
      default:
        bg = const Color(0xFFF1F5F9);
        fg = AppTheme.secondaryText;
        label = 'Unknown';
        icon = Icons.help_outline;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: fg),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: fg,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPublishedBadge(bool isPublished) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: isPublished ? const Color(0xFFEFF6FF) : const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        isPublished ? 'Live' : 'Draft',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: isPublished ? AppTheme.primary : AppTheme.secondaryText,
        ),
      ),
    );
  }

  Widget _buildEmptyState({
    required String title,
    required String subtitle,
    required String buttonLabel,
    required VoidCallback onAction,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: AppTheme.primary.withOpacity(0.08),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.inventory_2_outlined,
                size: 40,
                color: AppTheme.primary,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              title,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppTheme.mainText,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              style: const TextStyle(
                fontSize: 14,
                color: AppTheme.secondaryText,
                height: 1.4,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: onAction,
              child: Text(
                buttonLabel,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // ADD / EDIT PRODUCT MODAL
  // ---------------------------------------------------------------------------

  void _showProductModal(BuildContext context, Product? product) {
    final isEditing = product != null;
    final nameCtrl = TextEditingController(text: product?.name ?? '');
    final descCtrl = TextEditingController(text: product?.description ?? '');
    final priceCtrl = TextEditingController(
      text: product?.price != null ? product!.price!.toStringAsFixed(0) : '',
    );
    final imageCtrl = TextEditingController(text: product?.imageUrl ?? '');
    String stockStatus = product?.stockStatus ?? 'in_stock';
    bool isPublished = product?.isPublished ?? true;
    bool isUploadingImage = false;
    Uint8List? selectedSampleBytes;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (modalCtx, setModalState) {
          return Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(modalCtx).viewInsets.bottom,
              left: 20,
              right: 20,
              top: 20,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        isEditing ? 'Edit Product' : 'Add New Product',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.mainText,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(modalCtx),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Name
                  const Text(
                    'Product Title *',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    key: const Key('modal_product_name'),
                    controller: nameCtrl,
                    decoration: InputDecoration(
                      hintText: 'e.g. Copper Water Bottle 1L',
                      filled: true,
                      fillColor: const Color(0xFFF8FAFC),
                      isDense: true,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Price
                  const Text(
                    'Price (₹ INR) *',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    key: const Key('modal_product_price'),
                    controller: priceCtrl,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      prefixText: '₹ ',
                      hintText: '299',
                      filled: true,
                      fillColor: const Color(0xFFF8FAFC),
                      isDense: true,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Stock Status Picker
                  const Text(
                    'Stock Status',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 6),
                  DropdownButtonFormField<String>(
                    value: stockStatus,
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: const Color(0xFFF8FAFC),
                      isDense: true,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'in_stock',
                        child: Text('In Stock'),
                      ),
                      DropdownMenuItem(
                        value: 'limited',
                        child: Text('Limited / Low Stock'),
                      ),
                      DropdownMenuItem(
                        value: 'out_of_stock',
                        child: Text('Out of Stock'),
                      ),
                    ],
                    onChanged: (val) {
                      if (val != null) setModalState(() => stockStatus = val);
                    },
                  ),
                  const SizedBox(height: 14),

                  // Description
                  const Text(
                    'Description',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    key: const Key('modal_product_desc'),
                    controller: descCtrl,
                    maxLines: 2,
                    decoration: InputDecoration(
                      hintText:
                          'Add details, material, dimensions or warranty...',
                      filled: true,
                      fillColor: const Color(0xFFF8FAFC),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Product photography
                  const Text(
                    'Product photo (optional)',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 6),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: OutlinedButton.icon(
                      onPressed: isUploadingImage
                          ? null
                          : () async {
                              final sampleIndex = await showModalBottomSheet<int>(
                                context: modalCtx,
                                isScrollControlled: true,
                                showDragHandle: true,
                                builder: (sheetContext) => SafeArea(
                                  child: SizedBox(
                                    height:
                                        MediaQuery.sizeOf(sheetContext).height *
                                        .72,
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Padding(
                                          padding: const EdgeInsets.fromLTRB(
                                            20,
                                            4,
                                            20,
                                            12,
                                          ),
                                          child: Text(
                                            'Choose a category photo',
                                            style: Theme.of(sheetContext)
                                                .textTheme
                                                .titleLarge
                                                ?.copyWith(
                                                  fontWeight: FontWeight.w800,
                                                ),
                                          ),
                                        ),
                                        const Padding(
                                          padding: EdgeInsets.fromLTRB(
                                            20,
                                            0,
                                            20,
                                            12,
                                          ),
                                          child: Text(
                                            'Illustrative samples are a starting point. Replace them with your own photo when available.',
                                          ),
                                        ),
                                        Expanded(
                                          child: GridView.builder(
                                            key: const ValueKey(
                                              'category_sample_grid',
                                            ),
                                            padding: const EdgeInsets.fromLTRB(
                                              16,
                                              0,
                                              16,
                                              20,
                                            ),
                                            gridDelegate:
                                                const SliverGridDelegateWithFixedCrossAxisCount(
                                                  crossAxisCount: 2,
                                                  crossAxisSpacing: 12,
                                                  mainAxisSpacing: 12,
                                                  childAspectRatio: 1.16,
                                                ),
                                            itemCount:
                                                categorySampleLabels.length,
                                            itemBuilder: (context, index) => Material(
                                              color: Colors.white,
                                              borderRadius:
                                                  BorderRadius.circular(15),
                                              clipBehavior: Clip.antiAlias,
                                              child: InkWell(
                                                key: ValueKey(
                                                  'category_sample_$index',
                                                ),
                                                onTap: () => Navigator.pop(
                                                  sheetContext,
                                                  index,
                                                ),
                                                child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    Expanded(
                                                      child: SizedBox(
                                                        width: double.infinity,
                                                        child:
                                                            CategorySampleImage(
                                                              index: index,
                                                            ),
                                                      ),
                                                    ),
                                                    Padding(
                                                      padding:
                                                          const EdgeInsets.symmetric(
                                                            horizontal: 10,
                                                            vertical: 9,
                                                          ),
                                                      child: Text(
                                                        categorySampleLabels[index],
                                                        maxLines: 1,
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                        style: const TextStyle(
                                                          fontWeight:
                                                              FontWeight.w700,
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                              if (sampleIndex == null || !modalCtx.mounted) {
                                return;
                              }
                              setModalState(() => isUploadingImage = true);
                              try {
                                selectedSampleBytes = await cropCategorySample(
                                  sampleIndex,
                                );
                                setModalState(() => isUploadingImage = false);
                              } catch (_) {
                                setModalState(() => isUploadingImage = false);
                                if (modalCtx.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        'Photo upload failed. Check your connection and try again.',
                                      ),
                                    ),
                                  );
                                }
                              }
                            },
                      icon: isUploadingImage
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.photo_library_outlined),
                      label: Text(
                        isUploadingImage
                            ? 'Uploading photo…'
                            : 'Choose a sample photo',
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    key: const Key('modal_product_image_url'),
                    controller: imageCtrl,
                    onChanged: (_) => setModalState(() {}),
                    decoration: InputDecoration(
                      hintText: 'Or paste an image URL',
                      filled: true,
                      fillColor: const Color(0xFFF8FAFC),
                      isDense: true,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                  if (selectedSampleBytes != null ||
                      imageCtrl.text.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: SizedBox(
                        width: double.infinity,
                        height: 112,
                        child: selectedSampleBytes != null
                            ? Image.memory(
                                selectedSampleBytes!,
                                fit: BoxFit.cover,
                              )
                            : Image.network(
                                imageCtrl.text,
                                fit: BoxFit.cover,
                                errorBuilder: (_, _, _) => const ColoredBox(
                                  color: Color(0xFFEAF0F8),
                                  child: Center(
                                    child: Text('Image preview unavailable'),
                                  ),
                                ),
                              ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 14),

                  // Published switch
                  Row(
                    children: [
                      Switch.adaptive(
                        value: isPublished,
                        activeColor: AppTheme.primary,
                        onChanged: (val) =>
                            setModalState(() => isPublished = val),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        isPublished
                            ? 'Published on Storefront'
                            : 'Saved as Draft (Hidden)',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // Submit button
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton(
                      key: const Key('save_product_btn'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primary,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: () async {
                        final name = nameCtrl.text.trim();
                        if (name.isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Product title is required.'),
                            ),
                          );
                          return;
                        }
                        final priceText = priceCtrl.text.trim();
                        final price = double.tryParse(priceText);
                        if (priceText.isNotEmpty &&
                            (price == null || price < 0)) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Enter a valid price of zero or more.',
                              ),
                            ),
                          );
                          return;
                        }
                        var imageUrl = imageCtrl.text.trim();
                        if (selectedSampleBytes != null) {
                          setModalState(() => isUploadingImage = true);
                          try {
                            final upload = await apiClient.uploadMedia(
                              bytes: selectedSampleBytes!,
                              filename: 'category-sample.png',
                              purpose: 'product',
                            );
                            final imagePath = upload['url'] as String? ?? '';
                            if (imagePath.isEmpty) {
                              throw StateError(
                                'Storage did not return an image URL.',
                              );
                            }
                            imageUrl = apiClient.resolveMediaUrl(imagePath);
                          } catch (_) {
                            setModalState(() => isUploadingImage = false);
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Photo upload failed. Check your connection and try again.',
                                  ),
                                ),
                              );
                            }
                            return;
                          }
                          setModalState(() => isUploadingImage = false);
                        }
                        final saved = isEditing
                            ? await ref
                                  .read(merchantCatalogProvider.notifier)
                                  .updateProduct(product.id, {
                                    'name': name,
                                    'description': descCtrl.text.trim(),
                                    'price': price,
                                    'stock_status': stockStatus,
                                    'is_published': isPublished,
                                    'image_url': imageUrl,
                                  })
                            : await ref
                                  .read(merchantCatalogProvider.notifier)
                                  .createProduct(
                                    name: name,
                                    description: descCtrl.text.trim(),
                                    price: price,
                                    stockStatus: stockStatus,
                                    isPublished: isPublished,
                                    imageUrl: imageUrl,
                                  );

                        if (!context.mounted) return;
                        if (!saved) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Could not save product. Check your connection and try again.',
                              ),
                            ),
                          );
                          return;
                        }
                        Navigator.pop(modalCtx);
                      },
                      child: Text(
                        isEditing ? 'Save Changes' : 'Create Product',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // ADD / EDIT SERVICE MODAL
  // ---------------------------------------------------------------------------

  void _showServiceModal(BuildContext context, Service? service) {
    final isEditing = service != null;
    final nameCtrl = TextEditingController(text: service?.name ?? '');
    final descCtrl = TextEditingController(text: service?.description ?? '');
    final minPriceCtrl = TextEditingController(
      text: service?.indicativePriceMin != null
          ? service!.indicativePriceMin!.toStringAsFixed(0)
          : '',
    );
    final maxPriceCtrl = TextEditingController(
      text: service?.indicativePriceMax != null
          ? service!.indicativePriceMax!.toStringAsFixed(0)
          : '',
    );
    bool isActive = service?.isActive ?? true;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (modalCtx, setModalState) {
          return Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(modalCtx).viewInsets.bottom,
              left: 20,
              right: 20,
              top: 20,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        isEditing ? 'Edit Service' : 'Add New Service',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.mainText,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(modalCtx),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Name
                  const Text(
                    'Service Name *',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    key: const Key('modal_service_name'),
                    controller: nameCtrl,
                    decoration: InputDecoration(
                      hintText: 'e.g. Fan Installation & Repair',
                      filled: true,
                      fillColor: const Color(0xFFF8FAFC),
                      isDense: true,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Price Range
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Min Rate (₹)',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 6),
                            TextField(
                              key: const Key('modal_service_min_price'),
                              controller: minPriceCtrl,
                              keyboardType: TextInputType.number,
                              decoration: InputDecoration(
                                prefixText: '₹ ',
                                hintText: '199',
                                filled: true,
                                fillColor: const Color(0xFFF8FAFC),
                                isDense: true,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Max Rate (₹)',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 6),
                            TextField(
                              key: const Key('modal_service_max_price'),
                              controller: maxPriceCtrl,
                              keyboardType: TextInputType.number,
                              decoration: InputDecoration(
                                prefixText: '₹ ',
                                hintText: '499',
                                filled: true,
                                fillColor: const Color(0xFFF8FAFC),
                                isDense: true,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),

                  // Description
                  const Text(
                    'Service Scope / Terms',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    key: const Key('modal_service_desc'),
                    controller: descCtrl,
                    maxLines: 2,
                    decoration: InputDecoration(
                      hintText: 'Includes diagnostic inspection, wiring check, and safety testing...',
                      filled: true,
                      fillColor: const Color(0xFFF8FAFC),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Active switch
                  Row(
                    children: [
                      Switch.adaptive(
                        value: isActive,
                        activeColor: const Color(0xFF0F766E),
                        onChanged: (val) => setModalState(() => isActive = val),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        isActive
                            ? 'Active (Open for customer bookings)'
                            : 'Paused (Hidden)',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // Submit button
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton(
                      key: const Key('save_service_btn'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0F766E),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: () async {
                        final name = nameCtrl.text.trim();
                        if (name.isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Service title is required.'),
                            ),
                          );
                          return;
                        }
                        final pMin = double.tryParse(minPriceCtrl.text.trim());
                        final pMax = double.tryParse(maxPriceCtrl.text.trim());

                        if (isEditing) {
                          await ref
                              .read(merchantCatalogProvider.notifier)
                              .updateService(service.id, {
                                'name': name,
                                'description': descCtrl.text.trim(),
                                'indicative_price_min': pMin,
                                'indicative_price_max': pMax,
                                'is_active': isActive,
                              });
                        } else {
                          await ref
                              .read(merchantCatalogProvider.notifier)
                              .createService(
                                name: name,
                                description: descCtrl.text.trim(),
                                priceMin: pMin,
                                priceMax: pMax,
                                isActive: isActive,
                              );
                        }
                        if (context.mounted) Navigator.pop(modalCtx);
                      },
                      child: Text(
                        isEditing ? 'Save Changes' : 'Create Service',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // CONFIRM DELETIONS
  // ---------------------------------------------------------------------------

  void _confirmDeleteProduct(BuildContext context, Product p) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Product?'),
        content: Text(
          'Are you sure you want to remove "${p.name}" from your catalog?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.error,
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              Navigator.pop(ctx);
              await ref
                  .read(merchantCatalogProvider.notifier)
                  .deleteProduct(p.id);
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _confirmDeleteService(BuildContext context, Service s) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Service?'),
        content: Text(
          'Are you sure you want to remove "${s.name}" from your service offerings?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.error,
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              Navigator.pop(ctx);
              await ref
                  .read(merchantCatalogProvider.notifier)
                  .deleteService(s.id);
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}
