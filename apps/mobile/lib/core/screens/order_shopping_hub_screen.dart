import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:grepmind_mobile/core/providers/app_provider.dart';
import 'package:grepmind_mobile/core/network/api_client.dart';
import 'package:grepmind_mobile/core/models/platform_catalog.dart';
import 'package:grepmind_mobile/core/providers/platform_catalog_provider.dart';
import 'package:grepmind_mobile/core/providers/platform_cart_provider.dart';
import 'package:grepmind_mobile/core/screens/order_history_screen.dart';
import 'package:grepmind_mobile/core/screens/platform_catalog_screen.dart';
import 'package:grepmind_mobile/core/screens/platform_product_detail_screen.dart';
import 'package:grepmind_mobile/core/screens/platform_cart_screen.dart';
import 'package:grepmind_mobile/core/theme/app_theme.dart';

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
                                      color: AppTheme.primary,
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
                  Container(
                    padding: const EdgeInsets.all(22),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFFE7F0FF), Color(0xFFF8FAFF)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: AppTheme.border),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Your everyday needs,\ndelivered locally',
                          style: Theme.of(context).textTheme.headlineMedium
                              ?.copyWith(
                                fontWeight: FontWeight.w700,
                                height: 1.18,
                              ),
                        ),
                        const SizedBox(height: 9),
                        Text(
                          'Browse the Grepmind catalog, fulfilled by approved nearby partners.',
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(color: AppTheme.secondaryText),
                        ),
                        const SizedBox(height: 16),
                        const Row(
                          children: [
                            Icon(
                              Icons.verified_user_outlined,
                              size: 17,
                              color: AppTheme.secondary,
                            ),
                            SizedBox(width: 7),
                            Expanded(
                              child: Text(
                                'Curated locally. Prices set by Grepmind.',
                                style: TextStyle(
                                  color: AppTheme.secondary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 23),
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
                    const SizedBox(height: 24),
                    _FeaturedCatalogSection(
                      city: districtName,
                      locality: locality?.name ?? '',
                      localityId: locality?.id ?? '',
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

class _FeaturedCatalogSection extends ConsumerWidget {
  final String city;
  final String locality;
  final String localityId;
  final ValueChanged<PlatformCatalogProduct> onTap;

  const _FeaturedCatalogSection({
    required this.city,
    required this.locality,
    required this.localityId,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final foodQuery = PlatformCatalogQuery(
      vertical: 'food',
      city: city,
      locality: locality,
      localityId: localityId,
    );
    final groceryQuery = PlatformCatalogQuery(
      vertical: 'grocery',
      city: city,
      locality: locality,
      localityId: localityId,
    );
    final food = ref.watch(platformCatalogProductsProvider(foodQuery));
    final grocery = ref.watch(platformCatalogProductsProvider(groceryQuery));
    final products = [
      ...?food.valueOrNull?.products.take(3),
      ...?grocery.valueOrNull?.products.take(3),
    ];
    if (products.isEmpty && food.isLoading && grocery.isLoading) {
      return const SizedBox(
        height: 84,
        child: Center(child: LinearProgressIndicator()),
      );
    }
    if (products.isEmpty && (food.hasError || grocery.hasError)) {
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
    if (products.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Available in your area',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => PlatformCatalogScreen(
                    vertical: 'food',
                    city: city,
                    locality: locality,
                    localityId: localityId,
                  ),
                ),
              ),
              child: const Text('Explore'),
            ),
          ],
        ),
        const SizedBox(height: 6),
        SizedBox(
          height: 176,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: products.length,
            separatorBuilder: (_, _) => const SizedBox(width: 11),
            itemBuilder: (context, index) => _FeaturedProductCard(
              product: products[index],
              onTap: () => onTap(products[index]),
            ),
          ),
        ),
      ],
    );
  }
}

class _FeaturedProductCard extends StatelessWidget {
  final PlatformCatalogProduct product;
  final VoidCallback onTap;
  const _FeaturedProductCard({required this.product, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final image = product.imageUrls.isEmpty ? null : product.imageUrls.first;
    final amount = product.lowestPriceMinor;
    return SizedBox(
      width: 142,
      child: Material(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(17),
        child: InkWell(
          borderRadius: BorderRadius.circular(17),
          onTap: onTap,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(17),
              border: Border.all(color: AppTheme.border),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: image == null
                      ? const _FeaturedPlaceholder()
                      : CachedNetworkImage(
                          imageUrl: apiClient.resolveMediaUrl(image),
                          fit: BoxFit.cover,
                          width: double.infinity,
                          placeholder: (_, _) => const _FeaturedPlaceholder(),
                          errorWidget: (_, _, _) =>
                              const _FeaturedPlaceholder(),
                        ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(10, 8, 10, 9),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        product.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                      Text(
                        amount == null
                            ? product.categoryName
                            : '₹${(amount / 100).toStringAsFixed(2)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall
                            ?.copyWith(color: AppTheme.secondaryText),
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

class _FeaturedPlaceholder extends StatelessWidget {
  const _FeaturedPlaceholder();
  @override
  Widget build(BuildContext context) => Container(
    color: AppTheme.surfaceVariant,
    child: const Center(
      child: Icon(
        Icons.shopping_bag_outlined,
        color: AppTheme.secondaryText,
        size: 30,
      ),
    ),
  );
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
