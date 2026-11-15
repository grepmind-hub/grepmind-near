import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:grepmind_mobile/core/providers/app_provider.dart';
import 'package:grepmind_mobile/core/network/api_client.dart';
import 'package:grepmind_mobile/core/models/platform_catalog.dart';
import 'package:grepmind_mobile/core/models/customer_order.dart';
import 'package:grepmind_mobile/core/providers/platform_catalog_provider.dart';
import 'package:grepmind_mobile/core/providers/platform_cart_provider.dart';
import 'package:grepmind_mobile/core/providers/customer_orders_provider.dart';
import 'package:grepmind_mobile/core/screens/order_history_screen.dart';
import 'package:grepmind_mobile/core/screens/order_tracking_screen.dart';
import 'package:grepmind_mobile/core/screens/platform_catalog_screen.dart';
import 'package:grepmind_mobile/core/screens/platform_product_detail_screen.dart';
import 'package:grepmind_mobile/core/screens/platform_cart_screen.dart';
import 'package:grepmind_mobile/core/theme/app_theme.dart';
import 'package:grepmind_mobile/core/widgets/category_placeholder.dart';
import 'package:grepmind_mobile/core/widgets/sticky_cart_summary_bar.dart';

class OrderShoppingHubScreen extends ConsumerStatefulWidget {
  const OrderShoppingHubScreen({super.key});

  @override
  ConsumerState<OrderShoppingHubScreen> createState() =>
      _OrderShoppingHubScreenState();
}

