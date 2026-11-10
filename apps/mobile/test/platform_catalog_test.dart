import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grepmind_mobile/core/models/business.dart';
import 'package:grepmind_mobile/core/models/platform_catalog.dart';
import 'package:grepmind_mobile/core/network/api_client.dart';
import 'package:grepmind_mobile/core/providers/app_provider.dart';
import 'package:grepmind_mobile/core/providers/platform_catalog_provider.dart';
import 'package:grepmind_mobile/core/screens/order_shopping_hub_screen.dart';
import 'package:grepmind_mobile/core/screens/platform_catalog_screen.dart';
import 'package:grepmind_mobile/core/screens/platform_product_detail_screen.dart';

const testFoodProduct = PlatformCatalogProduct(
  id: 'product-1',
  sku: 'FOOD-1',
  categoryId: 'category-1',
  categoryName: 'Meals',
  categorySlug: 'meals',
  vertical: 'food',
  name: 'Odia thali',
  description: 'A catalog product',
  imageUrls: ['/media/food.png'],
  variants: [
    PlatformCatalogVariant(
      id: 'variant-1',
      name: 'Regular',
      unitLabel: 'plate',
      priceMinor: 12550,
      currency: 'INR',
      priceRevision: 1,
    ),
  ],
);

void main() {
  setUpAll(() => apiClient.init());

  test('platform catalog parses images and integer minor-unit variants', () {
    final parsed = PlatformCatalogProduct.fromJson({
      'id': 'p',
      'sku': 'SKU',
      'category_id': 'c',
      'category_name': 'Meals',
      'category_slug': 'meals',
      'vertical': 'food',
      'name': 'Meal',
      'description': '',
      'image_urls': ['/media/a.png', '/media/b.png'],
      'variants': [
        {
          'id': 'v1',
          'name': 'Small',
          'unit_label': 'plate',
          'price_minor': 10050,
          'currency': 'INR',
          'price_revision': 1,
        },
        {
          'id': 'v2',
          'name': 'Large',
          'unit_label': 'plate',
          'price_minor': 15000,
          'currency': 'INR',
          'price_revision': 2,
        },
      ],
    });

    expect(parsed.imageUrls, ['/media/a.png', '/media/b.png']);
    expect(parsed.lowestPriceMinor, 10050);
    expect(parsed.variants.last.priceRevision, 2);
  });

  testWidgets(
    'Orders hub opens catalog and exact product details with a separate platform cart',
    (tester) async {
      final container = _container();
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: OrderShoppingHubScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Order on Grepmind'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('orders_food_catalog')));
      await tester.pumpAndSettle();
      expect(find.byType(PlatformCatalogScreen), findsOneWidget);
      expect(find.text('Odia thali'), findsOneWidget);

      await tester.drag(
        find.byKey(const ValueKey('platform_catalog_scroll')),
        const Offset(0, -250),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Odia thali'));
      await tester.pumpAndSettle();
      expect(find.byType(PlatformProductDetailScreen), findsOneWidget);
      expect(find.textContaining('₹125.50'), findsOneWidget);
      final cartButton = tester.widget<FilledButton>(
        find.byKey(const ValueKey('platform_open_cart')),
      );
      expect(cartButton.onPressed, isNull);

      await tester.pumpWidget(const SizedBox.shrink());
      container.dispose();
    },
  );

  testWidgets('empty platform catalog shows an honest availability state', (
    tester,
  ) async {
    final container = _container(empty: true);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: PlatformCatalogScreen(vertical: 'grocery', city: 'Jajpur'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('No products available here yet'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    container.dispose();
  });

  testWidgets(
    'Orders locality picker resets locality across districts and filters by ID',
    (tester) async {
      final repository = _TestCatalogRepository(empty: true);
      final storage = _TestDeliveryLocationStorage(
        const DeliveryLocationSelection(
          district: 'Cuttack',
          localityId: 'kuanpal-id',
          locality: 'Kuanpal',
        ),
      );
      final container = _container(repository: repository, storage: storage);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: OrderShoppingHubScreen()),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('orders_delivery_location')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('delivery-district-jajpur-id')),
      );
      await tester.pumpAndSettle();
      expect(storage.value?.localityId, isEmpty);
      await tester.tap(
        find.byKey(const ValueKey('delivery-locality-jajpur-id-chhatia-id')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Chhatia, Jajpur'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('orders_food_catalog')));
      await tester.pumpAndSettle();
      expect(repository.lastProductsQuery?.city, 'Jajpur');
      expect(repository.lastProductsQuery?.localityId, 'chhatia-id');
      await tester.pumpWidget(const SizedBox.shrink());
      container.dispose();
    },
  );
}

ProviderContainer _container({
  bool empty = false,
  _TestCatalogRepository? repository,
  _TestDeliveryLocationStorage? storage,
}) => ProviderContainer(
  overrides: [
    appLocationProvider.overrideWith((ref) => _TestLocationNotifier()),
    authProvider.overrideWith((ref) => _TestAuthNotifier()),
    platformCatalogRepositoryProvider.overrideWithValue(
      repository ?? _TestCatalogRepository(empty: empty),
    ),
    deliveryLocationStorageProvider.overrideWithValue(
      storage ?? _TestDeliveryLocationStorage(null),
    ),
  ],
);

class _TestLocationNotifier extends LocationNotifier {
  _TestLocationNotifier() : super() {
    setLocation(
      const AppLocation(
        cityName: 'Cuttack',
        localityName: 'Badambadi',
        latitude: 20.46,
        longitude: 85.88,
      ),
    );
  }

  @override
  Future<void> loadDefaultLocation() async {}
}

class _TestAuthNotifier extends AuthNotifier {
  _TestAuthNotifier() : super.forTesting() {
    state = const AuthState(
      user: AppUser(
        id: 'customer-1',
        phoneE164: '+919876543210',
        displayName: 'Customer',
        status: 'active',
        preferredLanguage: 'en',
        roles: ['customer'],
      ),
      activeRole: 'customer',
    );
  }
}

class _TestCatalogRepository extends PlatformCatalogRepository {
  final bool empty;
  PlatformCatalogQuery? lastProductsQuery;
  _TestCatalogRepository({required this.empty});

  @override
  Future<List<DeliveryDistrict>> locations() async => const [
    DeliveryDistrict(
      id: 'cuttack-id',
      name: 'Cuttack',
      localities: [
        DeliveryLocality(
          id: 'kuanpal-id',
          name: 'Kuanpal',
          deliveryEnabled: true,
        ),
      ],
    ),
    DeliveryDistrict(
      id: 'jajpur-id',
      name: 'Jajpur',
      localities: [
        DeliveryLocality(
          id: 'chhatia-id',
          name: 'Chhatia',
          deliveryEnabled: true,
        ),
      ],
    ),
  ];

  @override
  Future<List<PlatformCatalogCategory>> categories(
    PlatformCatalogQuery query,
  ) async => const [
    PlatformCatalogCategory(
      id: 'category-1',
      vertical: 'food',
      slug: 'meals',
      name: 'Meals',
    ),
  ];

  @override
  Future<PlatformCatalogPage> products(
    PlatformCatalogQuery query, {
    int offset = 0,
  }) async {
    lastProductsQuery = query;
    return PlatformCatalogPage(
      products: empty ? const [] : const [testFoodProduct],
      hasMore: false,
      count: empty ? 0 : 1,
    );
  }

  @override
  Future<PlatformCatalogProduct> product(
    String id,
    PlatformCatalogQuery query,
  ) async => testFoodProduct;
}

class _TestDeliveryLocationStorage extends DeliveryLocationStorage {
  DeliveryLocationSelection? value;
  _TestDeliveryLocationStorage(this.value);
  @override
  Future<DeliveryLocationSelection?> read() async => value;
  @override
  Future<void> write(DeliveryLocationSelection selection) async =>
      value = selection;
  @override
  Future<void> writeDistrict(String district) async =>
      value = DeliveryLocationSelection(
        district: district,
        localityId: '',
        locality: '',
      );
  @override
  Future<void> clear() async => value = null;
}
