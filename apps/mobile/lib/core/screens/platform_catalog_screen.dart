import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:grepmind_mobile/core/models/platform_catalog.dart';
import 'package:grepmind_mobile/core/network/api_client.dart';
import 'package:grepmind_mobile/core/providers/platform_catalog_provider.dart';
import 'package:grepmind_mobile/core/providers/platform_cart_provider.dart';
import 'package:grepmind_mobile/core/providers/app_provider.dart';
import 'package:grepmind_mobile/core/screens/platform_cart_screen.dart';
import 'package:grepmind_mobile/core/screens/platform_product_detail_screen.dart';
import 'package:grepmind_mobile/core/theme/app_theme.dart';
import 'package:grepmind_mobile/core/widgets/sticky_cart_summary_bar.dart';

class PlatformCatalogScreen extends ConsumerStatefulWidget {
  final String vertical;
  final String city;
  final String locality;
  final String localityId;
  final bool startInSearch;

  const PlatformCatalogScreen({
    super.key,
    required this.vertical,
    required this.city,
    this.locality = '',
    this.localityId = '',
    this.startInSearch = false,
  });

  @override
  ConsumerState<PlatformCatalogScreen> createState() =>
      _PlatformCatalogScreenState();
}

class _PlatformCatalogScreenState extends ConsumerState<PlatformCatalogScreen> {
  late final TextEditingController _search;
  Timer? _debounce;
  String? _categoryId;
  late String _city;
  late String _locality;
  late String _localityId;
  String _searchValue = '';
  List<PlatformCatalogProduct> _extraProducts = const [];
  int _nextOffset = 20;
  bool _loadingMore = false;
  String? _loadMoreError;
  bool? _moreAvailable;
  final FocusNode _searchFocus = FocusNode();

  String get _vertical => widget.vertical;
  PlatformCatalogQuery get _baseQuery => PlatformCatalogQuery(
    vertical: _vertical,
    city: _city,
    locality: _locality,
    localityId: _localityId,
  );
  PlatformCatalogQuery get _query => PlatformCatalogQuery(
    vertical: _vertical,
    city: _city,
    locality: _locality,
    localityId: _localityId,
    search: _searchValue,
    categoryId: _categoryId,
  );