class _OrderShoppingHubScreenState
    extends ConsumerState<OrderShoppingHubScreen> {
  List<DeliveryDistrict> _districts = const [];
  DeliveryDistrict? _selectedDistrict;
  DeliveryLocality? _selectedLocality;
  bool _locationsLoading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ref.read(appLocationProvider.notifier).loadDefaultLocation();
        _loadDeliveryLocations();
      }
    });
  }

  Future<void> _loadDeliveryLocations() async {
    try {
      final districts = await ref
          .read(platformCatalogRepositoryProvider)
          .locations();
      final locationStorage = ref.read(deliveryLocationStorageProvider);
      final saved = await locationStorage.read();
      final appCity = ref.read(appLocationProvider).cityName;
      DeliveryDistrict? district;
      DeliveryLocality? locality;
      var savedDistrictFound = false;
      for (final candidate in districts) {
        if (saved != null &&
            candidate.name.toLowerCase() == saved.district.toLowerCase()) {
          district = candidate;
          savedDistrictFound = true;
          for (final option in candidate.localities) {
            if (saved.localityId.isNotEmpty && option.id == saved.localityId) {
              locality = option;
            }
          }
        }
      }
      if (district == null) {
        for (final candidate in districts) {
          if (candidate.name.toLowerCase() == appCity.toLowerCase()) {
            district = candidate;
            break;
          }
        }
      }
      district ??= districts.isEmpty ? null : districts.first;
      if (locality == null && district != null && !savedDistrictFound) {
        for (final option in district.localities) {
          if (option.deliveryEnabled) {
            locality = option;
            break;
          }
        }
      }
      if (!mounted) return;
      setState(() {
        _districts = districts;
        _selectedDistrict = district;
        _selectedLocality = locality;
        _locationsLoading = false;
      });
      if (district != null && locality != null) {
        await ref
            .read(deliveryLocationStorageProvider)
            .write(
              DeliveryLocationSelection(
                district: district.name,
                localityId: locality.id,
                locality: locality.name,
              ),
            );
      }
    } catch (_) {
      if (mounted) setState(() => _locationsLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final location = ref.watch(appLocationProvider);
    final userId = ref.watch(currentUserProvider)?.id ?? '';
    final districtName =
        _selectedDistrict?.name ??
        (_isSupportedCity(location.cityName) ? location.cityName : '');
    final locality = _selectedLocality;
    final foodScope = PlatformCartScope(
      userId: userId,
      vertical: 'food',
      localityId: locality?.id ?? '',
      locality: locality?.name ?? '',
      district: districtName,
    );
    final groceryScope = PlatformCartScope(
      userId: userId,
      vertical: 'grocery',
      localityId: locality?.id ?? '',
      locality: locality?.name ?? '',
      district: districtName,
    );
    final foodCart = ref.watch(platformCartProvider(foodScope));
    final groceryCart = ref.watch(platformCartProvider(groceryScope));
    final hasDeliveryCity = districtName.isNotEmpty;
    return Scaffold(
      backgroundColor: AppTheme.background,
      bottomNavigationBar: groceryCart.itemCount > 0
          ? StickyCartSummaryBar(scope: groceryScope)
          : foodCart.itemCount > 0
              ? StickyCartSummaryBar(scope: foodScope)
              : null,
      body: SafeArea(
        child: CustomScrollView(
          key: const ValueKey('orders_shopping_hub_scroll'),
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
              sliver: SliverList.list(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Order on Grepmind',
                              style: Theme.of(context).textTheme.headlineSmall,
                            ),
                            const SizedBox(height: 7),
                            InkWell(
                              key: const ValueKey('orders_delivery_location'),
                              borderRadius: BorderRadius.circular(14),
                              onTap: () => _chooseLocation(context),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 5,
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(
                                      Icons.location_on_outlined,
                                      size: 18,
                                      color: AppTheme.emerald,
                                    ),
                                    const SizedBox(width: 5),
                                    Text(
                                      !hasDeliveryCity
                                          ? 'Choose delivery location'
                                          : (locality == null
                                                ? districtName
                                                : '${locality.name}, $districtName'),
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodyMedium
                                          ?.copyWith(
                                            color: AppTheme.secondaryText,
                                            fontWeight: FontWeight.w600,
                                          ),
                                    ),
                                    const Icon(
                                      Icons.keyboard_arrow_down_rounded,
                                      color: AppTheme.secondaryText,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'My orders',
                        onPressed: () => _openOrders(context),
                        icon: const Icon(Icons.receipt_long_outlined),
                      ),
                      IconButton(
                        tooltip: 'Search catalog',
                        onPressed: () => _openCatalog(
                          context,
                          'food',
                          location,
                          search: true,
                        ),
                        icon: const Icon(Icons.search_rounded),
                      ),
                      IconButton(
                        key: const ValueKey('platform_cart_button'),
                        tooltip: 'Food and Grocery carts',
                        onPressed: locality == null || userId.isEmpty
                            ? null
                            : () => _openCartPicker(
                                context,
                                foodScope,
                                groceryScope,
                                foodCart.itemCount,
                                groceryCart.itemCount,
                              ),
                        icon: Badge(
                          isLabelVisible:
                              foodCart.itemCount + groceryCart.itemCount > 0,
                          label: Text(
                            '${foodCart.itemCount + groceryCart.itemCount}',
                          ),
                          child: const Icon(Icons.shopping_cart_outlined),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 23),
                  Builder(
                    builder: (context) {
                      final ordersState = ref.watch(customerOrdersProvider);
                      final activeOrder = ordersState.orders
                          .where((o) => o.isActive)
                          .firstOrNull;
                      if (activeOrder == null) return const SizedBox.shrink();
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: _ActiveOrderHubBanner(
                          order: activeOrder,
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) =>
                                  OrderTrackingScreen(orderId: activeOrder.id),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFFF0FDF4), Color(0xFFF8FAFC)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFFBBF7D0)),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: const Color(0xFFDCFCE7),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(
                            Icons.bolt_rounded,
                            color: Color(0xFF059669),
                            size: 22,
                          ),
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'Everyday essentials, delivered fast',
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 14,
                                  color: Color(0xFF0F172A),
                                ),
                              ),
                              SizedBox(height: 2),
                              Text(
                                'Curated locally · Prices set by Grepmind',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Color(0xFF059669),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.timer_outlined,
                                size: 12,
                                color: Color(0xFF64748B),
                              ),
                              SizedBox(width: 3),
                              Text(
                                '15-30m',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF334155),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: _VerticalCard(
                          title: 'Food & Meals',
                          subtitle: 'Explore food catalog',
                          icon: Icons.restaurant_rounded,
                          color: const Color(0xFFF28C45),
                          keyName: 'orders_food_catalog',
                          onTap: () => _openCatalog(context, 'food', location),
                        ),
                      ),
                      const SizedBox(width: 13),
                      Expanded(
                        child: _VerticalCard(
                          title: 'Groceries',
                          subtitle: 'Explore grocery catalog',
                          icon: Icons.shopping_basket_rounded,
                          color: AppTheme.secondary,
                          keyName: 'orders_grocery_catalog',
                          onTap: () =>
                              _openCatalog(context, 'grocery', location),
                        ),
                      ),
                    ],
                  ),
                  if (hasDeliveryCity) ...[
                    const SizedBox(height: 20),
                    _FeaturedCatalogSection(
                      city: districtName,
                      locality: locality?.name ?? '',
                      localityId: locality?.id ?? '',
                      userId: userId,
                      onChooseLocation: () => _chooseLocation(context),
                      onTap: (product) =>
                          _openFeaturedProduct(context, product, location),
                    ),
                  ],
                  const SizedBox(height: 18),
                  Material(
                    color: AppTheme.surface,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                      side: const BorderSide(color: AppTheme.border),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      children: [
                        _HubAction(
                          keyName: 'orders_active_shortcut',
                          icon: Icons.local_shipping_outlined,
                          title: 'Active orders',
                          subtitle: 'Track a recent order or booking',
                          onTap: () => _openOrders(context),
                        ),
                        const Divider(height: 1, indent: 18, endIndent: 18),
                        _HubAction(
                          keyName: 'orders_history_entry',
                          icon: Icons.receipt_long_outlined,
                          title: 'My Orders',
                          subtitle: 'Order history, bookings and tracking',
                          onTap: () => _openOrders(context),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 15),
                  if (locality != null && userId.isNotEmpty)
                    Center(
                      child: TextButton.icon(
                        onPressed: () => _openCartPicker(
                          context,
                          foodScope,
                          groceryScope,
                          foodCart.itemCount,
                          groceryCart.itemCount,
                        ),
                        icon: const Icon(
                          Icons.shopping_cart_outlined,
                          size: 18,
                        ),
                        label: const Text('View Food and Grocery carts'),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openCatalog(
    BuildContext context,
    String vertical,
    AppLocation location, {
    bool search = false,
  }) {
    final city = _isSupportedCity(location.cityName) ? location.cityName : '';
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PlatformCatalogScreen(
          vertical: vertical,
          city: _selectedDistrict?.name ?? city,
          locality: _selectedLocality?.name ?? '',
          localityId: _selectedLocality?.id ?? '',
          startInSearch: search,
        ),
      ),
    );
  }

  void _openFeaturedProduct(
    BuildContext context,
    PlatformCatalogProduct product,
    AppLocation location,
  ) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PlatformProductDetailScreen(
          id: product.id,
          vertical: product.vertical,
          city: _selectedDistrict?.name ?? location.cityName,
          locality: _selectedLocality?.name ?? '',
          localityId: _selectedLocality?.id ?? '',
        ),
      ),
    );
  }

  bool _isSupportedCity(String city) =>
      const {'cuttack', 'jajpur'}.contains(city.trim().toLowerCase());

  void _openOrders(BuildContext context) {
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const OrderHistoryScreen()));
  }

  Future<void> _openCartPicker(
    BuildContext context,
    PlatformCartScope food,
    PlatformCartScope grocery,
    int foodCount,
    int groceryCount,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(
                Icons.restaurant_outlined,
                color: AppTheme.primary,
              ),
              title: const Text('Food cart'),
              subtitle: Text(
                '$foodCount items · ${food.locality}, ${food.district}',
              ),
              onTap: () {
                Navigator.pop(sheetContext);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => PlatformCartScreen(scope: food),
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(
                Icons.shopping_basket_outlined,
                color: AppTheme.secondary,
              ),
              title: const Text('Grocery cart'),
              subtitle: Text(
                '$groceryCount items · ${grocery.locality}, ${grocery.district}',
              ),
              onTap: () {
                Navigator.pop(sheetContext);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => PlatformCartScreen(scope: grocery),
                  ),
                );
              },
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  Future<void> _chooseLocation(BuildContext context) async {
    if (_districts.isEmpty && !_locationsLoading) {
      await _loadDeliveryLocations();
    }
    if (!context.mounted) return;
    if (_districts.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Delivery locations are unavailable. Please retry.'),
        ),
      );
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        var district = _selectedDistrict ?? _districts.first;
        return StatefulBuilder(
          builder: (context, setSheetState) => SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
              shrinkWrap: true,
              children: [
                Text(
                  'Delivery district',
                  style: Theme.of(sheetContext).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 10,
                  children: [
                    for (final option in _districts)
                      ChoiceChip(
                        key: ValueKey('delivery-district-${option.id}'),
                        label: Text(option.name),
                        selected: district.id == option.id,
                        onSelected: (_) async {
                          setSheetState(() => district = option);
                          setState(() {
                            _selectedDistrict = option;
                            _selectedLocality = null;
                          });
                          await ref
                              .read(deliveryLocationStorageProvider)
                              .writeDistrict(option.name);
                        },
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  'Delivery locality',
                  style: Theme.of(sheetContext).textTheme.titleMedium,
                ),
                for (final locality in district.localities)
                  ListTile(
                    key: ValueKey(
                      'delivery-locality-${district.id}-${locality.id}',
                    ),
                    leading: const Icon(
                      Icons.location_on_outlined,
                      color: AppTheme.primary,
                    ),
                    title: Text(locality.name),
                    subtitle: Text(
                      locality.deliveryEnabled
                          ? 'Delivery enabled'
                          : 'Planned · delivery not enabled',
                    ),
                    trailing: locality.deliveryEnabled
                        ? const Icon(
                            Icons.check_circle_rounded,
                            color: AppTheme.secondary,
                          )
                        : const Icon(
                            Icons.schedule_outlined,
                            color: AppTheme.secondaryText,
                          ),
                    onTap: () async {
                      setState(() {
                        _selectedDistrict = district;
                        _selectedLocality = locality;
                      });
                      await ref
                          .read(deliveryLocationStorageProvider)
                          .write(
                            DeliveryLocationSelection(
                              district: district.name,
                              localityId: locality.id,
                              locality: locality.name,
                            ),
                          );
                      if (sheetContext.mounted) Navigator.pop(sheetContext);
                    },
                  ),
                TextButton.icon(
                  onPressed: () async {
                    setState(() {
                      _selectedDistrict = null;
                      _selectedLocality = null;
                    });
                    await ref.read(deliveryLocationStorageProvider).clear();
                    if (!sheetContext.mounted) return;
                    Navigator.pop(sheetContext);
                  },
                  icon: const Icon(Icons.clear_rounded),
                  label: const Text('Clear location'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _FeaturedCatalogSection extends ConsumerStatefulWidget {
  final String city;
  final String locality;
  final String localityId;
  final String userId;
  final VoidCallback onChooseLocation;
  final ValueChanged<PlatformCatalogProduct> onTap;

  const _FeaturedCatalogSection({
    required this.city,
    required this.locality,
    required this.localityId,
    required this.userId,
    required this.onChooseLocation,
    required this.onTap,
  });

  @override
  ConsumerState<_FeaturedCatalogSection> createState() =>
      _FeaturedCatalogSectionState();
}

class _FeaturedCatalogSectionState
    extends ConsumerState<_FeaturedCatalogSection> {
  String _selectedFilter = 'all';

  @override
  Widget build(BuildContext context) {
    final foodQuery = PlatformCatalogQuery(
      vertical: 'food',
      city: widget.city,
      locality: widget.locality,
      localityId: widget.localityId,
    );
    final groceryQuery = PlatformCatalogQuery(
      vertical: 'grocery',
      city: widget.city,
      locality: widget.locality,
      localityId: widget.localityId,
    );
    final food = ref.watch(platformCatalogProductsProvider(foodQuery));
    final grocery = ref.watch(platformCatalogProductsProvider(groceryQuery));

    final foodProducts = food.valueOrNull?.products ?? [];
    final groceryProducts = grocery.valueOrNull?.products ?? [];

    List<PlatformCatalogProduct> displayProducts;
    if (_selectedFilter == 'food') {
      displayProducts = foodProducts;
    } else if (_selectedFilter == 'grocery') {
      displayProducts = groceryProducts;
    } else {
      displayProducts = [...foodProducts, ...groceryProducts];
    }

    if (foodProducts.isEmpty &&
        groceryProducts.isEmpty &&
        food.isLoading &&
        grocery.isLoading) {
      return const SizedBox(
        height: 84,
        child: Center(child: LinearProgressIndicator()),
      );
    }
    if (foodProducts.isEmpty &&
        groceryProducts.isEmpty &&
        (food.hasError || grocery.hasError)) {
      return Container(
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          border: Border.all(color: AppTheme.border),
          borderRadius: BorderRadius.circular(17),
        ),
        child: const Row(
          children: [
            Icon(Icons.info_outline_rounded, color: AppTheme.secondaryText),
            SizedBox(width: 9),
            Expanded(
              child: Text(
                'Featured catalog items could not be loaded. Open Food or Groceries to retry.',
              ),
            ),
          ],
        ),
      );
    }
    if (displayProducts.isEmpty &&
        foodProducts.isEmpty &&
        groceryProducts.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      'Food & Groceries',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.3,
                          ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFDCFCE7),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text(
                        'Direct order',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF15803D),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                const Text(
                  'Delivered fast by approved local partners',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppTheme.secondaryText,
                  ),
                ),
              ],
            ),
            TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => PlatformCatalogScreen(
                    vertical: _selectedFilter == 'grocery' ? 'grocery' : 'food',
                    city: widget.city,
                    locality: widget.locality,
                    localityId: widget.localityId,
                  ),
                ),
              ),
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                foregroundColor: const Color(0xFF059669),
                textStyle: const TextStyle(fontWeight: FontWeight.w700),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('See All'),
                  Icon(Icons.chevron_right_rounded, size: 16),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _FilterPill(
                label: 'All (${foodProducts.length + groceryProducts.length})',
                icon: Icons.auto_awesome_rounded,
                selected: _selectedFilter == 'all',
                onTap: () => setState(() => _selectedFilter = 'all'),
              ),
              const SizedBox(width: 8),
              _FilterPill(
                label: 'Food & Meals (${foodProducts.length})',
                icon: Icons.restaurant_rounded,
                selected: _selectedFilter == 'food',
                onTap: () => setState(() => _selectedFilter = 'food'),
              ),
              const SizedBox(width: 8),
              _FilterPill(
                label: 'Fresh Groceries (${groceryProducts.length})',
                icon: Icons.local_grocery_store_rounded,
                selected: _selectedFilter == 'grocery',
                onTap: () => setState(() => _selectedFilter = 'grocery'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: displayProducts.length,
          separatorBuilder: (_, _) => const SizedBox(height: 14),
          itemBuilder: (context, index) {
            final product = displayProducts[index];
            return _ZomatoFoodGroceryCard(
              product: product,
              city: widget.city,
              locality: widget.locality,
              localityId: widget.localityId,
              userId: widget.userId,
              onChooseLocation: widget.onChooseLocation,
              onTap: () => widget.onTap(product),
            );
          },
        ),
      ],
    );
  }
}

