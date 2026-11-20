import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grepmind_mobile/core/network/api_client.dart';
import 'package:grepmind_mobile/core/screens/merchant_catalog_screen.dart';

void main() {
  setUpAll(() {
    apiClient.init(baseUrl: 'https://catalog-phase02d.test/api/v1');
  });

  setUp(() => apiClient.dio.interceptors.clear());

  testWidgets('Phase 02D: Screen 12 catalog renders product cards with price, MRP and discount',
      (tester) async {
    final rawProducts = [
      {
        'id': 'prod-001',
        'business_id': 'biz-01',
        'name': 'Asian Paints Apex 20L',
        'description': 'Weatherproof exterior emulsion paint',
        'price': 4500,
        'stock_status': 'in_stock',
        'inventory_mode': 'finite',
        'available_quantity': 12,
        'is_published': true,
      },
      {
        'id': 'prod-002',
        'business_id': 'biz-01',
        'name': 'Brass Padlock 65mm',
        'description': 'Hardened steel shackle 3 keys',
        'price': 320,
        'stock_status': 'limited',
        'inventory_mode': 'finite',
        'available_quantity': 3,
        'is_published': true,
      },
    ];

    apiClient.dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          if (options.path.endsWith('/merchant/products')) {
            return handler.resolve(
              Response(
                requestOptions: options,
                statusCode: 200,
                data: {'data': rawProducts},
              ),
            );
          }
          if (options.path.endsWith('/merchant/services')) {
            return handler.resolve(
              Response(
                requestOptions: options,
                statusCode: 200,
                data: {'data': []},
              ),
            );
          }
          return handler.reject(
            DioException(requestOptions: options, message: 'Unexpected'),
          );
        },
      ),
    );

    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: MerchantCatalogScreen()),
      ),
    );
    await tester.pumpAndSettle();

    // Verify Title & Search
    expect(find.text('Catalog Management'), findsOneWidget);
    expect(find.byKey(const Key('search_catalog_input')), findsOneWidget);

    // Verify Product 1 Card
    expect(find.text('Asian Paints Apex 20L'), findsOneWidget);
    expect(find.text('Weatherproof exterior emulsion paint'), findsOneWidget);
    expect(find.text('₹4,500'), findsOneWidget);
    expect(find.text('20% OFF'), findsNWidgets(2)); // Both products have 20% OFF pill
    expect(find.text('In Stock'), findsNWidgets(2)); // Filter chip + Product badge
    expect(find.text('Qty: 12'), findsOneWidget);

    // Verify Product 2 Card
    expect(find.text('Brass Padlock 65mm'), findsOneWidget);
    expect(find.text('₹320'), findsOneWidget);
    expect(find.text('Limited'), findsNWidgets(2)); // Filter chip + Product badge
    expect(find.text('Qty: 3'), findsOneWidget);
  });

  testWidgets('Phase 02D: Screen 14 quick stock steppers increment and decrement inventory',
      (tester) async {
    final requestedUpdates = <Map<String, dynamic>>[];
    final rawProduct = {
      'id': 'prod-001',
      'business_id': 'biz-01',
      'name': 'Dr. Fixit Waterproofing 1L',
      'price': 240,
      'stock_status': 'in_stock',
      'inventory_mode': 'finite',
      'available_quantity': 10,
      'is_published': true,
    };

    apiClient.dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          if (options.method == 'PATCH' && options.path.contains('/merchant/products/')) {
            requestedUpdates.add(options.data as Map<String, dynamic>);
            return handler.resolve(
              Response(
                requestOptions: options,
                statusCode: 200,
                data: {'data': {'id': 'prod-001'}},
              ),
            );
          }
          if (options.path.endsWith('/merchant/products')) {
            return handler.resolve(
              Response(
                requestOptions: options,
                statusCode: 200,
                data: {
                  'data': [rawProduct]
                },
              ),
            );
          }
          if (options.path.endsWith('/merchant/services')) {
            return handler.resolve(
              Response(
                requestOptions: options,
                statusCode: 200,
                data: {'data': []},
              ),
            );
          }
          return handler.reject(
            DioException(requestOptions: options, message: 'Unexpected'),
          );
        },
      ),
    );

    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: MerchantCatalogScreen()),
      ),
    );
    await tester.pumpAndSettle();

    // Verify stepper buttons exist
    final incBtn = find.byKey(const Key('increment_stock_prod-001'));
    final decBtn = find.byKey(const Key('decrement_stock_prod-001'));
    expect(incBtn, findsOneWidget);
    expect(decBtn, findsOneWidget);

    // Tap Increment (+)
    await tester.tap(incBtn);
    await tester.pumpAndSettle();

    expect(requestedUpdates.isNotEmpty, isTrue);
    expect(requestedUpdates.last['available_quantity'], 11);
    expect(requestedUpdates.last['stock_status'], 'in_stock');

    // Tap Decrement (-)
    await tester.tap(decBtn);
    await tester.pumpAndSettle();

    expect(requestedUpdates.length, 2);
    expect(requestedUpdates.last['available_quantity'], 9);
  });

  testWidgets('Phase 02D: Screen 13 Add Product modal accepts MRP, unit chip, and price',
      (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: MerchantCatalogScreen()),
      ),
    );
    await tester.pumpAndSettle();

    // Tap Add Product FAB
    await tester.tap(find.byKey(const Key('add_product_fab')));
    await tester.pumpAndSettle();

    // Verify Screen 13 modal fields
    expect(find.text('Add New Product'), findsOneWidget);
    expect(find.byKey(const Key('modal_product_name')), findsOneWidget);
    expect(find.byKey(const Key('modal_product_price')), findsOneWidget);
    expect(find.byKey(const Key('modal_product_mrp')), findsOneWidget);
    expect(find.text('Unit / Measure'), findsOneWidget);
    expect(find.text('1 kg'), findsOneWidget);
    expect(find.text('500 g'), findsOneWidget);

    // Enter product data
    await tester.enterText(find.byKey(const Key('modal_product_name')), 'Cement Primer 4L');
    await tester.enterText(find.byKey(const Key('modal_product_price')), '480');
    await tester.enterText(find.byKey(const Key('modal_product_mrp')), '600');
    await tester.pump();

    expect(find.text('Cement Primer 4L'), findsOneWidget);
    expect(find.text('480'), findsOneWidget);
    expect(find.text('600'), findsOneWidget);

    // Select Unit Chip
    await tester.tap(find.text('500 g'));
    await tester.pump();

    // Close modal
    await tester.tap(find.byKey(const Key('modal_product_close_btn')));
    await tester.pumpAndSettle();
    expect(find.text('Add New Product'), findsNothing);
  });
}