  @override
  void initState() {
    super.initState();
    _city = widget.city;
    _locality = widget.locality;
    _localityId = widget.localityId;
    _searchValue = '';
    _search = TextEditingController();
    if (widget.startInSearch) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _searchFocus.requestFocus();
      });
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final title = _vertical == 'food' ? 'Food & Meals' : 'Groceries';
    final userId = ref.watch(currentUserProvider)?.id ?? '';
    final cartScope = PlatformCartScope(
      userId: userId,
      vertical: _vertical,
      localityId: _localityId,
      locality: _locality,
      district: _city,
    );
    final cart = ref.watch(platformCartProvider(cartScope));
    final categories = _city.isEmpty
        ? const AsyncValue<List<PlatformCatalogCategory>>.data([])
        : ref.watch(platformCatalogCategoriesProvider(_baseQuery));
    final page = _city.isEmpty
        ? const AsyncValue<PlatformCatalogPage>.data(
            PlatformCatalogPage(products: [], hasMore: false, count: 0),
          )
        : ref.watch(platformCatalogProductsProvider(_query));
    return Scaffold(
      backgroundColor: context.abashyaka.canvas,
      bottomNavigationBar: StickyCartSummaryBar(scope: cartScope),
      appBar: AppBar(
        title: Text(title),
        actions: [
          IconButton(
            tooltip: 'Open ${_vertical == 'food' ? 'Food' : 'Grocery'} cart',
            onPressed: _localityId.isEmpty || userId.isEmpty
                ? null
                : () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => PlatformCartScreen(scope: cartScope),
                    ),
                  ),
            icon: Badge(
              isLabelVisible: cart.itemCount > 0,
              label: Text('${cart.itemCount}'),
              child: const Icon(Icons.shopping_cart_outlined),
            ),
          ),
          IconButton(
            tooltip: 'Refresh catalog',
            onPressed: _city.isEmpty
                ? null
                : () {
                    ref.invalidate(platformCatalogProductsProvider(_query));
                    ref.invalidate(
                      platformCatalogCategoriesProvider(_baseQuery),
                    );
                  },
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _city.isEmpty
          ? _CatalogMessage(
              icon: Icons.location_off_outlined,
              title: 'Choose a delivery location',
              detail:
                  'Select Cuttack or Jajpur to browse catalog availability.',
              action: TextButton.icon(
                onPressed: _chooseLocation,
                icon: const Icon(Icons.location_on_outlined),
                label: const Text('Choose location'),
              ),
            )
          : CustomScrollView(
              key: const ValueKey('platform_catalog_scroll'),
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
                  sliver: SliverList.list(
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.location_on_outlined,
                            size: 18,
                            color: AppTheme.emerald,
                          ),
                          const SizedBox(width: 5),
                          Expanded(
                            child: Text(
                              _locality.isEmpty ? _city : '$_locality, $_city',
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(fontWeight: FontWeight.w600),
                            ),
                          ),
                          TextButton.icon(
                            key: const ValueKey('catalog_change_location'),
                            onPressed: _chooseLocation,
                            icon: const Icon(
                              Icons.edit_location_alt_outlined,
                              size: 18,
                            ),
                            label: const Text('Change'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      // Keep catalog context authoritative; partner identity,
                      // ratings, distance and ETA are not available in this API response.
                      Container(
                        margin: const EdgeInsets.only(top: 4, bottom: 10),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: AppTheme.emeraldDark,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                color: AppTheme.emerald,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Icon(
                                Icons.storefront_rounded,
                                color: Colors.white,
                                size: 18,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Text(
                                        _vertical == 'food'
                                            ? 'Food catalog'
                                            : 'Grocery catalog',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 12,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Published items available for ${_locality.isEmpty ? _city : _locality}',
                                    style: const TextStyle(
                                      fontSize: 10,
                                      color: Color(0xFFD0E8E3),
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 7,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFF8A00),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Text(
                                'Live',
                                style: TextStyle(
                                  color: AppTheme.forestDark,
                                  fontSize: 9,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      TextField(
                        controller: _search,
                        focusNode: _searchFocus,
                        key: const ValueKey('platform_catalog_search'),
                        textInputAction: TextInputAction.search,
                        onChanged: (value) {
                          _debounce?.cancel();
                          _debounce = Timer(
                            const Duration(milliseconds: 350),
                            () {
                              if (mounted) {
                                setState(() {
                                  _searchValue = value.trim();
                                  _resetExtraProducts();
                                });
                              }
                            },
                          );
                        },
                        decoration: InputDecoration(
                          hintText: 'Search $title',
                          prefixIcon: const Icon(Icons.search_rounded),
                          suffixIcon: _search.text.isEmpty
                              ? null
                              : IconButton(
                                  tooltip: 'Clear search',
                                  onPressed: () {
                                    _debounce?.cancel();
                                    _search.clear();
                                    setState(() {
                                      _searchValue = '';
                                      _resetExtraProducts();
                                    });
                                  },
                                  icon: const Icon(Icons.close_rounded),
                                ),
                          filled: true,
                          fillColor: AppTheme.surface,
                        ),
                      ),
                      const SizedBox(height: 15),
                      categories.when(
                        loading: () => const SizedBox(
                          height: 42,
                          child: Center(child: LinearProgressIndicator()),
                        ),
                        error: (error, _) => Row(
                          children: [
                            const Expanded(
                              child: Text('Categories unavailable.'),
                            ),
                            TextButton(
                              onPressed: () => ref.invalidate(
                                platformCatalogCategoriesProvider(_baseQuery),
                              ),
                              child: const Text('Retry'),
                            ),
                          ],
                        ),
                        data: (items) => SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                              _CategoryChip(
                                label: 'All',
                                selected: _categoryId == null,
                                onTap: () => setState(() {
                                  _categoryId = null;
                                  _resetExtraProducts();
                                }),
                              ),
                              for (final category in items)
                                Padding(
                                  padding: const EdgeInsets.only(left: 8),
                                  child: _CategoryChip(
                                    label: category.name,
                                    selected: _categoryId == category.id,
                                    onTap: () => setState(() {
                                      _categoryId = category.id;
                                      _resetExtraProducts();
                                    }),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                page.when(
                  loading: () => const SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(child: CircularProgressIndicator()),
                  ),
                  error: (error, _) => SliverFillRemaining(
                    hasScrollBody: false,
                    child: _CatalogMessage(
                      icon: Icons.wifi_off_rounded,
                      title: 'Catalog unavailable',
                      detail: platformCatalogErrorMessage(error),
                      action: TextButton.icon(
                        onPressed: () => ref.invalidate(
                          platformCatalogProductsProvider(_query),
                        ),
                        icon: const Icon(Icons.refresh_rounded),
                        label: const Text('Retry'),
                      ),
                    ),
                  ),
                  data: (result) {
                    final products = [...result.products, ..._extraProducts];
                    return products.isEmpty
                        ? SliverFillRemaining(
                            hasScrollBody: false,
                            child: _CatalogMessage(
                              icon: result.deliveryAvailable
                                  ? Icons.inventory_2_outlined
                                  : Icons.location_off_outlined,
                              title: result.deliveryAvailable
                                  ? 'No products available here yet'
                                  : 'Delivery not enabled here yet',
                              detail: result.deliveryAvailable
                                  ? 'Published catalog items for this location will appear here.'
                                  : 'This locality is planned for a future rollout. You can browse when delivery is enabled.',
                            ),
                          )
                        : SliverMainAxisGroup(
                            slivers: [
                              SliverPadding(
                                padding: const EdgeInsets.fromLTRB(
                                  16,
                                  0,
                                  16,
                                  10,
                                ),
                                sliver: SliverGrid.builder(
                                  key: const ValueKey('platform_products_grid'),
                                  itemCount: products.length,
                                  gridDelegate:
                                      const SliverGridDelegateWithFixedCrossAxisCount(
                                        crossAxisCount: 2,
                                        crossAxisSpacing: 12,
                                        mainAxisSpacing: 12,
                                        childAspectRatio: .69,
                                      ),
                                  itemBuilder: (context, index) => _ProductCard(
                                    product: products[index],
                                    onTap: () => Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) =>
                                            PlatformProductDetailScreen(
                                              id: products[index].id,
                                              vertical: _vertical,
                                              city: _city,
                                              locality: _locality,
                                              localityId: _localityId,
                                            ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              if ((result.hasMore &&
                                      (_moreAvailable ?? true)) ||
                                  _loadingMore)
                                SliverToBoxAdapter(
                                  child: Padding(
                                    padding: const EdgeInsets.fromLTRB(
                                      16,
                                      0,
                                      16,
                                      24,
                                    ),
                                    child: Column(
                                      children: [
                                        if (_loadMoreError != null)
                                          Text(
                                            _loadMoreError!,
                                            textAlign: TextAlign.center,
                                            style: const TextStyle(
                                              color: AppTheme.error,
                                            ),
                                          ),
                                        OutlinedButton.icon(
                                          key: const ValueKey(
                                            'catalog_load_more',
                                          ),
                                          onPressed: _loadingMore
                                              ? null
                                              : () => _loadMore(
                                                  result.hasMore &&
                                                      (_moreAvailable ?? true),
                                                ),
                                          icon: _loadingMore
                                              ? const SizedBox(
                                                  width: 16,
                                                  height: 16,
                                                  child:
                                                      CircularProgressIndicator(
                                                        strokeWidth: 2,
                                                      ),
                                                )
                                              : const Icon(
                                                  Icons.expand_more_rounded,
                                                ),
                                          label: Text(
                                            _loadingMore
                                                ? 'Loading…'
                                                : 'Load more',
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                            ],
                          );
                  },
                ),
              ],
            ),
    );
  }

  Future<void> _chooseLocation() async {
    try {
      final response = await apiClient.get('/catalog/locations');
      final rows =
          (response.data as Map<String, dynamic>)['data'] as List? ?? [];
      final options = rows
          .whereType<Map<String, dynamic>>()
          .map(DeliveryDistrict.fromJson)
          .toList();
      if (!mounted) return;
      await showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        builder: (context) => SafeArea(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                'Delivery location',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              for (final district in options)
                ExpansionTile(
                  title: Text(district.name),
                  leading: const Icon(Icons.location_city_outlined),
                  children: [
                    for (final locality in district.localities)
                      ListTile(
                        title: Text(locality.name),
                        subtitle: Text(
                          locality.deliveryEnabled
                              ? 'Delivery enabled'
                              : 'Planned · delivery not enabled',
                        ),
                        onTap: () async {
                          setState(() {
                            _city = district.name;
                            _locality = locality.name;
                            _localityId = locality.id;
                            _categoryId = null;
                            _resetExtraProducts();
                          });
                          await DeliveryLocationStorage().write(
                            DeliveryLocationSelection(
                              district: district.name,
                              localityId: locality.id,
                              locality: locality.name,
                            ),
                          );
                          if (context.mounted) Navigator.pop(context);
                        },
                      ),
                  ],
                ),
            ],
          ),
        ),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Locations are unavailable. Please retry.'),
          ),
        );
      }
    }
  }

  void _resetExtraProducts() {
    _extraProducts = const [];
    _nextOffset = 20;
    _loadMoreError = null;
    _moreAvailable = null;
  }

  Future<void> _loadMore(bool hasMore) async {
    if (_loadingMore || !hasMore) return;
    final requestedQuery = _query;
    setState(() {
      _loadingMore = true;
      _loadMoreError = null;
    });
    try {
      final page = await ref
          .read(platformCatalogRepositoryProvider)
          .products(requestedQuery, offset: _nextOffset);
      if (!mounted) return;
      setState(() {
        if (requestedQuery == _query) {
          _extraProducts = [..._extraProducts, ...page.products];
          _nextOffset += page.products.length;
          _moreAvailable = page.hasMore && page.products.isNotEmpty;
        }
        _loadingMore = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadingMore = false;
        if (requestedQuery == _query) {
          _loadMoreError = platformCatalogErrorMessage(error);
        }
      });
    }
  }
}

class _ProductCard extends StatelessWidget {
  final PlatformCatalogProduct product;
  final VoidCallback onTap;

  const _ProductCard({required this.product, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final palette = context.abashyaka;
    final image = product.imageUrls.isEmpty ? null : product.imageUrls.first;
    final amount = product.lowestPriceMinor;
    final unitBadge = product.variants.isNotEmpty
        ? product.variants.first.unitLabel
        : '';
    return Material(
      color: palette.card,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: palette.border),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (image != null)
                      CachedNetworkImage(
                        imageUrl: apiClient.resolveMediaUrl(image),
                        fit: BoxFit.cover,
                        placeholder: (_, _) => const _ProductImagePlaceholder(),
                        errorWidget: (_, _, _) =>
                            const _ProductImagePlaceholder(),
                      )
                    else
                      const _ProductImagePlaceholder(),
                    if (unitBadge.isNotEmpty)
                      Positioned(
                        left: 9,
                        top: 9,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xBF0B1320),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            unitBadge,
                            style: AbashyakaTypography.categoryLabel(
                              color: AbashyakaColors.pureWhite,
                              fontSize: 10,
                            ),
                          ),
                        ),
                      ),
                    Positioned(
                      right: 9,
                      top: 9,
                      child: Container(
                        padding: const EdgeInsets.all(7),
                        decoration: BoxDecoration(
                          color: palette.card.withValues(alpha: 0.94),
                          shape: BoxShape.circle,
                          border: Border.all(color: palette.border),
                        ),
                        child: Icon(
                          Icons.arrow_outward_rounded,
                          color: palette.accent,
                          size: 16,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 11, 12, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      product.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AbashyakaTypography.cardTitle(
                        color: palette.textPrimary,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      product.categoryName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AbashyakaTypography.supportingText(
                        color: palette.textMuted,
                        fontSize: 11.5,
                      ),
                    ),
                    const SizedBox(height: 7),
                    if (amount != null)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: palette.accentSurface,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          'From ₹${(amount / 100).toStringAsFixed(2)}',
                          style: AbashyakaTypography.ratingText(
                            color: palette.accent,
                            fontSize: 12.5,
                          ),
                        ),
                      )
                    else
                      Text(
                        'View available options',
                        style: AbashyakaTypography.supportingText(
                          color: palette.textMuted,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProductImagePlaceholder extends StatelessWidget {
  const _ProductImagePlaceholder();
  @override
  Widget build(BuildContext context) => Container(
    color: AppTheme.surfaceVariant,
    child: const Center(
      child: Icon(
        Icons.shopping_bag_outlined,
        color: AppTheme.secondaryText,
        size: 38,
      ),
    ),
  );
}

class _CategoryChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _CategoryChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) => ChoiceChip(
    label: Text(label),
    selected: selected,
    onSelected: (_) => onTap(),
    selectedColor: AppTheme.emerald,
    backgroundColor: context.abashyaka.card,
    labelStyle: TextStyle(
      color: selected ? Colors.white : context.abashyaka.textPrimary,
      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
    ),
    side: BorderSide(
      color: selected ? AppTheme.emerald : context.abashyaka.border,
    ),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
  );
}

class _CatalogMessage extends StatelessWidget {
  final IconData icon;
  final String title;
  final String detail;
  final Widget? action;
  const _CatalogMessage({
    required this.icon,
    required this.title,
    required this.detail,
    this.action,
  });
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 42, color: AppTheme.secondaryText),
          const SizedBox(height: 14),
          Text(
            title,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Text(
            detail,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium
                ?.copyWith(color: AppTheme.secondaryText),
          ),
          if (action != null) ...[const SizedBox(height: 10), action!],
        ],
      ),
    ),
  );
}