class _FilterPill extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _FilterPill({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF0F172A) : AppTheme.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? const Color(0xFF0F172A) : AppTheme.border,
            width: selected ? 1.5 : 1.0,
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 14,
              color: selected ? Colors.white : AppTheme.secondaryText,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected ? Colors.white : AppTheme.mainText,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ZomatoFoodGroceryCard extends ConsumerWidget {
  final PlatformCatalogProduct product;
  final String city;
  final String locality;
  final String localityId;
  final String userId;
  final VoidCallback onChooseLocation;
  final VoidCallback onTap;

  const _ZomatoFoodGroceryCard({
    required this.product,
    required this.city,
    required this.locality,
    required this.localityId,
    required this.userId,
    required this.onChooseLocation,
    required this.onTap,
  });

  bool get _isNonVeg {
    final text = '${product.name} ${product.categoryName} ${product.description}'.toLowerCase();
    return text.contains('chicken') ||
        text.contains('mutton') ||
        text.contains('fish') ||
        text.contains('egg') ||
        text.contains('meat') ||
        text.contains('prawn') ||
        text.contains('non-veg');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isFood = product.vertical == 'food';
    final scope = PlatformCartScope(
      userId: userId,
      vertical: product.vertical,
      localityId: localityId,
      locality: locality,
      district: city,
    );
    final cart = ref.watch(platformCartProvider(scope));

    final defaultVariant =
        product.variants.isNotEmpty ? product.variants.first : null;
    final currentQty = defaultVariant != null
        ? (cart.lines[defaultVariant.id]?.quantity ?? 0)
        : 0;

    final image = product.imageUrls.isNotEmpty ? product.imageUrls.first : null;
    final price = defaultVariant != null
        ? defaultVariant.priceMinor
        : product.lowestPriceMinor;

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          if (isFood) ...[
                            Container(
                              width: 15,
                              height: 15,
                              padding: const EdgeInsets.all(2),
                              decoration: BoxDecoration(
                                border: Border.all(
                                  color: _isNonVeg
                                      ? const Color(0xFFDC2626)
                                      : const Color(0xFF16A34A),
                                  width: 1.5,
                                ),
                                borderRadius: BorderRadius.circular(3),
                              ),
                              child: Center(
                                child: Container(
                                  width: 7,
                                  height: 7,
                                  decoration: BoxDecoration(
                                    color: _isNonVeg
                                        ? const Color(0xFFDC2626)
                                        : const Color(0xFF16A34A),
                                    shape: _isNonVeg
                                        ? BoxShape.rectangle
                                        : BoxShape.circle,
                                    borderRadius: _isNonVeg
                                        ? BorderRadius.circular(1)
                                        : null,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                          ],
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: isFood
                                  ? const Color(0xFFFFF7ED)
                                  : const Color(0xFFF0FDF4),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              product.categoryName.isNotEmpty
                                  ? product.categoryName
                                  : (isFood ? 'Food' : 'Grocery'),
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: isFood
                                    ? const Color(0xFFC2410C)
                                    : const Color(0xFF15803D),
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.bolt_rounded,
                                size: 12,
                                color: Color(0xFFEAB308),
                              ),
                              Text(
                                '20-30m',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF64748B),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        product.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF0F172A),
                          letterSpacing: -0.2,
                          height: 1.25,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Text(
                            price != null
                                ? '₹${(price / 100).toStringAsFixed(0)}'
                                : 'Check price',
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF059669),
                            ),
                          ),
                          if (defaultVariant != null &&
                              defaultVariant.unitLabel.isNotEmpty) ...[
                            const SizedBox(width: 4),
                            Text(
                              '/ ${defaultVariant.unitLabel}',
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                                color: Color(0xFF64748B),
                              ),
                            ),
                          ],
                        ],
                      ),
                      if (product.description.isNotEmpty) ...[
                        const SizedBox(height: 5),
                        Text(
                          product.description,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF64748B),
                            height: 1.3,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 14),
                SizedBox(
                  width: 108,
                  child: Column(
                    children: [
                      Container(
                        width: 108,
                        height: 96,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: image != null && image.isNotEmpty
                            ? CachedNetworkImage(
                                imageUrl: apiClient.resolveMediaUrl(image),
                                fit: BoxFit.cover,
                                placeholder: (_, _) =>
                                    CategoryThemedPlaceholder(
                                  categoryName: product.categoryName,
                                ),
                                errorWidget: (_, _, _) =>
                                    CategoryThemedPlaceholder(
                                  categoryName: product.categoryName,
                                ),
                              )
                            : CategoryThemedPlaceholder(
                                categoryName: product.categoryName,
                              ),
                      ),
                      const SizedBox(height: 6),
                      if (currentQty == 0)
                        SizedBox(
                          width: 100,
                          height: 32,
                          child: ElevatedButton(
                            onPressed: () async {
                              if (localityId.isEmpty) {
                                onChooseLocation();
                                return;
                              }
                              if (defaultVariant != null) {
                                final notifier = ref.read(
                                  platformCartProvider(scope).notifier,
                                );
                                final added = await notifier.add(
                                  product,
                                  defaultVariant,
                                );
                                if (added && context.mounted) {
                                  ScaffoldMessenger.of(context).hideCurrentSnackBar();
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      behavior: SnackBarBehavior.floating,
                                      backgroundColor: const Color(0xFF0F172A),
                                      content: Row(
                                        children: [
                                          const Icon(
                                            Icons.check_circle_rounded,
                                            color: Color(0xFF34D399),
                                            size: 18,
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Text(
                                              '${product.name} added to cart',
                                              style: const TextStyle(
                                                fontSize: 13,
                                                fontWeight: FontWeight.w600,
                                                color: Colors.white,
                                              ),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ],
                                      ),
                                      action: SnackBarAction(
                                        label: 'VIEW CART',
                                        textColor: const Color(0xFF34D399),
                                        onPressed: () {
                                          Navigator.of(context).push(
                                            MaterialPageRoute(
                                              builder: (_) =>
                                                  PlatformCartScreen(
                                                scope: scope,
                                              ),
                                            ),
                                          );
                                        },
                                      ),
                                    ),
                                  );
                                }
                              } else {
                                onTap();
                              }
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.white,
                              foregroundColor: const Color(0xFF059669),
                              elevation: 2,
                              shadowColor: Colors.black.withValues(alpha: 0.12),
                              side: const BorderSide(
                                color: Color(0xFF059669),
                                width: 1.5,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                              padding: EdgeInsets.zero,
                            ),
                            child: const Text(
                              'ADD +',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.3,
                              ),
                            ),
                          ),
                        )
                      else
                        Container(
                          width: 100,
                          height: 32,
                          decoration: BoxDecoration(
                            color: const Color(0xFF059669),
                            borderRadius: BorderRadius.circular(10),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFF059669).withValues(alpha: 0.3),
                                blurRadius: 4,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              InkWell(
                                onTap: () {
                                  if (defaultVariant != null) {
                                    ref
                                        .read(
                                          platformCartProvider(scope).notifier,
                                        )
                                        .setQuantity(
                                          defaultVariant.id,
                                          currentQty - 1,
                                        );
                                  }
                                },
                                child: const Padding(
                                  padding: EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 4,
                                  ),
                                  child: Icon(
                                    Icons.remove,
                                    color: Colors.white,
                                    size: 16,
                                  ),
                                ),
                              ),
                              Text(
                                '$currentQty',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 13,
                                ),
                              ),
                              InkWell(
                                onTap: () {
                                  if (defaultVariant != null) {
                                    ref
                                        .read(
                                          platformCartProvider(scope).notifier,
                                        )
                                        .add(product, defaultVariant);
                                  }
                                },
                                child: const Padding(
                                  padding: EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 4,
                                  ),
                                  child: Icon(
                                    Icons.add,
                                    color: Colors.white,
                                    size: 16,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _VerticalCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final String keyName;
  final VoidCallback onTap;

  const _VerticalCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.keyName,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => Material(
    color: AppTheme.surface,
    borderRadius: BorderRadius.circular(20),
    child: InkWell(
      key: ValueKey(keyName),
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 18, 14, 16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppTheme.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: color.withValues(alpha: .12),
                borderRadius: BorderRadius.circular(15),
              ),
              child: Icon(icon, color: color, size: 27),
            ),
            const SizedBox(height: 16),
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: AppTheme.secondaryText),
            ),
            const SizedBox(height: 10),
            const Icon(
              Icons.arrow_forward_rounded,
              color: AppTheme.primary,
              size: 18,
            ),
          ],
        ),
      ),
    ),
  );
}

