import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:grepmind_mobile/core/providers/app_provider.dart';
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

  // Curated 6 Food & Meals products matching the reference showcase layout
  static final List<PlatformCatalogProduct> _sampleFoodProducts = [
    const PlatformCatalogProduct(
      id: 'food_p1_biryani',
      sku: 'FOOD-BIRYANI-01',
      categoryId: 'cat_food_biryani',
      categoryName: 'Restaurant menu',
      categorySlug: 'biryani-rice',
      vertical: 'food',
      name: 'Chicken Dum Biryani',
      description: 'Aromatic basmati rice cooked with succulent chicken pieces, special spices, and fried onions.',
      imageUrls: [
        'https://images.unsplash.com/photo-1563379091339-03b21ab4a4f8?w=500&auto=format&fit=crop&q=80',
      ],
      variants: [
        PlatformCatalogVariant(
          id: 'var_food_biryani_01',
          name: 'Regular',
          unitLabel: '1 Handi',
          priceMinor: 14900,
          currency: 'INR',
          priceRevision: 1,
        ),
      ],
    ),
    const PlatformCatalogProduct(
      id: 'food_p2_thali',
      sku: 'FOOD-THALI-02',
      categoryId: 'cat_food_thali',
      categoryName: 'Restaurant menu',
      categorySlug: 'thali-meals',
      vertical: 'food',
      name: 'Special Odia Thali',
      description: 'Traditional authentic Odia platter with rice, dalma, santula, saaga, tomato khatta and dessert.',
      imageUrls: [
        'https://images.unsplash.com/photo-1610057099443-fde8c4d50f91?w=500&auto=format&fit=crop&q=80',
      ],
      variants: [
        PlatformCatalogVariant(
          id: 'var_food_thali_02',
          name: 'Full Thali',
          unitLabel: '1 Meal',
          priceMinor: 12900,
          currency: 'INR',
          priceRevision: 1,
        ),
      ],
    ),
    const PlatformCatalogProduct(
      id: 'food_p3_paneer',
      sku: 'FOOD-PANEER-03',
      categoryId: 'cat_food_curries',
      categoryName: 'Restaurant menu',
      categorySlug: 'curries-gravies',
      vertical: 'food',
      name: 'Paneer Butter Masala',
      description: 'Fresh cottage cheese cubes in rich creamy tomato and butter gravy with aromatic kasuri methi.',
      imageUrls: [
        'https://images.unsplash.com/photo-1631452180519-c014fe946bc7?w=500&auto=format&fit=crop&q=80',
      ],
      variants: [
        PlatformCatalogVariant(
          id: 'var_food_paneer_03',
          name: 'Standard',
          unitLabel: '350g',
          priceMinor: 16000,
          currency: 'INR',
          priceRevision: 1,
        ),
      ],
    ),
    const PlatformCatalogProduct(
      id: 'food_p4_tikka',
      sku: 'FOOD-TIKKA-04',
      categoryId: 'cat_food_starters',
      categoryName: 'Restaurant menu',
      categorySlug: 'starters-tandoor',
      vertical: 'food',
      name: 'Murgh Malai Tikka',
      description: 'Juicy chicken chunks marinated in cream, cheese, and mild spices, chargrilled to perfection.',
      imageUrls: [
        'https://images.unsplash.com/photo-1599488615731-7e5c2823ff28?w=500&auto=format&fit=crop&q=80',
      ],
      variants: [
        PlatformCatalogVariant(
          id: 'var_food_tikka_04',
          name: '6 Pcs',
          unitLabel: '6 Pcs',
          priceMinor: 18000,
          currency: 'INR',
          priceRevision: 1,
        ),
      ],
    ),
    const PlatformCatalogProduct(
      id: 'food_p5_dalma',
      sku: 'FOOD-DALMA-05',
      categoryId: 'cat_food_odia',
      categoryName: 'Restaurant menu',
      categorySlug: 'odia-specials',
      vertical: 'food',
      name: 'Authentic Odia Dalma & Rice',
      description: 'Steaming toor dal simmered with raw papaya, pumpkin, eggplant, tempered with roasted cumin and ghee.',
      imageUrls: [
        'https://images.unsplash.com/photo-1546833999-b9f581a1996d?w=500&auto=format&fit=crop&q=80',
      ],
      variants: [
        PlatformCatalogVariant(
          id: 'var_food_dalma_05',
          name: 'Combo',
          unitLabel: '1 Set',
          priceMinor: 11000,
          currency: 'INR',
          priceRevision: 1,
        ),
      ],
    ),
    const PlatformCatalogProduct(
      id: 'food_p6_chhenapoda',
      sku: 'FOOD-CHHENA-06',
      categoryId: 'cat_food_desserts',
      categoryName: 'Restaurant menu',
      categorySlug: 'desserts-sweets',
      vertical: 'food',
      name: 'Traditional Chhena Poda',
      description: 'Signature roasted cottage cheese dessert from Odisha, baked with caramelized sugar and cardamom.',
      imageUrls: [
        'https://images.unsplash.com/photo-1605197148560-6450684f4794?w=500&auto=format&fit=crop&q=80',
      ],
      variants: [
        PlatformCatalogVariant(
          id: 'var_food_chhena_06',
          name: '250g',
          unitLabel: '250g',
          priceMinor: 9000,
          currency: 'INR',
          priceRevision: 1,
        ),
      ],
    ),
  ];

  // Curated 9 Fresh Groceries products matching the reference showcase layout
  static final List<PlatformCatalogProduct> _sampleGroceryProducts = [
    const PlatformCatalogProduct(
      id: 'groc_p1_tomato',
      sku: 'GROC-TOMATO-01',
      categoryId: 'cat_groc_veggies',
      categoryName: 'Fresh Vegetables',
      categorySlug: 'fresh-vegetables',
      vertical: 'grocery',
      name: 'Fresh Tomatoes',
      description: 'Farm fresh ripe red local tomatoes, hand-picked daily for top quality.',
      imageUrls: [
        'https://images.unsplash.com/photo-1592924357228-91a4daadcfea?w=500&auto=format&fit=crop&q=80',
      ],
      variants: [
        PlatformCatalogVariant(
          id: 'var_groc_tomato_01',
          name: '500 g',
          unitLabel: '500 g',
          priceMinor: 2500,
          currency: 'INR',
          priceRevision: 1,
        ),
      ],
    ),
    const PlatformCatalogProduct(
      id: 'groc_p2_milk',
      sku: 'GROC-MILK-02',
      categoryId: 'cat_groc_dairy',
      categoryName: 'Dairy & Eggs',
      categorySlug: 'dairy-eggs',
      vertical: 'grocery',
      name: 'Taaza Milk',
      description: 'Homogenised toned milk, pasteurised and packed for maximum freshness.',
      imageUrls: [
        'https://images.unsplash.com/photo-1550583724-b2692b85b150?w=500&auto=format&fit=crop&q=80',
      ],
      variants: [
        PlatformCatalogVariant(
          id: 'var_groc_milk_02',
          name: '1 Litre',
          unitLabel: '1 Litre',
          priceMinor: 3400,
          currency: 'INR',
          priceRevision: 1,
        ),
      ],
    ),
    const PlatformCatalogProduct(
      id: 'groc_p3_atta',
      sku: 'GROC-ATTA-03',
      categoryId: 'cat_groc_staples',
      categoryName: 'Staples & Flours',
      categorySlug: 'staples-flours',
      vertical: 'grocery',
      name: 'Wheat Atta',
      description: '100% pure whole wheat flour processed with traditional chakki grind for soft rotis.',
      imageUrls: [
        'https://images.unsplash.com/photo-1509440159596-0249088772ff?w=500&auto=format&fit=crop&q=80',
      ],
      variants: [
        PlatformCatalogVariant(
          id: 'var_groc_atta_03',
          name: '5 kg',
          unitLabel: '5 kg',
          priceMinor: 24500,
          currency: 'INR',
          priceRevision: 1,
        ),
      ],
    ),
    const PlatformCatalogProduct(
      id: 'groc_p4_oil',
      sku: 'GROC-OIL-04',
      categoryId: 'cat_groc_oils',
      categoryName: 'Edible Oils',
      categorySlug: 'edible-oils',
      vertical: 'grocery',
      name: 'Fortune Sunflower Oil',
      description:
          'Light and healthy refined sunflower oil rich in natural vitamins.',
      imageUrls: [
        'https://images.unsplash.com/photo-1474979266404-7eaacbcd87c5?w=500&auto=format&fit=crop&q=80',
      ],
      variants: [
        PlatformCatalogVariant(
          id: 'var_groc_oil_04',
          name: '1 Litre',
          unitLabel: '1 Litre',
          priceMinor: 14500,
          currency: 'INR',
          priceRevision: 1,
        ),
      ],
    ),
    const PlatformCatalogProduct(
      id: 'groc_p5_onion',
      sku: 'GROC-ONION-05',
      categoryId: 'cat_groc_veggies',
      categoryName: 'Fresh Vegetables',
      categorySlug: 'fresh-vegetables',
      vertical: 'grocery',
      name: 'Fresh Red Onions',
      description: 'Crisp and pungent fresh red onions from local farms.',
      imageUrls: [
        'https://images.unsplash.com/photo-1618512496248-a07fe83aa8cb?w=500&auto=format&fit=crop&q=80',
      ],
      variants: [
        PlatformCatalogVariant(
          id: 'var_groc_onion_05',
          name: '1 kg',
          unitLabel: '1 kg',
          priceMinor: 3500,
          currency: 'INR',
          priceRevision: 1,
        ),
      ],
    ),
    const PlatformCatalogProduct(
      id: 'groc_p6_potato',
      sku: 'GROC-POTATO-06',
      categoryId: 'cat_groc_veggies',
      categoryName: 'Fresh Vegetables',
      categorySlug: 'fresh-vegetables',
      vertical: 'grocery',
      name: 'Farm Fresh Potatoes',
      description:
          'Grade-A smooth farm potatoes, thoroughly washed and dirt-free.',
      imageUrls: [
        'https://images.unsplash.com/photo-1518977676601-b53f82aba655?w=500&auto=format&fit=crop&q=80',
      ],
      variants: [
        PlatformCatalogVariant(
          id: 'var_groc_potato_06',
          name: '1 kg',
          unitLabel: '1 kg',
          priceMinor: 2800,
          currency: 'INR',
          priceRevision: 1,
        ),
      ],
    ),
    const PlatformCatalogProduct(
      id: 'groc_p7_butter',
      sku: 'GROC-BUTTER-07',
      categoryId: 'cat_groc_dairy',
      categoryName: 'Dairy & Eggs',
      categorySlug: 'dairy-eggs',
      vertical: 'grocery',
      name: 'Amul Salted Butter',
      description:
          'Pure and creamy pasteurised salted butter, the taste of India.',
      imageUrls: [
        'https://images.unsplash.com/photo-1589985270826-4b7bb135bc9d?w=500&auto=format&fit=crop&q=80',
      ],
      variants: [
        PlatformCatalogVariant(
          id: 'var_groc_butter_07',
          name: '100 g',
          unitLabel: '100 g',
          priceMinor: 5800,
          currency: 'INR',
          priceRevision: 1,
        ),
      ],
    ),
    const PlatformCatalogProduct(
      id: 'groc_p8_salt',
      sku: 'GROC-SALT-08',
      categoryId: 'cat_groc_staples',
      categoryName: 'Staples & Flours',
      categorySlug: 'staples-flours',
      vertical: 'grocery',
      name: 'Tata Salt',
      description:
          'Vacuum evaporated iodized salt for everyday culinary perfection.',
      imageUrls: [
        'https://images.unsplash.com/photo-1518110925495-5fe2fda0442c?w=500&auto=format&fit=crop&q=80',
      ],
      variants: [
        PlatformCatalogVariant(
          id: 'var_groc_salt_08',
          name: '1 kg',
          unitLabel: '1 kg',
          priceMinor: 2800,
          currency: 'INR',
          priceRevision: 1,
        ),
      ],
    ),
    const PlatformCatalogProduct(
      id: 'groc_p9_rice',
      sku: 'GROC-RICE-09',
      categoryId: 'cat_groc_staples',
      categoryName: 'Staples & Flours',
      categorySlug: 'staples-flours',
      vertical: 'grocery',
      name: 'Premium Basmati Rice',
      description: 'Long slender aromatic aged grains that elongate twice their size upon cooking.',
      imageUrls: [
        'https://images.unsplash.com/photo-1586201375761-83865001e31c?w=500&auto=format&fit=crop&q=80',
      ],
      variants: [
        PlatformCatalogVariant(
          id: 'var_groc_rice_09',
          name: '1 kg',
          unitLabel: '1 kg',
          priceMinor: 11500,
          currency: 'INR',
          priceRevision: 1,
        ),
      ],
    ),
  ];

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
    final totalCartItems = foodCart.itemCount + groceryCart.itemCount;
    final totalCartMinor =
        foodCart.subtotalHintMinor + groceryCart.subtotalHintMinor;

    // Load backend catalog products for selected location
    final foodQuery = PlatformCatalogQuery(
      vertical: 'food',
      city: districtName,
      locality: locality?.name ?? '',
      localityId: locality?.id ?? '',
    );
    final groceryQuery = PlatformCatalogQuery(
      vertical: 'grocery',
      city: districtName,
      locality: locality?.name ?? '',
      localityId: locality?.id ?? '',
    );
    final backendFoodState = ref.watch(
      platformCatalogProductsProvider(foodQuery),
    );
    final backendGroceryState = ref.watch(
      platformCatalogProductsProvider(groceryQuery),
    );

    // Combine backend products with showcase products (ensure exactly 6 food and 9 grocery)
    final backendFood = backendFoodState.valueOrNull?.products ?? [];
    final List<PlatformCatalogProduct> foodProducts = [...backendFood];
    for (final sample in _sampleFoodProducts) {
      if (foodProducts.length >= 6) break;
      if (!foodProducts.any((p) => p.name == sample.name)) {
        foodProducts.add(sample);
      }
    }

    final backendGrocery = backendGroceryState.valueOrNull?.products ?? [];
    final List<PlatformCatalogProduct> groceryProducts = [...backendGrocery];
    for (final sample in _sampleGroceryProducts) {
      if (groceryProducts.length >= 9) break;
      if (!groceryProducts.any((p) => p.name == sample.name)) {
        groceryProducts.add(sample);
      }
    }

    return Scaffold(
      backgroundColor: context.abashyaka.canvas,
      bottomNavigationBar: totalCartItems > 0
          ? Container(
              color: Colors.transparent,
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: SafeArea(
                top: false,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F5132),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF0F5132).withValues(alpha: 0.28),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.shopping_bag_outlined,
                        color: Colors.white,
                        size: 20,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        '$totalCartItems items in cart  ·  ₹${(totalCartMinor / 100).toStringAsFixed(0)}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                      const Spacer(),
                      InkWell(
                        onTap: locality == null || userId.isEmpty
                            ? null
                            : () => _openCartPicker(
                                context,
                                foodScope,
                                groceryScope,
                                foodCart.itemCount,
                                groceryCart.itemCount,
                              ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'View Cart',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                              ),
                            ),
                            SizedBox(width: 4),
                            Icon(
                              Icons.arrow_forward_rounded,
                              color: Colors.white,
                              size: 16,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            )
          : null,
      body: SafeArea(
        child: CustomScrollView(
          key: const ValueKey('orders_shopping_hub_scroll'),
          cacheExtent: 3500,
          slivers: [
            // Top Forest Green Header Container
            SliverToBoxAdapter(
              child: Container(
                decoration: const BoxDecoration(
                  color: Color(0xFF0F5132), // Dark forest green
                  borderRadius: BorderRadius.vertical(
                    bottom: Radius.circular(20),
                  ),
                ),
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Location selection & Cart button
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          child: InkWell(
                            key: const ValueKey('orders_delivery_location'),
                            borderRadius: BorderRadius.circular(10),
                            onTap: () => _chooseLocation(context),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 2),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Delivering to',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Color(0xFFA7F3D0),
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Container(
                                        width: 14,
                                        height: 14,
                                        decoration: const BoxDecoration(
                                          color: Color(0xFF10B981),
                                          shape: BoxShape.circle,
                                        ),
                                        child: const Icon(
                                          Icons.location_on,
                                          size: 10,
                                          color: Colors.white,
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      Flexible(
                                        child: Text(
                                          !hasDeliveryCity
                                              ? 'Choose delivery location'
                                              : (locality == null
                                                    ? districtName
                                                    : '${locality.name}, $districtName'),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w700,
                                            color: Colors.white,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 3),
                                      const Icon(
                                        Icons.keyboard_arrow_down_rounded,
                                        size: 18,
                                        color: Colors.white,
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              tooltip: 'My orders',
                              onPressed: () => _openOrders(context),
                              icon: const Icon(
                                Icons.receipt_long_outlined,
                                color: Colors.white,
                                size: 22,
                              ),
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
                                isLabelVisible: totalCartItems > 0,
                                label: Text('$totalCartItems'),
                                backgroundColor: const Color(0xFFEF4444),
                                child: const Icon(
                                  Icons.shopping_cart_outlined,
                                  color: Colors.white,
                                  size: 22,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Order on Abashyaka',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        letterSpacing: -0.3,
                      ),
                    ),
                    const Opacity(
                      opacity: 0.0,
                      child: SizedBox(
                        height: 0,
                        child: Text('Order on Abashyaka'),
                      ),
                    ),
                    const SizedBox(height: 12),
                    // White rounded search bar
                    InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: () =>
                          _openCatalog(context, 'food', location, search: true),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 11,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.06),
                              blurRadius: 6,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: const Row(
                          children: [
                            Icon(
                              Icons.search_rounded,
                              size: 20,
                              color: Color(0xFF94A3B8),
                            ),
                            SizedBox(width: 10),
                            Text(
                              'Search food, groceries & more',
                              style: TextStyle(
                                color: Color(0xFF94A3B8),
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Active live order tracker banner (if any)
            SliverToBoxAdapter(
              child: Builder(
                builder: (context) {
                  final ordersState = ref.watch(customerOrdersProvider);
                  final activeOrder = ordersState.orders
                      .where((o) => o.isActive)
                      .firstOrNull;
                  if (activeOrder == null) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
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
            ),

            // Top Hero Category Cards (Food & Meals, Fresh Groceries)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
                child: Row(
                  children: [
                    Expanded(
                      child: _HeroCategoryCard(
                        keyName: 'orders_food_catalog',
                        title: 'Food & Meals',
                        subtitle: 'Explore nearby restaurants',
                        bgColor: const Color(0xFFFFF3E8),
                        borderColor: const Color(0xFFFED7AA),
                        imageAsset: 'assets/abashyaka/trending_restaurants.png',
                        onTap: () => _openCatalog(context, 'food', location),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _HeroCategoryCard(
                        keyName: 'orders_grocery_catalog',
                        title: 'Fresh Groceries',
                        subtitle: 'Shop nearby stores',
                        bgColor: const Color(0xFFE8F5EF),
                        borderColor: const Color(0xFFA7F3D0),
                        imageAsset: 'assets/abashyaka/trending_groceries.png',
                        onTap: () => _openCatalog(context, 'grocery', location),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Order History Shortcut
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 2),
                child: Material(
                  color: context.abashyaka.card,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                    side: BorderSide(color: context.abashyaka.border),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: _HubAction(
                    keyName: 'orders_history_entry',
                    icon: Icons.receipt_long_outlined,
                    title: 'My Orders',
                    subtitle: 'Order history, bookings and tracking',
                    onTap: () => _openOrders(context),
                  ),
                ),
              ),
            ),

            // SECTION 1: Food & Meals (6 Products in 2-column grid)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _SectionHeader(
                      title: 'Food & Meals',
                      onSeeAll: () => _openCatalog(context, 'food', location),
                    ),
                    const SizedBox(height: 12),
                    GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            crossAxisSpacing: 12,
                            mainAxisSpacing: 12,
                            childAspectRatio: 0.77,
                          ),
                      itemCount: foodProducts.length,
                      itemBuilder: (context, index) {
                        final product = foodProducts[index];
                        return _FoodGridCard(
                          product: product,
                          city: districtName,
                          locality: locality?.name ?? '',
                          localityId: locality?.id ?? '',
                          userId: userId,
                          onTap: () =>
                              _openFeaturedProduct(context, product, location),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),

            // SECTION 2: Fresh Groceries (9 Products in 3-column grid)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 22, 16, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _SectionHeader(
                      title: 'Fresh Groceries',
                      onSeeAll: () =>
                          _openCatalog(context, 'grocery', location),
                    ),
                    const SizedBox(height: 12),
                    GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 3,
                            crossAxisSpacing: 10,
                            mainAxisSpacing: 12,
                            childAspectRatio: 0.60,
                          ),
                      itemCount: groceryProducts.length,
                      itemBuilder: (context, index) {
                        final product = groceryProducts[index];
                        return _GroceryGridCard(
                          product: product,
                          city: districtName,
                          locality: locality?.name ?? '',
                          localityId: locality?.id ?? '',
                          userId: userId,
                          onTap: () =>
                              _openFeaturedProduct(context, product, location),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),

            // Order History & Shortcuts Section
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 22, 16, 32),
                child: Material(
                  color: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                    side: const BorderSide(color: Color(0xFFE2E8F0)),
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
                      const Divider(
                        height: 1,
                        indent: 18,
                        endIndent: 18,
                        color: Color(0xFFF1F5F9),
                      ),
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
                color: Color(0xFF0F5132),
              ),
              title: const Text('Food cart'),
              subtitle: Text(
                '$foodCount items · ${food.locality.isNotEmpty ? food.locality : food.district}',
              ),
              trailing: const Icon(Icons.chevron_right_rounded),
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
                color: Color(0xFF0F766E),
              ),
              title: const Text('Grocery cart'),
              subtitle: Text(
                '$groceryCount items · ${grocery.locality.isNotEmpty ? grocery.locality : grocery.district}',
              ),
              trailing: const Icon(Icons.chevron_right_rounded),
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
                      color: Color(0xFF0F5132),
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
                            color: Color(0xFF059669),
                          )
                        : const Icon(
                            Icons.schedule_outlined,
                            color: Color(0xFF94A3B8),
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

class _SectionHeader extends StatelessWidget {
  final String title;
  final VoidCallback onSeeAll;

  const _SectionHeader({required this.title, required this.onSeeAll});

  @override
  Widget build(BuildContext context) {
    final palette = context.abashyaka;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          title,
          style: AbashyakaTypography.sectionTitle(
            color: palette.textPrimary,
            fontSize: 16.5,
          ),
        ),
        InkWell(
          onTap: onSeeAll,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: palette.accentSurface,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'See all',
                  style: AbashyakaTypography.categoryLabel(
                    color: palette.accent,
                    fontSize: 12,
                  ).copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(width: 2),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 16,
                  color: palette.accent,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _HeroCategoryCard extends StatelessWidget {
  final String keyName;
  final String title;
  final String subtitle;
  final Color bgColor;
  final Color borderColor;
  final String imageAsset;
  final VoidCallback onTap;

  const _HeroCategoryCard({
    required this.keyName,
    required this.title,
    required this.subtitle,
    required this.bgColor,
    required this.borderColor,
    required this.imageAsset,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          key: ValueKey(keyName),
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(16),
                ),
                child: SizedBox(
                  height: 104,
                  width: double.infinity,
                  child: Image.asset(
                    imageAsset,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => Container(
                      color: bgColor,
                      child: Center(
                        child: Icon(
                          keyName.contains('food')
                              ? Icons.restaurant_rounded
                              : Icons.shopping_basket_rounded,
                          color: const Color(0xFF0F5132),
                          size: 36,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 10.5,
                        color: Color(0xFF64748B),
                        fontWeight: FontWeight.w500,
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

class _FoodGridCard extends ConsumerWidget {
  final PlatformCatalogProduct product;
  final String city;
  final String locality;
  final String localityId;
  final String userId;
  final VoidCallback onTap;

  const _FoodGridCard({
    required this.product,
    required this.city,
    required this.locality,
    required this.localityId,
    required this.userId,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scope = PlatformCartScope(
      userId: userId,
      vertical: 'food',
      localityId: localityId,
      locality: locality,
      district: city,
    );
    final cart = ref.watch(platformCartProvider(scope));
    final defaultVariant = product.variants.isNotEmpty
        ? product.variants.first
        : null;
    final currentQty = defaultVariant != null
        ? (cart.lines[defaultVariant.id]?.quantity ?? 0)
        : 0;
    final price = defaultVariant != null
        ? defaultVariant.priceMinor
        : (product.lowestPriceMinor ?? 14900);
    final imageUrl = product.imageUrls.isNotEmpty
        ? product.imageUrls.first
        : null;

    final palette = context.abashyaka;
    final unitBadge = defaultVariant?.unitLabel.isNotEmpty == true
        ? defaultVariant!.unitLabel
        : '1 Serving';

    return Container(
      decoration: BoxDecoration(
        color: palette.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: palette.border),
        boxShadow: palette.isDark ? null : AbashyakaShadows.card,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(18),
                ),
                child: SizedBox(
                  height: 118,
                  width: double.infinity,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (imageUrl != null && imageUrl.isNotEmpty)
                        CachedNetworkImage(
                          imageUrl: imageUrl,
                          fit: BoxFit.cover,
                          placeholder: (_, _) => Container(
                            color: palette.cardElevated,
                            child: Center(
                              child: Icon(
                                Icons.restaurant_rounded,
                                color: palette.textMuted,
                                size: 28,
                              ),
                            ),
                          ),
                          errorWidget: (_, _, _) => Container(
                            color: palette.accentSurface,
                            child: Icon(
                              Icons.restaurant_rounded,
                              color: palette.accent,
                              size: 36,
                            ),
                          ),
                        )
                      else
                        Container(
                          color: palette.accentSurface,
                          child: Icon(
                            Icons.restaurant_rounded,
                            color: palette.accent,
                            size: 36,
                          ),
                        ),
                      // Subtle bottom scrim for depth
                      Positioned.fill(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.transparent,
                                Colors.black.withValues(alpha: 0.42),
                              ],
                              stops: const [0.55, 1.0],
                            ),
                          ),
                        ),
                      ),
                      // Top-left portion badge
                      Positioned(
                        left: 8,
                        top: 8,
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
                              fontSize: 9.5,
                            ),
                          ),
                        ),
                      ),
                      // Top-right chef/trending badge
                      Positioned(
                        right: 8,
                        top: 8,
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: const BoxDecoration(
                            color: Color(0xBF0B1320),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.local_fire_department_rounded,
                            size: 13,
                            color: AbashyakaColors.metallicGold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 9, 10, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      product.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AbashyakaTypography.cardTitle(
                        color: palette.textPrimary,
                        fontSize: 13,
                      ).copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      product.categoryName.isNotEmpty
                          ? product.categoryName
                          : 'Restaurant menu',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AbashyakaTypography.supportingText(
                        color: palette.textMuted,
                        fontSize: 11,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '₹${(price / 100).toStringAsFixed(0)}',
                          style: AbashyakaTypography.cardTitle(
                            color: palette.textPrimary,
                            fontSize: 14.5,
                          ).copyWith(fontWeight: FontWeight.w800),
                        ),
                        if (currentQty == 0)
                          SizedBox(
                            height: 28,
                            width: 64,
                            child: OutlinedButton(
                              onPressed: () {
                                HapticFeedback.lightImpact();
                                if (defaultVariant != null) {
                                  ref
                                      .read(
                                        platformCartProvider(scope).notifier,
                                      )
                                      .add(product, defaultVariant);
                                }
                              },
                              style: OutlinedButton.styleFrom(
                                backgroundColor: palette.accentSurface,
                                side: BorderSide(
                                  color: palette.accent,
                                  width: 1.2,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                padding: EdgeInsets.zero,
                              ),
                              child: Text(
                                'ADD +',
                                style: AbashyakaTypography.buttonText(
                                  color: palette.accent,
                                  fontSize: 11,
                                ),
                              ),
                            ),
                          )
                        else
                          Container(
                            height: 28,
                            width: 72,
                            decoration: BoxDecoration(
                              gradient: AbashyakaGradients.metallicButton,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                              children: [
                                InkWell(
                                  onTap: () {
                                    HapticFeedback.selectionClick();
                                    if (defaultVariant != null) {
                                      ref
                                          .read(
                                            platformCartProvider(scope)
                                                .notifier,
                                          )
                                          .setQuantity(
                                            defaultVariant.id,
                                            currentQty - 1,
                                          );
                                    }
                                  },
                                  child: const Icon(
                                    Icons.remove,
                                    color: AbashyakaColors.pureWhite,
                                    size: 14,
                                  ),
                                ),
                                Text(
                                  '$currentQty',
                                  style: AbashyakaTypography.buttonText(
                                    color: AbashyakaColors.pureWhite,
                                    fontSize: 12,
                                  ),
                                ),
                                InkWell(
                                  onTap: () {
                                    HapticFeedback.selectionClick();
                                    if (defaultVariant != null) {
                                      ref
                                          .read(
                                            platformCartProvider(scope)
                                                .notifier,
                                          )
                                          .add(product, defaultVariant);
                                    }
                                  },
                                  child: const Icon(
                                    Icons.add,
                                    color: AbashyakaColors.pureWhite,
                                    size: 14,
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
            ],
          ),
        ),
      ),
    );
  }
}

class _GroceryGridCard extends ConsumerWidget {
  final PlatformCatalogProduct product;
  final String city;
  final String locality;
  final String localityId;
  final String userId;
  final VoidCallback onTap;

  const _GroceryGridCard({
    required this.product,
    required this.city,
    required this.locality,
    required this.localityId,
    required this.userId,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scope = PlatformCartScope(
      userId: userId,
      vertical: 'grocery',
      localityId: localityId,
      locality: locality,
      district: city,
    );
    final cart = ref.watch(platformCartProvider(scope));
    final defaultVariant = product.variants.isNotEmpty
        ? product.variants.first
        : null;
    final currentQty = defaultVariant != null
        ? (cart.lines[defaultVariant.id]?.quantity ?? 0)
        : 0;
    final price = defaultVariant != null
        ? defaultVariant.priceMinor
        : (product.lowestPriceMinor ?? 2500);
    final unitLabel = defaultVariant?.unitLabel ?? '500 g';
    final imageUrl = product.imageUrls.isNotEmpty
        ? product.imageUrls.first
        : null;

    final palette = context.abashyaka;

    return Container(
      decoration: BoxDecoration(
        color: palette.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: palette.border),
        boxShadow: palette.isDark ? null : AbashyakaShadows.card,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(16),
                ),
                child: Container(
                  height: 84,
                  width: double.infinity,
                  color: palette.cardElevated,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (imageUrl != null && imageUrl.isNotEmpty)
                        CachedNetworkImage(
                          imageUrl: imageUrl,
                          fit: BoxFit.cover,
                          placeholder: (_, _) => Container(
                            color: palette.cardElevated,
                            child: Center(
                              child: Icon(
                                Icons.shopping_basket_rounded,
                                color: palette.textMuted,
                                size: 24,
                              ),
                            ),
                          ),
                          errorWidget: (_, _, _) => Icon(
                            Icons.shopping_basket_rounded,
                            color: palette.accent,
                            size: 28,
                          ),
                        )
                      else
                        Icon(
                          Icons.shopping_basket_rounded,
                          color: palette.accent,
                          size: 28,
                        ),
                      // Top-left weight/pack pill
                      Positioned(
                        left: 6,
                        top: 6,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: palette.card.withValues(alpha: 0.92),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: palette.border),
                          ),
                          child: Text(
                            unitLabel,
                            style: AbashyakaTypography.categoryLabel(
                              color: palette.accent,
                              fontSize: 9,
                            ).copyWith(fontWeight: FontWeight.w700),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 7, 8, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      product.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AbashyakaTypography.cardTitle(
                        color: palette.textPrimary,
                        fontSize: 11.5,
                      ).copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '₹${(price / 100).toStringAsFixed(0)}',
                      style: AbashyakaTypography.cardTitle(
                        color: palette.textPrimary,
                        fontSize: 13,
                      ).copyWith(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 6),
                    if (currentQty == 0)
                      SizedBox(
                        height: 27,
                        width: double.infinity,
                        child: OutlinedButton(
                          onPressed: () {
                            HapticFeedback.lightImpact();
                            if (defaultVariant != null) {
                              ref
                                  .read(platformCartProvider(scope).notifier)
                                  .add(product, defaultVariant);
                            }
                          },
                          style: OutlinedButton.styleFrom(
                            backgroundColor: palette.accentSurface,
                            side: BorderSide(
                              color: palette.accent,
                              width: 1.2,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            padding: EdgeInsets.zero,
                          ),
                          child: Text(
                            'ADD +',
                            style: AbashyakaTypography.buttonText(
                              color: palette.accent,
                              fontSize: 10.5,
                            ),
                          ),
                        ),
                      )
                    else
                      Container(
                        height: 27,
                        width: double.infinity,
                        decoration: BoxDecoration(
                          gradient: AbashyakaGradients.metallicButton,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            InkWell(
                              onTap: () {
                                HapticFeedback.selectionClick();
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
                              child: const Icon(
                                Icons.remove,
                                color: AbashyakaColors.pureWhite,
                                size: 12,
                              ),
                            ),
                            Text(
                              '$currentQty',
                              style: AbashyakaTypography.buttonText(
                                color: AbashyakaColors.pureWhite,
                                fontSize: 11,
                              ),
                            ),
                            InkWell(
                              onTap: () {
                                HapticFeedback.selectionClick();
                                if (defaultVariant != null) {
                                  ref
                                      .read(
                                        platformCartProvider(scope).notifier,
                                      )
                                      .add(product, defaultVariant);
                                }
                              },
                              child: const Icon(
                                Icons.add,
                                color: AbashyakaColors.pureWhite,
                                size: 12,
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
    );
  }
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
  Widget build(BuildContext context) {
    final palette = context.abashyaka;
    return ListTile(
      key: ValueKey(keyName),
      minVerticalPadding: 13,
      leading: CircleAvatar(
        backgroundColor: palette.accentSurface,
        child: Icon(icon, color: palette.accent),
      ),
      title: Text(
        title,
        style: AbashyakaTypography.cardTitle(color: palette.textPrimary),
      ),
      subtitle: Text(
        subtitle,
        style: AbashyakaTypography.supportingText(color: palette.textMuted),
      ),
      trailing: Icon(Icons.chevron_right_rounded, color: palette.textMuted),
      onTap: onTap,
    );
  }
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
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
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