class _HubAction extends StatelessWidget {
  final String keyName;
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _HubAction({
    required this.keyName,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => ListTile(
    key: ValueKey(keyName),
    minVerticalPadding: 13,
    leading: CircleAvatar(
      backgroundColor: AppTheme.primaryContainer,
      child: Icon(icon, color: AppTheme.primary),
    ),
    title: Text(title, style: Theme.of(context).textTheme.titleMedium),
    subtitle: Text(subtitle),
    trailing: const Icon(Icons.chevron_right_rounded),
    onTap: onTap,
  );
}

class _ActiveOrderHubBanner extends StatelessWidget {
  final CustomerOrder order;
  final VoidCallback onTap;

  const _ActiveOrderHubBanner({required this.order, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFE6F9F1), Color(0xFFF8FAF9)],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFB8F2DC), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF059669).withValues(alpha: 0.08),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF059669),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(
                    Icons.delivery_dining_rounded,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Text(
                            'LIVE ORDER',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF059669),
                              letterSpacing: 0.5,
                            ),
                          ),
                          if (order.etaMinutes > 0) ...[
                            const SizedBox(width: 6),
                            Text(
                              '• ~${order.etaMinutes}m ETA',
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF0D9488),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        order.businessName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                          color: Color(0xFF17352C),
                        ),
                      ),
                      Text(
                        order.statusDisplay,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF64748B),
                        ),
                      ),
                    ],
                  ),
                ),
                FilledButton.tonal(
                  onPressed: onTap,
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF059669),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: const Text(
                    'Track',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
